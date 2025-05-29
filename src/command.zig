const std = @import("std");

/// encapsulation of a state change, with a do and undo
pub const Command = struct {
    context: *anyopaque,
    _do: *const fn (ctx: *anyopaque) void,
    _undo: *const fn (ctx: *anyopaque) void,
    _destroy: *const fn (ctx: *anyopaque, std.mem.Allocator) void,

    pub fn do(
        self: @This(),
    ) !void 
    {
        self._do(self.context);
    }

    pub fn undo(
        self: @This(),
    ) !void 
    {
        self._undo(self.context);
    }

    pub fn destroy(
        self: @This(),
        allocator: std.mem.Allocator,
    ) void 
    {
        self._destroy(self.context, allocator);
    }
};

/// produces a command for setting a value
pub fn SetValue(
    comptime T: type,
) type 
{
    return struct {
        const Context = struct {
            parameter: *T,
            oldvalue: T,
            newvalue: T,
        };

        pub fn init(
            allocator: std.mem.Allocator,
            parameter: *T,
            newvalue: T,
        ) !Command
        {
            const ctx: *Context  = try allocator.create(Context);
            ctx.* = .{
                .parameter = parameter,
                .oldvalue = parameter.*,
                .newvalue = newvalue,
            };

            return .{
                .context = @ptrCast(ctx),
                ._do = do,
                ._undo = undo,
                ._destroy = destroy,
            };
        }

        pub fn do(
            blind_ctx: *anyopaque
        ) void
        {
            const ctx: *Context = @alignCast(@ptrCast(blind_ctx));

            ctx.*.parameter.* = ctx.*.newvalue;
        }

        pub fn undo(
            blind_ctx: *anyopaque
        ) void
        {
            const ctx: *Context = @alignCast(@ptrCast(blind_ctx));

            ctx.*.parameter.* = ctx.*.oldvalue;
        }

        pub fn destroy(
            blind_ctx: *anyopaque,
            allocator: std.mem.Allocator,
        ) void
        {
            const ctx: *Context = @alignCast(@ptrCast(blind_ctx));
            allocator.destroy(ctx);
        }

    };
}
const SetValue_f64 = SetValue(f64);
const SetValue_i32 = SetValue(i32);

test "Set Value f64"
{
    var test_parameter:f64 = 3.14;

    const cmd = try SetValue_f64.init(
        std.testing.allocator,
        &test_parameter,
        12,
    );
    defer cmd.destroy(std.testing.allocator);

    try cmd.do();
    try std.testing.expectEqual(12, test_parameter);

    try cmd.undo();
    try std.testing.expectEqual(3.14, test_parameter);
}

test "Set Value i32"
{
    var test_parameter:i32 = 314;

    const cmd = try SetValue(@TypeOf(test_parameter)).init(
        std.testing.allocator,
        &test_parameter,
        12,
    );
    defer cmd.destroy(std.testing.allocator);

    try cmd.do();
    try std.testing.expectEqual(12, test_parameter);

    try cmd.undo();
    try std.testing.expectEqual(314, test_parameter);
}

