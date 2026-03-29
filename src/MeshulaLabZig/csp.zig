//! CSP (Communicating Sequential Processes) engine
//!
//! Provides event-driven communication between Activities using
//! ZeroMQ (via zimq) on native platforms, with a synchronous
//! queue fallback on WASM. Mirrors the C++ CSP_Engine/CSP_Module/
//! CSP_Process pattern from MeshulaLab.

const std = @import("std");
const builtin = @import("builtin");

const IS_WASM = builtin.target.cpu.arch.isWasm();

/// A named behavior that can be triggered as an event.
pub const CspProcess = struct {
    /// Assigned by the engine during module registration.
    id: i32 = -1,

    /// Human-readable name for this process.
    name: []const u8,

    /// The function to invoke when this process is triggered.
    behavior: *const fn () void,
};

/// A collection of CspProcess instances forming a logical group.
/// Typically corresponds to a state machine or subsystem.
pub const CspModule = struct {
    name: []const u8,
    processes: std.ArrayListUnmanaged(*CspProcess) = .{},
    maybe_engine: ?*CspEngine = null,

    pub fn add_process(
        self: *CspModule,
        allocator: std.mem.Allocator,
        process: *CspProcess,
    ) void
    {
        self.processes.append(allocator, process) catch return;
    }

    /// Register this module with its engine, assigning IDs to all
    /// processes.
    pub fn register(
        self: *CspModule,
    ) void
    {
        const engine = self.maybe_engine orelse return;
        engine.register_module(self);
    }

    /// Emit an event for the given process (immediate, no delay).
    pub fn emit_event(
        self: *CspModule,
        process: *const CspProcess,
    ) void
    {
        const engine = self.maybe_engine orelse return;
        engine.emit_event(process, 0);
    }

    pub fn deinit(
        self: *CspModule,
        allocator: std.mem.Allocator,
    ) void
    {
        self.processes.deinit(allocator);
    }
};

/// Timed event with a target timestamp (used for delayed events).
const TimedEvent = struct {
    process_id: i32,
    send_time_ns: i128,
};

/// Central event coordinator.
///
/// All event processing is single-threaded (main thread). Timed
/// events are promoted to the immediate queue during process_all(),
/// which should be called once per frame. On WASM the behaviour
/// is identical — no ZMQ or threads are used on any platform.
pub const CspEngine = struct {
    modules: std.StringHashMapUnmanaged(*CspModule) = .{},
    processes: std.AutoHashMapUnmanaged(i32, *CspProcess) = .{},
    timed_queue: std.ArrayListUnmanaged(TimedEvent) = .{},
    immediate_queue: std.ArrayListUnmanaged(i32) = .{},
    next_process_id: i32 = 1,
    allocator: std.mem.Allocator,

    pub fn init(
        allocator: std.mem.Allocator,
    ) CspEngine
    {
        return .{ .allocator = allocator };
    }

    pub fn deinit(
        self: *CspEngine,
    ) void
    {
        self.modules.deinit(self.allocator);
        self.processes.deinit(self.allocator);
        self.timed_queue.deinit(self.allocator);
        self.immediate_queue.deinit(self.allocator);
    }

    /// Register a module, assigning unique IDs to all its processes.
    pub fn register_module(
        self: *CspEngine,
        module: *CspModule,
    ) void
    {
        module.maybe_engine = self;

        for (module.processes.items)
            |process|
        {
            process.id = self.next_process_id;
            self.next_process_id += 1;
            self.processes.put(
                self.allocator,
                process.id,
                process,
            ) catch continue;
        }

        self.modules.put(
            self.allocator,
            module.name,
            module,
        ) catch return;
    }

    /// Unregister a module and remove its processes.
    pub fn unregister_module(
        self: *CspEngine,
        module_name: []const u8,
    ) void
    {
        const module = self.modules.get(module_name) orelse return;

        for (module.processes.items)
            |process|
        {
            _ = self.processes.remove(process.id);
        }

        _ = self.modules.remove(module_name);
    }

    /// Queue an event for a process, with an optional delay in
    /// milliseconds. A delay of 0 means immediate.
    pub fn emit_event(
        self: *CspEngine,
        process: *const CspProcess,
        ms_delay: i32,
    ) void
    {
        if (ms_delay > 0)
        {
            const now_ns = std.time.nanoTimestamp();
            const delay_ns: i128 = (
                @as(i128, ms_delay) * std.time.ns_per_ms
            );
            self.timed_queue.append(
                self.allocator,
                .{
                    .process_id = process.id,
                    .send_time_ns = now_ns + delay_ns,
                },
            ) catch return;
            return;
        }

        // Immediate event — queue for next process_all()
        self.immediate_queue.append(
            self.allocator,
            process.id,
        ) catch return;
    }

    /// Start the engine. On this single-threaded implementation
    /// this is a no-op; kept for API compatibility.
    pub fn run(
        self: *CspEngine,
    ) void
    {
        _ = self;
    }

    /// Stop the engine. No-op for the same reason.
    pub fn stop(
        self: *CspEngine,
    ) void
    {
        _ = self;
    }

    /// Process all pending events synchronously.
    /// Call once per frame from the main thread.
    pub fn process_all(
        self: *CspEngine,
    ) void
    {
        // Promote expired timed events to the immediate queue.
        const now_ns = std.time.nanoTimestamp();
        var i: usize = 0;
        while (i < self.timed_queue.items.len)
        {
            const timed = self.timed_queue.items[i];
            if (timed.send_time_ns <= now_ns)
            {
                self.immediate_queue.append(
                    self.allocator,
                    timed.process_id,
                ) catch {};
                _ = self.timed_queue.swapRemove(i);
            }
            else
            {
                i += 1;
            }
        }

        // Dispatch immediate events. Use an index loop because
        // behavior callbacks may enqueue new immediate events.
        var j: usize = 0;
        while (j < self.immediate_queue.items.len)
        {
            const process_id = self.immediate_queue.items[j];
            j += 1;
            if (self.processes.get(process_id))
                |process|
            {
                process.behavior();
            }
        }
        self.immediate_queue.clearRetainingCapacity();
    }
};
