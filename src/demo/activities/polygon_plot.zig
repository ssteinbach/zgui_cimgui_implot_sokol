const std = @import("std");
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
            "Polygon Plot Child",
            .{ .w = -1, .h = -1, },
        )
    )
    {
        defer zgui.endChild();

        if (
            zgui.plot.beginPlot(
                "Polygon Plot Demo",
                .{
                    .w = -1.0,
                    .h = -1.0,
                    .flags = .{ .equal = true },
                },
            )
        )
        {
            defer zgui.plot.endPlot();

            zgui.plot.setupLegend(
                .{
                    .north = true,
                    .east = true,
                },
                .{},
            );
            zgui.plot.setupFinish();

            // Triangle (convex)
            const tri_xs = [_]f32{ 0.5, 1.0, 0.0 };
            const tri_ys = [_]f32{ 1.0, 0.0, 0.0 };
            zplot.plotPolygon(
                "Triangle",
                f32,
                .{
                    .xv = &tri_xs,
                    .yv = &tri_ys,
                    .fill_alpha = 0.5,
                },
            );

            // Pentagon (convex)
            const pent_xs = comptime blk: {
                var xs: [5]f32 = undefined;
                for (0..5)
                    |i|
                {
                    const angle: f32 = @as(f32, @floatFromInt(i)) * 2.0 * std.math.pi / 5.0 - std.math.pi / 2.0;
                    xs[i] = 3.0 + 0.8 * @cos(angle);
                }
                break :blk xs;
            };
            const pent_ys = comptime blk: {
                var ys: [5]f32 = undefined;
                for (0..5)
                    |i|
                {
                    const angle: f32 = @as(f32, @floatFromInt(i)) * 2.0 * std.math.pi / 5.0 - std.math.pi / 2.0;
                    ys[i] = 0.5 + 0.8 * @sin(angle);
                }
                break :blk ys;
            };
            zplot.plotPolygon(
                "Pentagon",
                f32,
                .{
                    .xv = &pent_xs,
                    .yv = &pent_ys,
                    .fill_alpha = 0.5,
                    .fill_color = .{ 0, 1, 0, 1 },
                },
            );

            // Star (concave)
            const star_xs = comptime blk: {
                var xs: [10]f32 = undefined;
                for (0..10)
                    |i|
                {
                    const angle: f32 = @as(f32, @floatFromInt(i)) * 2.0 * std.math.pi / 10.0 - std.math.pi / 2.0;
                    const radius: f32 = if (i % 2 == 0) 0.8 else 0.3;
                    xs[i] = 5.5 + radius * @cos(angle);
                }
                break :blk xs;
            };
            const star_ys = comptime blk: {
                var ys: [10]f32 = undefined;
                for (0..10)
                    |i|
                {
                    const angle: f32 = @as(f32, @floatFromInt(i)) * 2.0 * std.math.pi / 10.0 - std.math.pi / 2.0;
                    const radius: f32 = if (i % 2 == 0) 0.8 else 0.3;
                    ys[i] = 0.5 + radius * @sin(angle);
                }
                break :blk ys;
            };
            zplot.plotPolygon(
                "Star (Concave)",
                f32,
                .{
                    .xv = &star_xs,
                    .yv = &star_ys,
                    .fill_alpha = 0.5,
                    .fill_color = .{ 1, 1, 0, 1 },
                    .flags = .{ .concave = true },
                },
            );
        }
    }
}
