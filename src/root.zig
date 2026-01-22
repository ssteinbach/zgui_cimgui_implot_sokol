pub const zgui = @import("gui.zig");
pub const cimgui = @import("cimgui");
pub const sokol = @import("sokol");
pub const app_wrapper = @import("app_wrapper.zig");
pub const undo = @import("undo");
pub const thread = @import("thread.zig");

/// Platform-agnostic thread abstraction
pub const Thread = thread.Thread;
/// Task queue for frame-based cooperative multitasking
pub const TaskQueue = thread.TaskQueue;

// Web Worker support (WASM only)
pub const worker_pool = @import("worker_pool_full.zig");
pub const worker_registry = @import("worker_registry.zig");
pub const worker_context = @import("worker_context.zig");
