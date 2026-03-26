const demo = @import("../app_wrapper_demo.zig");
const MeshulaLab = @import("MeshulaLab");
const ziis = @import("zgui_cimgui_implot_sokol");
const zgui = ziis.zgui;

pub fn runUI(
    _: ?*anyopaque,
    _: ?*const MeshulaLab.ViewInteraction,
) callconv(.c) void
{
    if (zgui.beginChild("Big Child Test",.{}))
    {
        defer zgui.endChild();

        switch (demo.STATE.big_text_query.state) {
            .loaded => {
                zgui.separatorText("Big text embed test");

                const TEXT = (
                    demo.STATE.big_text_query.result_data_buffer
                );

                zgui.textUnformatted(TEXT);
            },
            .failed => {
                zgui.pushStyleColor4f(
                    .{
                        .idx = .text,
                        .c = .{ 1.0, 0.0, 0.0, 1.0 },
                    },
                );
                zgui.text(
                    "Failed to load big text file",
                    .{},
                );

                if (demo.STATE.big_text_query.maybe_error != null)
                {
                    zgui.text(
                        "  Error: {s}",
                        .{demo.STATE.big_text_query.error_message()},
                    );
                    zgui.text(
                        "  Code: {s}",
                        .{demo.STATE.big_text_query.error_name()},
                    );
                    zgui.text(
                        "  Path: {s}",
                        .{demo.STATE.big_text_query.target_path},
                    );
                }

                zgui.popStyleColor(.{});
            },
            .loading => {
                zgui.text(
                    "Loading big data...",
                    .{},
                );
            },
        }
    }
}
