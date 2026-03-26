const std = @import("std");
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
            "InfLinesPieChartDemo",
            .{ .w = -1, .h = -1, },
        )
    )
    {
        defer zgui.endChild();

        if (
            zgui.plot.beginPlot(
                "Infinite Lines Demo",
                .{
                    .w = -1.0,
                    .h = 300.0,
                },
            )
        )
        {
            defer zgui.plot.endPlot();

            zgui.plot.setupAxis(
                .x1,
                .{ .label = "X Axis" }
            );
            zgui.plot.setupAxis(
                .y1,
                .{ .label = "Y Axis" }
            );
            zgui.plot.setupAxisLimits(
                .x1,
                .{ .min = -1, .max = 10 }
            );
            zgui.plot.setupAxisLimits(
                .y1,
                .{ .min = -1, .max = 10 }
            );
            zgui.plot.setupFinish();

            // Vertical infinite lines at x positions
            const v_lines = [_]f64{1.0, 3.0, 5.0, 7.0};
            zplot.plotInfLines(
                "Vertical Lines",
                f64,
                .{ .v = &v_lines }
            );

            // Horizontal infinite lines at y positions
            const h_lines = [_]f64{2.0, 4.0, 6.0};
            zplot.plotInfLines(
                "Horizontal Lines",
                f64, .{
                    .v = &h_lines,
                    .flags = .{
                        .horizontal = true,
                    },
                }
            );
        }

        const pie_labels = [_][*:0]const u8{
            "Tacos",
            "Pizza",
            "Pasta",
            "Sushi"
        };
        const pie_values = (
            [_]f64{ 30.0, 25.0, 20.0, 15.0 }
        );

        if (
            zgui.plot.beginPlot(
                "Pie Chart Demo",
                .{
                    .w = -1.0,
                    .h = -1.0,
                    .flags = .{ .equal = true },
                },
            )
        )
        {
            defer zgui.plot.endPlot();

            zplot.plotPieChart(
                f64,
                .{
                    .label_ids = &pie_labels,
                    .values = &pie_values,
                    .flags = .{ .normalize = true },
                }
            );

            // tooltip on hover/click
            if (
                demo.maybe_pie_slice_under_mouse(
                    f64,
                    &pie_labels,
                    &pie_values
                )
            ) |hovered|
            {
                const mouse_screen_pos = zgui.getMousePos();
                zgui.setNextWindowPos(
                    .{
                        .x = mouse_screen_pos[0] + 15,
                        .y = mouse_screen_pos[1] + 15,
                    }
                );
                zgui.setNextWindowBgAlpha(.{ .alpha = 0.75 });

                if (
                    zgui.begin(
                        "###PieChartTooltip",
                        .{
                            .flags = .{
                                .no_title_bar = true,
                                .no_resize = true,
                                .no_move = true,
                                .always_auto_resize = true,
                                .no_saved_settings = true,
                                .no_focus_on_appearing = true,
                                .no_nav_inputs = true,
                                .no_nav_focus = true,
                            },
                        },
                    )
                )
                {
                    defer zgui.end();

                    zgui.text(
                        "Hovered\n  slice: {s}\n  value: {d}",
                        .{hovered.label, hovered.value});
                }

                // print on click as well
                if (zgui.isMouseClicked(.left))
                {
                    std.debug.print(
                        "Clicked on {s} slice!\n",
                        .{hovered.label}
                    );
                }
            }
        }
    }
}
