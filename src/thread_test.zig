//! Tests for the ZIIS platform-agnostic threading abstraction
//!
//! These tests verify that:
//! 1. On native platforms, true multithreading works via std.Thread
//! 2. On WASM/Emscripten, synchronous fallback works correctly
//! 3. TaskQueue provides cooperative multitasking on all platforms

const std = @import("std");
const builtin = @import("builtin");
const thread = @import("thread.zig");

/// Simple counter that threads will increment
var shared_counter: std.atomic.Value(u32) = std.atomic.Value(u32).init(0);

/// Worker function that increments the counter
fn worker(iterations: u32) void {
    for (0..iterations) |_| {
        _ = shared_counter.fetchAdd(1, .seq_cst);
    }
}

/// Test spawning threads and waiting for them
pub fn runThreadTest(allocator: std.mem.Allocator) !u32 {
    _ = allocator;

    if (thread.HAS_THREADS) {
        // True multithreading on native
        const num_threads = 4;
        const iterations_per_thread = 1000;

        var threads: [num_threads]thread.Thread = undefined;

        // Spawn threads
        for (&threads) |*t| {
            t.* = try thread.Thread.spawn(.{}, worker, .{iterations_per_thread});
        }

        // Join all threads
        for (threads) |t| {
            t.join();
        }
    } else {
        // Synchronous fallback on WASM
        // Each "thread" runs immediately
        for (0..4) |_| {
            _ = try thread.Thread.spawn(.{}, worker, .{@as(u32, 1000)});
        }
    }

    return shared_counter.load(.seq_cst);
}

/// Reset for multiple test runs
pub fn reset() void {
    shared_counter.store(0, .seq_cst);
}

test "platform-agnostic thread test" {
    reset();
    const result = try runThreadTest(std.testing.allocator);
    try std.testing.expectEqual(@as(u32, 4000), result);
}

test "task queue basic operations" {
    var queue = thread.TaskQueue(*u32).init(std.testing.allocator);
    defer queue.deinit();

    var value: u32 = 0;

    try queue.enqueue(.{
        .context = &value,
        .work = struct {
            fn work(v: *u32) void {
                v.* += 10;
            }
        }.work,
    });

    try queue.enqueue(.{
        .context = &value,
        .work = struct {
            fn work(v: *u32) void {
                v.* += 5;
            }
        }.work,
    });

    try std.testing.expectEqual(@as(usize, 2), queue.pending());

    _ = queue.processOne();
    try std.testing.expectEqual(@as(u32, 10), value);

    _ = queue.processAll();
    try std.testing.expectEqual(@as(u32, 15), value);
    try std.testing.expectEqual(@as(usize, 0), queue.pending());
}

test "reports correct platform capabilities" {
    if (thread.IS_WASM) {
        try std.testing.expect(!thread.HAS_THREADS);
    } else if (!builtin.single_threaded) {
        try std.testing.expect(thread.HAS_THREADS);
    }
}
