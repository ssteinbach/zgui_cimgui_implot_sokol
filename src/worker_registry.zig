//! Work Function Registry for cross-worker function dispatch
//!
//! Allows work functions to be registered with unique IDs and called
//! from Web Workers via message passing.
//!
//! On native: Direct function calls (no registry needed)
//! On WASM: Maps function IDs to function pointers for dispatch

const std = @import("std");
const builtin = @import("builtin");

pub const IS_WASM = builtin.target.cpu.arch.isWasm();

/// Work function signature - takes an opaque context pointer
pub const WorkFn = *const fn (*anyopaque) void;

/// Maximum number of registered work functions
pub const MAX_WORK_FUNCTIONS = 256;

/// Global work function registry
var WORK_FUNCTION_REGISTRY: [MAX_WORK_FUNCTIONS]?WorkFn = (
    [_]?WorkFn{null} ** MAX_WORK_FUNCTIONS
);
var NEXT_WORK_FN_ID: std.atomic.Value(u32) = std.atomic.Value(u32).init(0);

/// Register a work function and return its unique ID
pub fn registerWorkFunction(
    work_fn: WorkFn,
) u32
{
    const id = NEXT_WORK_FN_ID.fetchAdd(1, .seq_cst);
    if (id >= MAX_WORK_FUNCTIONS)
    {
        @panic("Too many work functions registered");
    }
    WORK_FUNCTION_REGISTRY[id] = work_fn;
    return id;
}

/// Get a work function by ID
pub fn getWorkFunction(
    id: u32,
) ?WorkFn
{
    if (id >= MAX_WORK_FUNCTIONS)
    {
        return null;
    }
    return WORK_FUNCTION_REGISTRY[id];
}

/// WASM export: Worker dispatcher entry point
/// Called from JavaScript worker harness
export fn _worker_dispatch(
    work_fn_id: u32,
    context_ptr: *anyopaque,
) i32
{
    if (!IS_WASM)
    {
        return -1;
    } // Should never be called on native

    const work_fn = getWorkFunction(work_fn_id) orelse {
        std.log.err("Invalid work function ID: {d}", .{work_fn_id});
        return -1;
    };

    // Execute the work function
    work_fn(context_ptr);

    return 0; // Success
}

/// WASM export: Worker initialization (optional)
export fn _worker_init(
) void
{
    if (!IS_WASM)
    {
        return;
    }
    // Per-worker initialization if needed
    // Could initialize thread-local state, etc.
}

/// Helper to create a typed work function wrapper
pub fn makeWorkFunction(
    comptime Context: type,
    comptime func: fn (Context) void,
) WorkFn
{
    return struct {
        fn wrapper(
            ctx_ptr: *anyopaque,
        ) void
        {
            const typed_ptr: *Context = @ptrCast(@alignCast(ctx_ptr));
            func(typed_ptr.*);
        }
    }.wrapper;
}

// Tests
test "register and retrieve work function"
{
    const test_fn = struct {
        fn work(
            ctx: *anyopaque,
        ) void
        {
            _ = ctx;
        }
    }.work;

    const id = registerWorkFunction(test_fn);
    const retrieved = getWorkFunction(id);

    try std.testing.expect(retrieved != null);
    try std.testing.expectEqual(test_fn, retrieved.?);
}

test "makeWorkFunction wrapper"
{
    const TestContext = struct {
        value: u32,
    };

    const work_fn = makeWorkFunction(
        TestContext,
        struct {
            fn work(
            ctx: TestContext,
        ) void
        {
                _ = ctx;
                // Work happens here
            }
        }.work,
    );

    var ctx = TestContext{ .value = 42 };
    work_fn(@ptrCast(&ctx));
}
