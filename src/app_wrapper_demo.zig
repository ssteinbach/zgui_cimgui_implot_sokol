//! example app using teh app wrapper

const std = @import("std");
const ziis = @import("zgui_cimgui_implot_sokol");
const zgui = ziis.zgui;
const zplot = zgui.plot;
const app_wrapper = ziis.app_wrapper;

const build_options = @import("build_options");

var f: f32 = 0;
var backup_f: f32 = 0;
var demo_window_gui = false;
var demo_window_plot = false;

var journal : ?ziis.undo.Journal = null;

/// draw the UI
fn draw(
) !void 
{
    const vp = zgui.getMainViewport();
    const size = vp.getSize();

    zgui.setNextWindowPos(.{ .x = 0, .y = 0 });
    zgui.setNextWindowSize(
        .{ 
            .w = size[0],
            .h = size[1],
        }
    );

    if (
        zgui.begin(
            "###FULLSCREEN",
            .{ 
                .flags = .{
                    .no_resize = true, 
                    .no_scroll_with_mouse  = true, 
                    .always_auto_resize = true, 
                    .no_move = true,
                    .no_collapse = true,
                    .no_title_bar = true,
                },
            }
        )
    )
    {
        defer zgui.end();

        var new = f;
        if (zgui.dragFloat("test float", .{ .v = &new })) {
            const cmd = try ziis.undo.SetValue(f32).init(
                    std.heap.page_allocator,
                    &f,
                    new,
                    "test float"
            );
            try cmd.do();
            try journal.?.update_if_new_or_add(cmd);
        }

        for (journal.?.entries.items, 0..)
            |cmd, ind|
        {
            zgui.bulletText("{d}: {s}", .{ ind, cmd.message });
        }

        if (zgui.button("show gui demo", .{}) )
        { 
            demo_window_gui = ! demo_window_gui; 
        }
        if (zgui.button("show plot demo", .{}))
        {
            demo_window_gui = ! demo_window_plot; 
        }

        if (demo_window_gui) 
        {
            zgui.showDemoWindow(&demo_window_gui);
        }
        if (demo_window_plot) 
        {
            zplot.showDemoWindow(&demo_window_plot);
        }

        if (
            zgui.beginChild(
                "Plot", 
                .{
                    .w = -1,
                    .h = -1,
                }
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
                    }
                )
            ) 
            {
                defer zgui.plot.endPlot();

                zgui.plot.setupAxis(
                    .x1,
                    .{ .label = "input" }
                );
                zgui.plot.setupAxis(
                    .y1,
                    .{ .label = "output" }
                );
                zgui.plot.setupLegend(
                    .{ 
                        .south = true,
                        .west = true 
                    },
                    .{}
                );
                zgui.plot.setupFinish();

                const xs= [_]f32{0, 1, 2, 3, 4};
                const ys= [_]f32{0, 1, 2, 3, 6};

                zplot.plotLine(
                    "test plot",
                    f32, 
                    .{
                        .xv = &xs,
                        .yv = &ys 
                    },
                );
            }
        }
    }
}

pub fn main(
) void 
{
    journal = ziis.undo.Journal.init(
        std.heap.page_allocator,
        5
    ) catch null;
    journal.?.update_window_ms = 1000;
    app_wrapper.sokol_main(
        .{
            .draw = draw, 
        },
    );
}
