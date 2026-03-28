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
            "Plot",
            .{ .w = -1, .h = -1, },
        )
    )
    {
        defer zgui.endChild();

        if (
            zgui.plot.beginPlot(
                "Test ZPlot Plot",
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

            const xs= [_]f32{0, 1, 2, 3, 4};
            const ys= [_]f32{0, 1, 2, 3, 6};

            zplot.plotText(
                "start",
                .{
                    .x = xs[0],
                    .y = ys[0],
                    .pix_offset = .{ -15, -10 },
                },
            );
            zplot.plotText(
                "end",
                .{
                    .x = xs[xs.len-1],
                    .y = ys[ys.len-1],
                    .pix_offset = .{ 15, 0 },
                },
            );

            zplot.plotLine(
                "example function",
                f32,
                .{
                    .xv = &xs,
                    .yv = &ys,
                    .flags = .{ .shaded = true },
                    .fill_alpha = 0.1,
                },
            );
        }
    }
}
