// Emscripten JavaScript interop for Web Worker management
// This provides the bridge between Zig code and JavaScript Web Worker APIs

#ifdef __EMSCRIPTEN__

#include <emscripten.h>
#include <stdint.h>

// JavaScript code for Web Worker management
// This will be injected into the page

EM_JS(int, js_worker_pool_create, (int num_workers), {
    // Create worker pool in JavaScript
    if (!Module.workerPool) {
        Module.workerPool = {
            workers: [],
            nextWorkerId: 0,
            pendingWork: new Map(),
            nextWorkId: 0,
            workerScript: null,
            wasmBytes: null,
            initialized: false
        };
    }

    const pool = Module.workerPool;

    // Get WASM bytes for workers to load
    if (!pool.wasmBytes && Module.wasmBinary) {
        pool.wasmBytes = Module.wasmBinary;
    }

    // Create workers
    for (let i = 0; i < num_workers; i++) {
        try {
            // Create worker from inline script
            const workerCode = Module.workerHarnessCode || `
                // Inline worker harness
                let wasmInstance = null;
                let isInitialized = false;

                self.onmessage = async function(event) {
                    const msg = event.data;

                    if (msg.type === 'init') {
                        try {
                            const wasmModule = await WebAssembly.compile(msg.wasmBytes);
                            const imports = {
                                env: {
                                    memory: msg.memory || new WebAssembly.Memory({initial: 256, maximum: 256})
                                }
                            };
                            wasmInstance = await WebAssembly.instantiate(wasmModule, imports);

                            if (wasmInstance.exports._worker_init) {
                                wasmInstance.exports._worker_init();
                            }

                            isInitialized = true;
                            self.postMessage({type: 'ready', workerId: msg.workerId});
                        } catch (error) {
                            self.postMessage({type: 'error', error: error.message});
                        }
                    } else if (msg.type === 'work') {
                        if (!isInitialized) {
                            self.postMessage({type: 'error', workId: msg.workId, error: 'Worker not initialized'});
                            return;
                        }

                        try {
                            if (wasmInstance.exports._worker_dispatch) {
                                wasmInstance.exports._worker_dispatch(msg.workFnId, msg.contextPtr);
                            }
                            self.postMessage({type: 'complete', workId: msg.workId});
                        } catch (error) {
                            self.postMessage({type: 'error', workId: msg.workId, error: error.message});
                        }
                    }
                };
            `;

            const blob = new Blob([workerCode], {type: 'application/javascript'});
            const workerUrl = URL.createObjectURL(blob);
            const worker = new Worker(workerUrl);

            const workerId = pool.nextWorkerId++;

            worker.onmessage = function(event) {
                const msg = event.data;

                if (msg.type === 'complete' || msg.type === 'error') {
                    const pending = pool.pendingWork.get(msg.workId);
                    if (pending) {
                        // Clear timeout if set
                        if (pending.timeoutId) {
                            clearTimeout(pending.timeoutId);
                        }

                        // Call back into WASM
                        Module.ccall('_worker_complete_callback', 'void', ['number', 'number'],
                            [msg.workId, msg.type === 'error' ? 1 : 0]);
                        pool.pendingWork.delete(msg.workId);
                    }
                } else if (msg.type === 'ready') {
                    console.log('Worker ' + workerId + ' ready');
                    // Mark worker as healthy
                    for (const info of pool.workers) {
                        if (info.id === workerId) {
                            info.healthy = true;
                            info.lastHeartbeat = Date.now();
                            break;
                        }
                    }
                }
            };

            worker.onerror = function(error) {
                console.error('Worker ' + workerId + ' error:', error);
                // Mark worker as unhealthy
                for (const info of pool.workers) {
                    if (info.id === workerId) {
                        info.healthy = false;
                        break;
                    }
                }
            };

            // Initialize worker with WASM
            worker.postMessage({
                type: 'init',
                workerId: workerId,
                wasmBytes: pool.wasmBytes,
                memory: Module.wasmMemory
            });

            pool.workers.push({
                id: workerId,
                worker: worker,
                busy: false,
                healthy: false,  // Will be set to true when worker sends 'ready' message
                lastHeartbeat: Date.now()
            });

        } catch (error) {
            console.error('Failed to create worker:', error);
            return -1;
        }
    }

    pool.initialized = true;
    return pool.workers.length;
});

EM_JS(void, js_worker_pool_destroy, (), {
    if (Module.workerPool) {
        for (const workerInfo of Module.workerPool.workers) {
            workerInfo.worker.terminate();
        }
        Module.workerPool.workers = [];
    }
});

EM_JS(int, js_worker_submit, (int work_id, int work_fn_id, int context_ptr, int context_size, int timeout_ms), {
    if (!Module.workerPool || !Module.workerPool.initialized) {
        console.error('Worker pool not initialized');
        return -1;
    }

    const pool = Module.workerPool;

    // Find available and healthy worker
    let workerInfo = null;
    for (const info of pool.workers) {
        if (!info.busy && info.healthy) {
            workerInfo = info;
            break;
        }
    }

    if (!workerInfo) {
        // Try to find any available worker even if not marked healthy yet
        for (const info of pool.workers) {
            if (!info.busy) {
                workerInfo = info;
                break;
            }
        }

        if (!workerInfo) {
            console.warn('No available workers');
            return -2;
        }
    }

    // Mark worker as busy
    workerInfo.busy = true;

    // Copy context data from WASM memory
    // Note: We create a copy because workers have separate memory spaces
    const contextData = new Uint8Array(Module.HEAPU8.buffer, context_ptr, context_size);
    const contextCopy = new Uint8Array(contextData.length);
    contextCopy.set(contextData);

    // Set up timeout if requested
    let timeoutId = null;
    if (timeout_ms > 0) {
        timeoutId = setTimeout(function() {
            console.warn('Work item ' + work_id + ' timed out after ' + timeout_ms + 'ms');
            // Mark worker as available again
            workerInfo.busy = false;
            workerInfo.healthy = false;  // Mark as unhealthy since it timed out

            // Call completion callback with error
            if (pool.pendingWork.has(work_id)) {
                Module.ccall('_worker_complete_callback', 'void', ['number', 'number'],
                    [work_id, 2]);  // Error code 2 for timeout
                pool.pendingWork.delete(work_id);
            }
        }, timeout_ms);
    }

    // Register work item
    pool.pendingWork.set(work_id, {
        workerId: workerInfo.id,
        startTime: performance.now(),
        contextPtr: context_ptr,
        contextSize: context_size,
        timeoutId: timeoutId
    });

    // Send work to worker
    // We pass the data as a transferable ArrayBuffer for better performance
    workerInfo.worker.postMessage({
        type: 'work',
        workId: work_id,
        workFnId: work_fn_id,
        contextData: contextCopy.buffer  // Transfer the buffer
    }, [contextCopy.buffer]);  // Transferable list

    return 0;
});

EM_JS(int, js_worker_get_available_count, (), {
    if (!Module.workerPool) return 0;

    let available = 0;
    for (const info of Module.workerPool.workers) {
        if (!info.busy) available++;
    }
    return available;
});

EM_JS(void, js_worker_mark_available, (int work_id), {
    if (!Module.workerPool) return;

    const pool = Module.workerPool;
    const pending = pool.pendingWork.get(work_id);

    if (pending) {
        // Find and mark worker as available
        for (const info of pool.workers) {
            if (pending.workerId === info.id) {
                info.busy = false;
                break;
            }
        }
    }
});

// Worker completion callback - called from JavaScript
// Must be exported from WASM
// The actual implementation is handled by Zig code (_worker_complete_callback in worker_pool_full.zig)
// This is just a forward declaration for the Emscripten build
extern void _worker_complete_callback(uint32_t work_id, int error_code);

#endif // __EMSCRIPTEN__
