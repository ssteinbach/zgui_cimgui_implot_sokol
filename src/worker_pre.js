// Pre-JS file for Web Worker support
// This code runs before the main WASM module is loaded

// Load the worker harness code
Module.workerHarnessCode = `
// Web Worker harness for ZIIS Worker Pool
let wasmInstance = null;
let wasmModule = null;
let wasmMemory = null;
let isInitialized = false;

const MSG_INIT = 'init';
const MSG_WORK = 'work';
const MSG_COMPLETE = 'complete';
const MSG_ERROR = 'error';

async function initialize(wasmModuleBytes, memoryDescriptor) {
    try {
        if (memoryDescriptor) {
            wasmMemory = new WebAssembly.Memory(memoryDescriptor);
        }

        wasmModule = await WebAssembly.compile(wasmModuleBytes);

        const importObject = {
            env: {
                memory: wasmMemory
            },
        };

        const instance = await WebAssembly.instantiate(wasmModule, importObject);
        wasmInstance = instance;

        if (wasmInstance.exports._worker_init) {
            wasmInstance.exports._worker_init();
        }

        isInitialized = true;

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
        if (wasmInstance.exports._worker_dispatch) {
            const contextSize = contextDataBuffer.byteLength;
            const contextPtr = wasmInstance.exports.malloc(contextSize);

            if (!contextPtr) {
                throw new Error('Failed to allocate memory for context');
            }

            try {
                const contextView = new Uint8Array(contextDataBuffer);
                const wasmMemoryView = new Uint8Array(wasmMemory.buffer);
                wasmMemoryView.set(contextView, contextPtr);

                const result = wasmInstance.exports._worker_dispatch(
                    workFnId,
                    contextPtr
                );

                self.postMessage({
                    type: MSG_COMPLETE,
                    workId: workId,
                    result: result
                });
            } finally {
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

self.onerror = function(error) {
    self.postMessage({
        type: MSG_ERROR,
        error: error.message,
        phase: 'runtime'
    });
};
`;

console.log('Web Worker harness code loaded');
