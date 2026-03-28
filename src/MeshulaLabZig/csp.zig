//! CSP (Communicating Sequential Processes) engine
//!
//! Provides event-driven communication between Activities using
//! ZeroMQ (via zimq) on native platforms, with a synchronous
//! queue fallback on WASM. Mirrors the C++ CSP_Engine/CSP_Module/
//! CSP_Process pattern from LabRaven.

const std = @import("std");
const builtin = @import("builtin");

const IS_WASM = builtin.target.cpu.arch.isWasm();
const HAS_THREADS = !IS_WASM;

const zimq = if (!IS_WASM) @import("zimq") else struct {};

/// A named behavior that can be triggered as an event.
pub const CspProcess = struct
{
    /// Assigned by the engine during module registration.
    id: i32 = -1,

    /// Human-readable name for this process.
    name: []const u8,

    /// The function to invoke when this process is triggered.
    behavior: *const fn () void,
};

/// A collection of CspProcess instances forming a logical group.
/// Typically corresponds to a state machine or subsystem.
pub const CspModule = struct
{
    name: []const u8,
    processes: std.ArrayListUnmanaged(*CspProcess) = .{},
    maybe_engine: ?*CspEngine = null,

    pub fn addProcess(
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
        engine.registerModule(self);
    }

    /// Emit an event for the given process (immediate, no delay).
    pub fn emitEvent(
        self: *CspModule,
        process: *const CspProcess,
    ) void
    {
        const engine = self.maybe_engine orelse return;
        engine.emitEvent(process, 0);
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
const TimedEvent = struct
{
    process_id: i32,
    send_time_ns: i128,
};

/// Central event coordinator.
///
/// On native: uses ZeroMQ PUB/SUB over inproc transport with a
/// worker thread, matching the C++ CSP_Engine pattern.
/// On WASM: uses a simple in-memory queue processed synchronously.
pub const CspEngine = struct
{
    modules: std.StringHashMapUnmanaged(*CspModule) = .{},
    processes: std.AutoHashMapUnmanaged(i32, *CspProcess) = .{},
    timed_queue: std.ArrayListUnmanaged(TimedEvent) = .{},
    next_process_id: i32 = 1,
    running: bool = false,
    allocator: std.mem.Allocator,

    // --- Native ZMQ fields ---
    zmq_context: if (HAS_THREADS) ?*zimq.Context else void =
        if (HAS_THREADS) null else {},
    pub_socket: if (HAS_THREADS) ?*zimq.Socket else void =
        if (HAS_THREADS) null else {},
    sub_socket: if (HAS_THREADS) ?*zimq.Socket else void =
        if (HAS_THREADS) null else {},
    maybe_worker: if (HAS_THREADS) ?std.Thread else void =
        if (HAS_THREADS) null else {},
    mutex: if (HAS_THREADS) std.Thread.Mutex else void =
        if (HAS_THREADS) .{} else {},

    // --- WASM fallback fields ---
    wasm_queue: if (IS_WASM) std.ArrayListUnmanaged(i32) else void =
        if (IS_WASM) .{} else {},

    const ENDPOINT = "inproc://csp_engine";

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
        self.stop();
        if (HAS_THREADS)
        {
            if (self.sub_socket)
                |s|
            {
                s.deinit();
            }
            if (self.pub_socket)
                |s|
            {
                s.deinit();
            }
            if (self.zmq_context)
                |ctx|
            {
                ctx.deinit();
            }
            self.sub_socket = null;
            self.pub_socket = null;
            self.zmq_context = null;
        }
        if (IS_WASM)
        {
            self.wasm_queue.deinit(self.allocator);
        }
        self.modules.deinit(self.allocator);
        self.processes.deinit(self.allocator);
        self.timed_queue.deinit(self.allocator);
    }

    /// Register a module, assigning unique IDs to all its processes.
    pub fn registerModule(
        self: *CspEngine,
        module: *CspModule,
    ) void
    {
        if (HAS_THREADS) self.mutex.lock();
        defer if (HAS_THREADS) self.mutex.unlock();

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
    pub fn unregisterModule(
        self: *CspEngine,
        module_name: []const u8,
    ) void
    {
        if (HAS_THREADS) self.mutex.lock();
        defer if (HAS_THREADS) self.mutex.unlock();

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
    pub fn emitEvent(
        self: *CspEngine,
        process: *const CspProcess,
        ms_delay: i32,
    ) void
    {
        if (ms_delay > 0)
        {
            if (HAS_THREADS) self.mutex.lock();
            defer if (HAS_THREADS) self.mutex.unlock();

            const now_ns = std.time.nanoTimestamp();
            const delay_ns: i128 =
                @as(i128, ms_delay) * std.time.ns_per_ms;
            self.timed_queue.append(
                self.allocator,
                .{
                    .process_id = process.id,
                    .send_time_ns = now_ns + delay_ns,
                },
            ) catch return;
            return;
        }

        // Immediate event
        if (HAS_THREADS)
        {
            self.zmqSend(process.id);
        }
        if (IS_WASM)
        {
            self.wasm_queue.append(
                self.allocator,
                process.id,
            ) catch return;
        }
    }

    /// Start the ZMQ sockets and worker thread (native only).
    /// On WASM this is a no-op.
    pub fn run(
        self: *CspEngine,
    ) void
    {
        if (HAS_THREADS)
        {
            if (self.running) return;
            self.initZmq() catch return;
            self.running = true;
            self.maybe_worker = std.Thread.spawn(
                .{},
                workerLoop,
                .{self},
            ) catch null;
        }
    }

    /// Stop the worker thread (native only).
    pub fn stop(
        self: *CspEngine,
    ) void
    {
        if (HAS_THREADS)
        {
            if (!self.running) return;
            self.running = false;
            if (self.maybe_worker)
                |worker|
            {
                worker.join();
                self.maybe_worker = null;
            }
        }
    }

    /// Process all pending events synchronously.
    /// Call once per frame on WASM. On native, can be used for
    /// non-blocking polling (the C++ `test()` equivalent).
    pub fn processAll(
        self: *CspEngine,
    ) void
    {
        self.processTimedEvents();
        if (HAS_THREADS)
        {
            self.zmqRecvAll();
        }
        if (IS_WASM)
        {
            self.processWasmQueue();
        }
    }

    // ---------------------------------------------------------------
    // Internal — ZMQ (native only)
    // ---------------------------------------------------------------

    fn initZmq(
        self: *CspEngine,
    ) !void
    {
        if (!HAS_THREADS) return;

        self.zmq_context = try zimq.Context.init();
        const ctx = self.zmq_context.?;

        self.pub_socket = try zimq.Socket.init(ctx, .@"pub");
        try self.pub_socket.?.bind(ENDPOINT);

        self.sub_socket = try zimq.Socket.init(ctx, .sub);
        try self.sub_socket.?.set(.subscribe, "");
        try self.sub_socket.?.connect(ENDPOINT);
    }

    fn zmqSend(
        self: *CspEngine,
        process_id: i32,
    ) void
    {
        if (!HAS_THREADS) return;
        const sock = self.pub_socket orelse return;
        const bytes: [4]u8 = @bitCast(process_id);
        sock.sendSlice(&bytes, .{}) catch {};
    }

    fn zmqRecvAll(
        self: *CspEngine,
    ) void
    {
        if (!HAS_THREADS) return;
        const sock = self.sub_socket orelse return;

        while (true)
        {
            var buf: [4]u8 = undefined;
            _ = sock.recv(&buf, .noblock) catch break;
            const process_id: i32 = @bitCast(buf);
            if (self.processes.get(process_id))
                |process|
            {
                process.behavior();
            }
        }
    }

    // ---------------------------------------------------------------
    // Internal — WASM fallback
    // ---------------------------------------------------------------

    fn processWasmQueue(
        self: *CspEngine,
    ) void
    {
        if (!IS_WASM) return;
        while (self.wasm_queue.items.len > 0)
        {
            const process_id = self.wasm_queue.orderedRemove(0);
            if (self.processes.get(process_id))
                |process|
            {
                process.behavior();
            }
        }
    }

    // ---------------------------------------------------------------
    // Internal — shared
    // ---------------------------------------------------------------

    fn processTimedEvents(
        self: *CspEngine,
    ) void
    {
        if (HAS_THREADS) self.mutex.lock();
        defer if (HAS_THREADS) self.mutex.unlock();

        const now_ns = std.time.nanoTimestamp();
        var i: usize = 0;
        while (i < self.timed_queue.items.len)
        {
            const timed = self.timed_queue.items[i];
            if (timed.send_time_ns <= now_ns)
            {
                // Promote to immediate
                const pid = timed.process_id;
                _ = self.timed_queue.swapRemove(i);
                if (HAS_THREADS)
                {
                    self.zmqSend(pid);
                }
                if (IS_WASM)
                {
                    self.wasm_queue.append(
                        self.allocator,
                        pid,
                    ) catch {};
                }
            }
            else
            {
                i += 1;
            }
        }
    }

    fn workerLoop(
        self: *CspEngine,
    ) void
    {
        while (self.running)
        {
            self.processAll();
            std.Thread.sleep(1 * std.time.ns_per_ms);
        }
    }
};
