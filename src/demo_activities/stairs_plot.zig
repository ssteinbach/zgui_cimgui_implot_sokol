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
            "Stairs Plot",
            .{ .w = -1, .h = -1, },
        )
    )
    {
        defer zgui.endChild();

        if (
            zgui.plot.beginPlot(
                "Stairstep Plot Demo",
                .{
                    .w = -1.0,
                    .h = -1.0,
                },
            )
        )
        {
            defer zgui.plot.endPlot();

            zgui.plot.setupAxis(
                .x1,
                .{ .label = "Time" },
            );
            zgui.plot.setupAxis(
                .y1,
                .{ .label = "Value" },
            );
            zgui.plot.setupLegend(
                .{
                    .north = true,
                    .east = true
                },
                .{},
            );
            zgui.plot.setupFinish();

            // Example 1: Simple stairs with values only
            const values= (
                [_]f32{1.0, 3.0, 2.0, 5.0, 4.0, 6.0, 3.0}
            );
            zplot.plotStairsValues(
                "Auto X-axis",
                f32,
                .{
                    .v = &values,
                },
            );

            // Example 2: Stairs with explicit X and Y values
            const xs= [_]f32{0.0, 1.0, 2.5, 3.5, 5.0, 6.0, 7.5};
            const ys= [_]f32{2.0, 4.0, 3.0, 6.0, 5.0, 7.0, 4.0};
            zplot.plotStairs(
                "Explicit X-Y",
                f32,
                .{
                    .xv = &xs,
                    .yv = &ys,
                },
            );

            // Example 3: Pre-step stairs (y value extends left)
            const xs2= [_]f32{0.5, 1.5, 2.5, 3.5, 4.5, 5.5, 6.5};
            const ys2= [_]f32{1.5, 2.5, 4.5, 3.5, 5.5, 4.5, 6.5};
            zplot.plotStairs(
                "Pre-step Mode",
                f32,
                .{
                    .xv = &xs2,
                    .yv = &ys2,
                    .flags = .{ .pre_step = true },
                },
            );

            // Example 4: Shaded stairs
            const xs3= (
                [_]f32{0.25, 1.25, 2.25, 3.25, 4.25, 5.25, 6.25}
            );
            const ys3= [_]f32{0.5, 1.5, 1.0, 2.5, 2.0, 3.0, 2.5};
            zplot.plotStairs(
                "Shaded Stairs",
                f32,
                .{
                    .xv = &xs3,
                    .yv = &ys3,
                    .flags = .{ .shaded = true },
                },
            );
        }
    }
}
