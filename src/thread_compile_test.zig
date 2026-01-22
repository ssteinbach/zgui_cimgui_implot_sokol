//! Compile-only verification for WASM target
//! This file just ensures that thread.zig compiles correctly on WASM
//! Full tests run on native platforms via thread_test.zig

const thread = @import("thread.zig");

// Just reference the types to ensure they compile
comptime {
    _ = thread.Thread;
    _ = thread.TaskQueue;
    _ = thread.HAS_THREADS;
    _ = thread.IS_WASM;
}

pub fn main() void {
    // Minimal function to make this a valid executable for check step
}
