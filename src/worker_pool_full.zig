//! Complete Worker Pool implementation with Web Worker support
//!
//! This is a comprehensive implementation that uses:
//! - Native: std.Thread.Pool for real threading
//! - WASM: Web Workers for parallel execution in browsers
//!
//! Architecture:
//! - WorkerPool manages a pool of workers (threads or Web Workers)
//! - WorkGroup batches related work for coordinated execution
//! - Function registry maps IDs to work functions
//! - Message passing for WASM (no SharedArrayBuffer required)

const std = @import("std");
const builtin = @import("builtin");
const thread = @import("thread.zig");
const registry = @import("worker_registry.zig");

pub const IS_WASM = builtin.target.cpu.arch.isWasm();
pub const HAS_THREADS = thread.HAS_THREADS;

//==============================================================================
// JAVASCRIPT INTEROP (WASM only)
//==============================================================================

// External C functions for JavaScript interop (defined in
// worker_js_interop.c)
extern fn js_worker_pool_create(num_workers: c_int) c_int;
extern fn js_worker_pool_destroy() void;
extern fn js_worker_submit(work_id: c_int, work_fn_id: c_int, context_ptr: c_int, context_size: c_int, timeout_ms: c_int) c_int;
extern fn js_worker_get_available_count() c_int;
extern fn js_worker_mark_available(work_id: c_int) void;

//==============================================================================
// CONFIGURATION
//==============================================================================

pub const WorkerPoolConfig = struct {
    core_workers: u32 = 4,
    max_overflow_workers: u32 = 4,
    work_timeout_ms: u32 = 30000, // 30 seconds default timeout
    allocator: std.mem.Allocator,
};

//==============================================================================
// WORK ITEM
//==============================================================================

pub fn WorkItem(
    comptime Context: type,
) type
{
    return struct {
        const Self = @This();

        id: u32,
        context: Context,
        work_fn_id: u32,
        completed: std.atomic.Value(bool) = std.atomic.Value(bool).init(
            false,
        ),
        error_code: std.atomic.Value(i32) = std.atomic.Value(i32).init(0),
    };
}

//==============================================================================
// WORKER POOL - PLATFORM DISPATCH
//==============================================================================

pub const WorkerPool = if (HAS_THREADS) NativeWorkerPool else WasmWorkerPool;

//==============================================================================
// NATIVE WORKER POOL
//==============================================================================

const NativeWorkerPool = struct {
    const Self = @This();

    thread_pool: std.Thread.Pool,
    allocator: std.mem.Allocator,
    next_work_id: std.atomic.Value(u32) = std.atomic.Value(u32).init(0),
    pending_work: std.ArrayList(*anyopaque),
    pending_lock: std.Thread.Mutex = .{},

    pub fn init(
        config: WorkerPoolConfig,
    ) !Self
    {
        var pool = std.Thread.Pool{};
        try pool.init(
            .{
                .allocator = config.allocator,
                .n_jobs = config.core_workers,
            },
        );

        return .{
            .thread_pool = pool,
            .allocator = config.allocator,
            .pending_work = std.ArrayList(*anyopaque).init(config.allocator),
        };
    }

    pub fn deinit(
        self: *Self,
    ) void
    {
        self.thread_pool.deinit();
        self.pending_work.deinit(self.allocator);
    }

    pub fn submit(
        self: *Self,
        comptime Context: type,
        work_item: *WorkItem(Context),
        work_fn: fn (Context) void,
    ) !void
    {
        const work_id = self.next_work_id.fetchAdd(1, .seq_cst);
        work_item.id = work_id;

        // Register work function if not already registered
        const work_fn_wrapper = registry.makeWorkFunction(Context, work_fn);
        const work_fn_id = registry.registerWorkFunction(work_fn_wrapper);
        work_item.work_fn_id = work_fn_id;

        // Track pending work
        self.pending_lock.lock();
        defer self.pending_lock.unlock();
        try self.pending_work.append(self.allocator, @ptrCast(work_item));

        // Spawn thread pool task
        try self.thread_pool.spawn(
            struct {
                fn run(
                    item: *WorkItem(Context),
                    fn_id: u32,
                ) void
                {
                    const work_func = registry.getWorkFunction(fn_id) orelse {
                        item.error_code.store(-1, .seq_cst);
                        item.completed.store(true, .seq_cst);
                        return;
                    };

                    // Execute work
                    work_func(@ptrCast(&item.context));

                    // Mark complete
                    item.completed.store(true, .seq_cst);
                }
            }.run,
            .{ work_item, work_fn_id },
        );
    }

    pub fn wait(
        self: *Self,
    ) void
    {
        // Wait for all pending work
        self.pending_lock.lock();
        const items = self.pending_work.items;
        self.pending_lock.unlock();

        for (items)
            |item_ptr|
        {
            const item: *WorkItem(anyopaque) = @ptrCast(@alignCast(item_ptr));
            while (!item.completed.load(.seq_cst))
            {
                std.Thread.yield() catch {};
            }
        }

        // Clear pending work
        self.pending_lock.lock();
        defer self.pending_lock.unlock();
        self.pending_work.clearRetainingCapacity();
    }

    pub fn getAvailableWorkerCount(
        self: *const Self,
    ) u32
    {
        _ = self;
        // std.Thread.Pool doesn't expose this easily
        return 0;
    }
};

//==============================================================================
// WASM WORKER POOL
//==============================================================================

const WorkItemState = struct {
    item_ptr: *anyopaque,
    completed_flag: *std.atomic.Value(bool),
    error_flag: *std.atomic.Value(i32),
};

const WasmWorkerPool = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    config: WorkerPoolConfig,
    next_work_id: std.atomic.Value(u32) = std.atomic.Value(u32).init(0),
    pending_work: std.AutoHashMap(u32, WorkItemState),
    pending_lock: std.Thread.Mutex = .{},
    initialized: bool = false,

    pub fn init(
        config: WorkerPoolConfig,
    ) !Self
    {
        if (!IS_WASM)
        {
            return error.WasmWorkerPoolOnlySupportsWasm;
        }

        var self = Self{
            .allocator = config.allocator,
            .config = config,
            .pending_work = std.AutoHashMap(u32, WorkItemState).init(
                config.allocator,
            ),
        };

        // Create Web Worker pool
        const num_created = js_worker_pool_create(
            @intCast(config.core_workers),
        );
        if (num_created < 0)
        {
            return error.FailedToCreateWorkerPool;
        }

        self.initialized = true;
        return self;
    }

    pub fn deinit(
        self: *Self,
    ) void
    {
        if (IS_WASM)
        {
            js_worker_pool_destroy();
        }
        self.pending_work.deinit();
    }

    pub fn submit(
        self: *Self,
        comptime Context: type,
        work_item: *WorkItem(Context),
        work_fn: fn (Context) void,
    ) !void
    {
        if (!self.initialized)
        {
            return error.WorkerPoolNotInitialized;
        }

        const work_id = self.next_work_id.fetchAdd(1, .seq_cst);
        work_item.id = work_id;

        // Register work function
        const work_fn_wrapper = registry.makeWorkFunction(Context, work_fn);
        const work_fn_id = registry.registerWorkFunction(work_fn_wrapper);
        work_item.work_fn_id = work_fn_id;

        // Track pending work
        self.pending_lock.lock();
        try self.pending_work.put(
            work_id,
            .{
                .item_ptr = @ptrCast(work_item),
                .completed_flag = &work_item.completed,
                .error_flag = &work_item.error_code,
            },
        );
        self.pending_lock.unlock();

        // Submit to Web Worker
        const context_ptr: c_int = @intCast(@intFromPtr(&work_item.context));
        const context_size: c_int = @intCast(@sizeOf(Context));
        const timeout_ms: c_int = @intCast(self.config.work_timeout_ms);

        const result = js_worker_submit(
            @intCast(work_id),
            @intCast(work_fn_id),
            context_ptr,
            context_size,
            timeout_ms,
        );

        if (result < 0)
        {
            // Failed to submit - clean up
            self.pending_lock.lock();
            _ = self.pending_work.remove(work_id);
            self.pending_lock.unlock();

            return (
                if (result == -2) error.NoAvailableWorkers
                else error.WorkerSubmitFailed
            );
        }
    }

    pub fn wait(
        self: *Self,
    ) void
    {
        // Poll pending work until all complete
        while (true)
        {
            self.pending_lock.lock();
            const count = self.pending_work.count();
            self.pending_lock.unlock();

            if (count == 0)
            {
                break;
            }

            // Yield to let JavaScript event loop run
            // In WASM, we need to yield control back to browser
            std.time.sleep(1 * std.time.ns_per_ms);
        }
    }

    pub fn getAvailableWorkerCount(
        self: *const Self,
    ) u32
    {
        _ = self;
        if (!IS_WASM)
        {
            return 0;
        }
        return @intCast(js_worker_get_available_count());
    }

    /// Called from JavaScript when work completes
    pub fn notifyWorkComplete(
        self: *Self,
        work_id: u32,
        error_code: i32,
    ) void
    {
        self.pending_lock.lock();
        defer self.pending_lock.unlock();

        if (self.pending_work.get(work_id))
            |state|
        {
            state.error_flag.store(error_code, .seq_cst);
            state.completed_flag.store(true, .seq_cst);
            _ = self.pending_work.remove(work_id);

            // Mark worker as available in JavaScript
            if (IS_WASM)
            {
                js_worker_mark_available(@intCast(work_id));
            }
        }
    }
};

// Export for JavaScript callback
var GLOBAL_WASM_WORKER_POOL: ?*WasmWorkerPool = null;

pub fn setGlobalWorkerPool(
    pool: *WasmWorkerPool,
) void
{
    GLOBAL_WASM_WORKER_POOL = pool;
}

export fn _worker_complete_callback(
    work_id: u32,
    error_code: i32,
) void
{
    if (GLOBAL_WASM_WORKER_POOL)
        |pool|
    {
        pool.notifyWorkComplete(work_id, error_code);
    }
}

//==============================================================================
// WORK GROUP
//==============================================================================

pub fn WorkGroup(
    comptime Context: type,
) type
{
    return struct {
        const Self = @This();

        pool: *WorkerPool,
        work_items: std.ArrayList(WorkItem(Context)),
        allocator: std.mem.Allocator,

        pub fn init(
            allocator: std.mem.Allocator,
            pool: *WorkerPool,
        ) Self
        {
            return .{
                .pool = pool,
                .work_items = std.ArrayList(WorkItem(Context)){},
                .allocator = allocator,
            };
        }

        pub fn deinit(
            self: *Self,
        ) void
        {
            self.work_items.deinit(self.allocator);
        }

        pub fn spawn(
            self: *Self,
            work_fn: fn (Context) void,
            context: Context,
        ) !void
        {
            const item = WorkItem(Context){
                .id = 0,
                .context = context,
                .work_fn_id = 0,
            };

            try self.work_items.append(self.allocator, item);
            const item_ptr = (
                &self.work_items.items[self.work_items.items.len - 1]
            );

            try self.pool.submit(Context, item_ptr, work_fn);
        }

        pub fn join(
            self: *Self,
        ) void
        {
            for (self.work_items.items)
                |*item|
            {
                while (!item.completed.load(.seq_cst))
                {
                    std.Thread.yield() catch {};
                }
            }
        }

        pub fn getErrorCount(
            self: *const Self,
        ) u32
        {
            var count: u32 = 0;
            for (self.work_items.items)
                |*item|
            {
                if (item.error_code.load(.seq_cst) != 0)
                {
                    count += 1;
                }
            }
            return count;
        }
    };
}

//==============================================================================
// TESTS
//==============================================================================

test "worker pool native"
{
    if (!HAS_THREADS)
    {
        return error.SkipZigTest;
    }

    const allocator = std.testing.allocator;

    var pool = try WorkerPool.init(
        .{
            .core_workers = 2,
            .allocator = allocator,
        },
    );
    defer pool.deinit();

    // Test will be implemented
}

test "work group"
{
    if (!HAS_THREADS)
    {
        return error.SkipZigTest;
    }

    const allocator = std.testing.allocator;

    var pool = try WorkerPool.init(
        .{
            .core_workers = 2,
            .allocator = allocator,
        },
    );
    defer pool.deinit();

    const Context = struct {
        value: std.atomic.Value(u32),
    };

    var ctx = Context{
        .value = std.atomic.Value(u32).init(0),
    };

    var group = WorkGroup(*Context).init(allocator, &pool);
    defer group.deinit();

    // Spawn work
    try group.spawn(
        struct {
            fn work(
                c: *Context,
            ) void
            {
                _ = c.value.fetchAdd(1, .seq_cst);
            }
        }.work,
        &ctx,
    );

    try group.spawn(
        struct {
            fn work(
                c: *Context,
            ) void
            {
                _ = c.value.fetchAdd(1, .seq_cst);
            }
        }.work,
        &ctx,
    );

    // Wait for completion
    group.join();

    try std.testing.expectEqual(@as(u32, 2), ctx.value.load(.seq_cst));
}
