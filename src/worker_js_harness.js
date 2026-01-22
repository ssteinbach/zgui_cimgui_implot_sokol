// Web Worker harness for ZIIS Worker Pool
// This script runs inside each Web Worker and handles:
// - Loading the WASM module
// - Receiving work messages from main thread
// - Dispatching to Zig work functions
// - Sending completion messages back

// Worker state
let wasmInstance = null;
let wasmModule = null;
let wasmMemory = null;
let isInitialized = false;

// Message types
const MSG_INIT = 'init';
const MSG_WORK = 'work';
const MSG_COMPLETE = 'complete';
const MSG_ERROR = 'error';

// Initialize the worker with WASM module
async function initialize(wasmModuleBytes, memoryDescriptor) {
    try {
        // Create shared memory if provided, or create new memory
        if (memoryDescriptor) {
            wasmMemory = new WebAssembly.Memory(memoryDescriptor);
        }

        // Compile the WASM module
        wasmModule = await WebAssembly.compile(wasmModuleBytes);

        // Instantiate with imports
        const importObject = {
            env: {
                memory: wasmMemory
            },
            // Add other imports as needed (e.g., for sokol, etc.)
        };

        const instance = await WebAssembly.instantiate(wasmModule, importObject);
        wasmInstance = instance;

        // Call WASM initialization if it exists
        if (wasmInstance.exports._worker_init) {
            wasmInstance.exports._worker_init();
        }

        isInitialized = true;

        // Notify main thread that worker is ready
        self.postMessage({
            type: MSG_COMPLETE,
            subtype: 'init',
            workerId: self.name || 0
        });

    } catch (error) {
        self.postMessage({
            type: MSG_ERROR,
            error: error.message,
            phase: 'initialization'
        });
    }
}

// Execute a work item
function executeWork(workId, workFnId, contextDataBuffer) {
    if (!isInitialized || !wasmInstance) {
        self.postMessage({
            type: MSG_ERROR,
            workId: workId,
            error: 'Worker not initialized'
        });
        return;
    }

    try {
        // Call the work dispatcher in WASM
        // This will look up the function by ID and execute it
        if (wasmInstance.exports._worker_dispatch) {
            // Allocate memory in worker's WASM memory for context data
            const contextSize = contextDataBuffer.byteLength;
            const contextPtr = wasmInstance.exports.malloc(contextSize);

            if (!contextPtr) {
                throw new Error('Failed to allocate memory for context');
            }

            try {
                // Copy context data into WASM memory
                const contextView = new Uint8Array(contextDataBuffer);
                const wasmMemoryView = new Uint8Array(wasmMemory.buffer);
                wasmMemoryView.set(contextView, contextPtr);

                // Call the dispatcher with function ID and context pointer
                const result = wasmInstance.exports._worker_dispatch(
                    workFnId,
                    contextPtr
                );

                // Send completion message
                self.postMessage({
                    type: MSG_COMPLETE,
                    workId: workId,
                    result: result
                });
            } finally {
                // Free the allocated memory
                if (wasmInstance.exports.free) {
                    wasmInstance.exports.free(contextPtr);
                }
            }
        } else {
            throw new Error('_worker_dispatch export not found in WASM');
        }

    } catch (error) {
        self.postMessage({
            type: MSG_ERROR,
            workId: workId,
            error: error.message
        });
    }
}

// Main message handler
self.onmessage = function(event) {
    const msg = event.data;

    switch (msg.type) {
        case MSG_INIT:
            initialize(msg.wasmBytes, msg.memoryDescriptor);
            break;

        case MSG_WORK:
            executeWork(msg.workId, msg.workFnId, msg.contextData || msg.contextDataBuffer);
            break;

        default:
            console.warn('Unknown message type:', msg.type);
    }
};

// Handle errors
self.onerror = function(error) {
    self.postMessage({
        type: MSG_ERROR,
        error: error.message,
        phase: 'runtime'
    });
};
