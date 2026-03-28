const std = @import("std");
const MeshulaLab = @import("MeshulaLab");
const ziis = @import("zgui_cimgui_implot_sokol");
const zgui = ziis.zgui;
const zplot = zgui.plot;

const builtin = @import("builtin");
const IS_WASM = builtin.target.cpu.arch.isWasm();

// ---------------------------------------------------------------
// Activity-local state
// ---------------------------------------------------------------

pub var point_buffers: std.MultiArrayList(
    struct { x: f32, y: f32 },
) = .empty;

pub fn initState(
    allocator: std.mem.Allocator,
) void
{
    const BIGCOUNT: usize = if (IS_WASM) 7000 else 75000;
    point_buffers.ensureUnusedCapacity(
        allocator,
        BIGCOUNT,
    ) catch {};

    const inc = 0.01;
    var cur: f32 = -10.0;
    for (0..(BIGCOUNT - 1))
        |_|
    {
        point_buffers.appendAssumeCapacity(
            .{
                .x = cur,
                .y = std.math.sin(cur),
            },
        );
        cur += inc;
    }
}

pub fn deinitState(
    allocator: std.mem.Allocator,
) void
{
    point_buffers.deinit(allocator);
    point_buffers = .empty;
}

// ---------------------------------------------------------------
// RunUI
// ---------------------------------------------------------------

pub fn runUI(
    _: ?*anyopaque,
    _: ?*const MeshulaLab.ViewInteraction,
) callconv(.c) void
{
    if (
        zgui.beginChild(
            "Big Plot",
            .{ .w = -1, .h = -1 },
        )
    )
    {
        defer zgui.endChild();

        if (
            zgui.plot.beginPlot(
                "Lots of items in plot test",
                .{
                    .w = -1.0,
                    .h = -1.0,
                    .flags = .{ .equal = true },
                },
            )
        )
        {
            defer zgui.plot.endPlot();

            zgui.plot.setupAxis(
                .x1,
                .{ .label = "input" },
            );
            zgui.plot.setupAxis(
                .y1,
                .{ .label = "output" },
            );
            zgui.plot.setupLegend(
                .{
                    .south = true,
                    .west = true,
                },
                .{},
            );
            zgui.plot.setupFinish();

            const xs = point_buffers.items(.x);
            const ys = point_buffers.items(.y);

            zplot.plotLine(
                "Sine wave with lots of samples",
                f32,
                .{
                    .xv = xs,
                    .yv = ys,
                    .flags = .{ .shaded = true },
                    .fill_alpha = 0.1,
                },
            );
        }
    }
}
