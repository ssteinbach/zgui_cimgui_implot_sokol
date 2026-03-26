const demo = @import("../app_wrapper_demo.zig");
const MeshulaLab = @import("MeshulaLab");
const ziis = @import("zgui_cimgui_implot_sokol");
const zgui = ziis.zgui;

pub fn runUI(
    _: ?*anyopaque,
    _: ?*const MeshulaLab.ViewInteraction,
) callconv(.c) void
{
    if (
        zgui.beginChild(
            "JSON Pie Chart",
            .{ .w = -1, .h = -1, },
        )
    )
    {
        defer zgui.endChild();

        // Display fetch status with colors
        switch (demo.STATE.json_fetch_query.state) {
            .failed => {
                zgui.pushStyleColor4f(
                    .{
                        .idx = .text,
                        .c = .{ 1.0, 0.0, 0.0, 1.0 },
                    },
                );
                zgui.text(
                    "Failed to load example.json via sokol.fetch",
                    .{},
                );

                if (demo.STATE.json_fetch_query.maybe_error != null)
                {
                    zgui.text(
                        "  Error: {s}",
                        .{demo.STATE.json_fetch_query.error_message()},
                    );
                    zgui.text(
                        "  Code: {s}",
                        .{demo.STATE.json_fetch_query.error_name()},
                    );
                    zgui.text(
                        "  Path: {s}",
                        .{demo.STATE.json_fetch_query.target_path},
                    );
                }

                zgui.popStyleColor(.{});
            },
            .loading => {
                zgui.pushStyleColor4f(
                    .{
                        .idx = .text,
                        .c = .{ 0.0, 0.5, 1.0, 1.0 },
                    },
                );
                zgui.text(
                    "Loading example.json... ({s})",
                    .{
                        @tagName(demo.STATE.json_fetch_query.state)
                    }
                );
                zgui.popStyleColor(.{});
            },
            .loaded => {
                // Display success message in green
                zgui.pushStyleColor4f(
                    .{
                        .idx = .text,
                        .c = .{ 0.0, 1.0, 0.0, 1.0 },
                    }
                );
                zgui.text(
                    (
                        "JSON data loaded successfully via "
                        ++ "sokol.fetch"
                    ),
                    .{}
                );
                zgui.popStyleColor(.{});

                if (
                    zgui.plot.beginPlot(
                        "Data from example.json",
                        .{
                            .w = -1.0,
                            .h = -1.0,
                            .flags = .{ .equal = true },
                        },
                    )
                )
                {
                    defer zgui.plot.endPlot();

                    demo.draw_pie_chart() catch {};
                }
            }
        }
    }
}
