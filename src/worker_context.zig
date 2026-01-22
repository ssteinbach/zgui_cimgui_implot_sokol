//! Context Serialization for Web Workers
//!
//! Provides utilities to serialize and deserialize context data
//! that needs to cross the worker boundary.
//!
//! For WASM Web Workers, we need to copy data since workers have
//! separate memory spaces (without SharedArrayBuffer).

const std = @import("std");
const builtin = @import("builtin");

pub const IS_WASM = builtin.target.cpu.arch.isWasm();

/// Serialized context wrapper
pub const SerializedContext = struct {
    data: []u8,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *SerializedContext) void {
        self.allocator.free(self.data);
    }
};

/// Serialize a context for passing to a worker
pub fn serialize(
    comptime Context: type,
    context: *const Context,
    allocator: std.mem.Allocator,
) !SerializedContext {
    // For POD types, we can just copy the bytes
    if (comptime isPOD(Context)) {
        const size = @sizeOf(Context);
        const data = try allocator.alloc(u8, size);
        const src_bytes: [*]const u8 = @ptrCast(context);
        @memcpy(data, src_bytes[0..size]);

        return SerializedContext{
            .data = data,
            .allocator = allocator,
        };
    } else {
        // For complex types, we need custom serialization
        // This is a placeholder - real implementation would need type-specific serialization
        @compileError("Complex types not yet supported for worker serialization");
    }
}

/// Deserialize a context received from a worker message
pub fn deserialize(
    comptime Context: type,
    data: []const u8,
    allocator: std.mem.Allocator,
) !Context {
    _ = allocator;

    if (comptime isPOD(Context)) {
        if (data.len != @sizeOf(Context)) {
            return error.InvalidSerializedData;
        }

        var result: Context = undefined;
        const dest_bytes: [*]u8 = @ptrCast(&result);
        @memcpy(dest_bytes[0..@sizeOf(Context)], data);

        return result;
    } else {
        @compileError("Complex types not yet supported for worker deserialization");
    }
}

/// Check if a type is Plain Old Data (POD)
/// POD types can be safely copied byte-by-byte
fn isPOD(comptime T: type) bool {
    const info = @typeInfo(T);

    switch (info) {
        .Bool, .Int, .Float, .Enum => return true,
        .Pointer => return false, // Pointers can't cross worker boundary
        .Array => |array_info| return isPOD(array_info.child),
        .Struct => |struct_info| {
            // Check all fields are POD
            inline for (struct_info.fields) |field| {
                if (!isPOD(field.type)) return false;
            }
            return true;
        },
        .Union => return false, // Unions need careful handling
        .Optional => |optional_info| return isPOD(optional_info.child),
        else => return false,
    }
}

/// In-place context holder for workers
/// This allocates memory for the context in a way that can be passed to workers
pub fn WorkerContext(comptime Context: type) type {
    return struct {
        const Self = @This();

        data: *Context,
        allocator: std.mem.Allocator,

        pub fn init(allocator: std.mem.Allocator, context: Context) !Self {
            const data = try allocator.create(Context);
            data.* = context;

            return .{
                .data = data,
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            self.allocator.destroy(self.data);
        }

        pub fn ptr(self: *Self) *Context {
            return self.data;
        }

        pub fn constPtr(self: *const Self) *const Context {
            return self.data;
        }
    };
}

test "serialize POD type" {
    const TestContext = struct {
        value: u32,
        flag: bool,
    };

    const allocator = std.testing.allocator;

    const ctx = TestContext{
        .value = 42,
        .flag = true,
    };

    var serialized = try serialize(TestContext, &ctx, allocator);
    defer serialized.deinit();

    try std.testing.expectEqual(@sizeOf(TestContext), serialized.data.len);

    const deserialized = try deserialize(TestContext, serialized.data, allocator);
    try std.testing.expectEqual(ctx.value, deserialized.value);
    try std.testing.expectEqual(ctx.flag, deserialized.flag);
}

test "worker context" {
    const TestContext = struct {
        value: u32,
    };

    const allocator = std.testing.allocator;

    var worker_ctx = try WorkerContext(TestContext).init(allocator, .{ .value = 123 });
    defer worker_ctx.deinit();

    try std.testing.expectEqual(@as(u32, 123), worker_ctx.ptr().value);

    worker_ctx.ptr().value = 456;
    try std.testing.expectEqual(@as(u32, 456), worker_ctx.constPtr().value);
}
