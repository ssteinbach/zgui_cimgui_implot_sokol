//! Worker Pool and Work Group abstraction for ZIIS
//!
//! Provides a thread pool on native platforms and Web Worker pool on WASM.
//!
//! Architecture:
//! - WorkerPool: Manages a pool of worker threads/Web Workers
//! - WorkGroup: Batches related work items for coordinated execution
//! - Native: Uses std.Thread.Pool
//! - WASM: Uses Web Workers via JavaScript interop with message passing
//!
//! Design decisions:
//! - Hybrid pool: Pre-spawn core workers, allow temporary overflow
//! - Message passing: Structured clone (no SharedArrayBuffer requirement)
//! - Compiled functions: Zig functions compiled to WASM, not JS eval
//! - Type-safe: Work functions are strongly typed

const std = @import("std");
const builtin = @import("builtin");
const thread = @import("thread.zig");

/// Whether we're building for WASM (Emscripten)
pub const IS_WASM = builtin.target.cpu.arch.isWasm();

/// Whether true multithreading is available
pub const HAS_THREADS = thread.HAS_THREADS;

/// Configuration for WorkerPool
pub const WorkerPoolConfig = struct {
    /// Number of workers to pre-spawn
    /// Native: thread pool size
    /// WASM: number of Web Workers to create upfront
    core_workers: u32 = 4,

    /// Maximum number of additional overflow workers (WASM only)
    /// Native uses std.Thread.Pool which manages this internally
    max_overflow_workers: u32 = 4,

    /// Allocator for pool management
    allocator: std.mem.Allocator,
};

/// Work item submitted to the pool
pub fn WorkItem(comptime Context: type) type {
    return struct {
        const Self = @This();

        /// User context data
        context: Context,

        /// Work function to execute
        work_fn: *const fn (Context) void,

        /// Completion flag (for tracking)
        completed: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    };
}

/// Worker pool - manages execution of work items
/// On native: wraps std.Thread.Pool
/// On WASM: manages Web Workers
pub const WorkerPool = if (HAS_THREADS)
    NativeWorkerPool
else
    WasmWorkerPool;

/// Native worker pool using std.Thread.Pool
const NativeWorkerPool = struct {
    const Self = @This();

    thread_pool: std.Thread.Pool,
    allocator: std.mem.Allocator,

    pub fn init(config: WorkerPoolConfig) !Self {
        var pool = std.Thread.Pool{};
        try pool.init(.{
            .allocator = config.allocator,
            .n_jobs = config.core_workers,
        });

        return .{
            .thread_pool = pool,
            .allocator = config.allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.thread_pool.deinit();
    }

    /// Submit work to the pool
    /// Returns immediately, work executes asynchronously
    pub fn submit(
        self: *Self,
        comptime Context: type,
        work: WorkItem(Context),
    ) !void {
        _ = self;
        _ = work;
        // TODO: Implement using thread_pool.spawn()
        @panic("NativeWorkerPool.submit not yet implemented");
    }

    /// Wait for all submitted work to complete
    pub fn wait(self: *Self) void {
        // TODO: Implement wait logic
        _ = self;
    }
};

/// WASM worker pool using Web Workers
const WasmWorkerPool = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    config: WorkerPoolConfig,

    // TODO: Track Web Worker handles
    // TODO: Track pending work items
    // TODO: Message passing infrastructure

    pub fn init(config: WorkerPoolConfig) !Self {
        return .{
            .allocator = config.allocator,
            .config = config,
        };
    }

    pub fn deinit(self: *Self) void {
        // TODO: Terminate Web Workers
        _ = self;
    }

    /// Submit work to a Web Worker
    pub fn submit(
        self: *Self,
        comptime Context: type,
        work: WorkItem(Context),
    ) !void {
        _ = self;
        _ = work;
        // TODO: Serialize work item and send to Web Worker via postMessage
        @panic("WasmWorkerPool.submit not yet implemented");
    }

    /// Wait for all Web Workers to complete their work
    pub fn wait(self: *Self) void {
        // TODO: Implement wait via promise or polling
        _ = self;
    }
};

/// Work Group - coordinates a batch of related work items
/// Provides spawn/join API similar to std.Thread
pub fn WorkGroup(comptime Context: type) type {
    return struct {
        const Self = @This();

        pool: *WorkerPool,
        work_items: std.ArrayList(WorkItem(Context)),
        allocator: std.mem.Allocator,

        pub fn init(
            allocator: std.mem.Allocator,
            pool: *WorkerPool,
        ) Self {
            return .{
                .pool = pool,
                .work_items = std.ArrayList(WorkItem(Context)).init(allocator),
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            self.work_items.deinit(self.allocator);
        }

        /// Spawn work in this group
        /// Similar to std.Thread.spawn but managed by the pool
        pub fn spawn(
            self: *Self,
            work_fn: *const fn (Context) void,
            context: Context,
        ) !void {
            const item = WorkItem(Context){
                .context = context,
                .work_fn = work_fn,
            };

            try self.work_items.append(self.allocator, item);
            try self.pool.submit(Context, item);
        }

        /// Wait for all work in this group to complete
        /// Similar to std.Thread.join
        pub fn join(self: *Self) void {
            // Wait for all work items to be marked complete
            for (self.work_items.items) |*item| {
                while (!item.completed.load(.seq_cst)) {
                    std.Thread.yield() catch {};
                }
            }
        }
    };
}

//==============================================================================
// TESTS
//==============================================================================

test "worker pool basic" {
    if (!HAS_THREADS) return error.SkipZigTest;

    // TODO: Implement and test
}

test "work group spawn and join" {
    if (!HAS_THREADS) return error.SkipZigTest;

    // TODO: Implement and test
}
