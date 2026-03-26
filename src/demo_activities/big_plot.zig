const demo = @import("../app_wrapper_demo.zig");
const MeshulaLab = @import("MeshulaLab");
const ziis = @import("zgui_cimgui_implot_sokol");
const zgui = ziis.zgui;
const zplot = zgui.plot;

pub fn runUI(
    _: ?*anyopaque,
    _: ?*const MeshulaLab.ViewInteraction,
) callconv(.c) void
{
    if (
        zgui.beginChild(
            "Big Plot",
            .{ .w = -1, .h = -1, },
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
                    .west = true
                },
                .{},
            );
            zgui.plot.setupFinish();

            const xs= demo.STATE.point_buffers.items(.x);
            const ys= demo.STATE.point_buffers.items(.y);

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
