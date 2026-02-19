//! Platform-agnostic threading abstraction for ZIIS
//!
//! On native platforms, this wraps std.Thread.
//! On WASM/Emscripten, this provides a synchronous fallback since
//! std.Thread does not support Emscripten.
//!
//! For true async behavior on WASM, use the TaskQueue for frame-based
//! cooperative multitasking.

const std = @import("std");
const builtin = @import("builtin");

/// Whether we're building for WASM (Emscripten)
pub const IS_WASM = builtin.target.cpu.arch.isWasm();

/// Whether true multithreading is available
pub const HAS_THREADS = !IS_WASM and !builtin.single_threaded;

/// Native thread wrapper (uses std.Thread)
/// Only defined when HAS_THREADS is true
const NativeThread = if (HAS_THREADS) struct {
    inner: std.Thread,

    pub const SpawnConfig = std.Thread.SpawnConfig;
    pub const SpawnError = std.Thread.SpawnError;

    pub fn spawn(
        config: SpawnConfig,
        comptime function: anytype,
        args: anytype,
    ) SpawnError!@This()
    {
        return .{
            .inner = try std.Thread.spawn(config, function, args),
        };
    }

    pub fn join(
        self: @This(),
    ) void
    {
        self.inner.join();
    }

    pub fn detach(
        self: @This(),
    ) void
    {
        self.inner.detach();
    }

    pub fn yield(
    ) !void
    {
        try std.Thread.yield();
    }

    pub fn getCurrentId(
    ) std.Thread.Id
    {
        return std.Thread.getCurrentId();
    }
} else struct {};

/// Platform-agnostic thread type
pub const Thread = if (HAS_THREADS) NativeThread else WasmThread;

/// WASM fallback "thread" - executes synchronously
const WasmThread = struct {
    pub const SpawnConfig = struct {
        stack_size: usize = 16 * 1024 * 1024,
        allocator: ?std.mem.Allocator = null,
    };

    pub const SpawnError = error{
        /// WASM synchronous execution cannot fail in the same ways
        WasmSyncExecutionFailed,
    };

    /// On WASM, "spawn" executes the function synchronously.
    /// This is a fallback behavior - for true async, use TaskQueue.
    pub fn spawn(
        config: SpawnConfig,
        comptime function: anytype,
        args: anytype,
    ) SpawnError!WasmThread
    {
        _ = config;

        // Execute synchronously
        const ReturnType = @typeInfo(@TypeOf(function)).@"fn".return_type.?;

        switch (@typeInfo(ReturnType)) {
            .error_union => {
                @call(.auto, function, args) catch {
                    return error.WasmSyncExecutionFailed;
                };
            },
            else => {
                @call(.auto, function, args);
            },
        }

        return WasmThread{};
    }

    /// No-op on WASM since execution was synchronous
    pub fn join(
        self: WasmThread,
    ) void
    {
        _ = self;
    }

    /// No-op on WASM since execution was synchronous
    pub fn detach(
        self: WasmThread,
    ) void
    {
        _ = self;
    }

    /// No-op yield on WASM
    pub fn yield(
    ) !void
    {}

    /// Returns 0 on WASM (single-threaded)
    pub fn getCurrentId(
    ) usize
    {
        return 0;
    }
};

// Note: For atomic values, use std.atomic.Value(T) directly
// This ensures clarity about where the type comes from

/// A frame-based task queue for cooperative multitasking
/// This allows long-running work to be split across frames,
/// preventing UI freezes on both native and WASM platforms.
pub fn TaskQueue(
    comptime Context: type,
) type
{
    return struct {
        const Self = @This();

        pub const Task = struct {
            /// User context passed to the work function
            context: Context,
            /// Work function to execute
            work: *const fn (Context) void,
        };

        tasks: std.ArrayList(Task),
        allocator: std.mem.Allocator,

        pub fn init(
            allocator: std.mem.Allocator,
        ) Self
        {
            return .{
                .tasks = std.ArrayList(Task){},
                .allocator = allocator,
            };
        }

        pub fn deinit(
            self: *Self,
        ) void
        {
            self.tasks.deinit(self.allocator);
        }

        /// Add a task to the queue
        pub fn enqueue(
            self: *Self,
            task: Task,
        ) !void
        {
            try self.tasks.append(self.allocator, task);
        }

        /// Process one task from the queue (call once per frame)
        /// Returns true if a task was processed
        pub fn processOne(
            self: *Self,
        ) bool
        {
            if (self.tasks.items.len > 0)
            {
                const task = self.tasks.orderedRemove(0);
                task.work(task.context);
                return true;
            }
            return false;
        }

        /// Process up to N tasks
        pub fn processN(
            self: *Self,
            max_count: usize,
        ) usize
        {
            var processed: usize = 0;
            while (
                processed < max_count
                and self.processOne()
            )
            {
                processed += 1;
            }
            return processed;
        }

        /// Process all pending tasks
        pub fn processAll(
            self: *Self,
        ) usize
        {
            var processed: usize = 0;
            while (self.processOne())
            {
                processed += 1;
            }
            return processed;
        }

        /// Number of pending tasks
        pub fn pending(
            self: *const Self,
        ) usize
        {
            return self.tasks.items.len;
        }
    };
}

// Tests
test "thread spawn and join on native"
{
    if (!HAS_THREADS)
    {
        return error.SkipZigTest;
    }

    var counter = std.atomic.Value(u32).init(0);

    const t = try Thread.spawn(
        .{},
        struct {
            fn work(
            c: *std.atomic.Value(u32),
        ) void
        {
                _ = c.fetchAdd(1, .seq_cst);
            }
        }.work,
        .{&counter},
    );

    t.join();

    try std.testing.expectEqual(@as(u32, 1), counter.load(.seq_cst));
}

test "wasm thread runs synchronously"
{
    if (HAS_THREADS)
    {
        return error.SkipZigTest;
    }

    var value: u32 = 0;

    _ = try Thread.spawn(
        .{},
        struct {
            fn work(
                v: *u32,
            ) void
            {
                v.* = 42;
            }
        }.work,
        .{&value},
    );

    // On WASM, this should already be set (synchronous execution)
    try std.testing.expectEqual(@as(u32, 42), value);
}

test "task queue"
{
    var queue = TaskQueue(*u32).init(std.testing.allocator);
    defer queue.deinit();

    var value: u32 = 0;

    try queue.enqueue(
        .{
            .context = &value,
            .work = struct {
                fn work(
                    v: *u32,
                ) void
                {
                    v.* += 10;
                }
            }.work,
        },
    );

    try queue.enqueue(
        .{
            .context = &value,
            .work = struct {
                fn work(
                    v: *u32,
                ) void
                {
                    v.* += 5;
                }
            }.work,
        },
    );

    try std.testing.expectEqual(@as(usize, 2), queue.pending());

    _ = queue.processOne();
    try std.testing.expectEqual(@as(u32, 10), value);
    try std.testing.expectEqual(@as(usize, 1), queue.pending());

    _ = queue.processAll();
    try std.testing.expectEqual(@as(u32, 15), value);
    try std.testing.expectEqual(@as(usize, 0), queue.pending());
}
