const std = @import("std");
const MeshulaLab = @import("MeshulaLab");
const ziis = @import("zgui_cimgui_implot_sokol");
const zgui = ziis.zgui;
const app_wrapper = ziis.app_wrapper;

// ---------------------------------------------------------------
// Activity-local state
// ---------------------------------------------------------------

pub var big_text_query: *app_wrapper.FetchQuery = undefined;

pub fn initState(
    allocator: std.mem.Allocator,
) void
{
    big_text_query = app_wrapper.fetch_resource(
        allocator,
        "src/app_wrapper_demo.zig",
        .{
            .compression = .none,
        },
    ) catch {
        std.log.err(
            "Unable to fetch data: {s}",
            .{"src/app_wrapper_demo.zig"},
        );
        return;
    };
}

pub fn deinitState(
    allocator: std.mem.Allocator,
) void
{
    big_text_query.deinit();
    allocator.destroy(big_text_query);
}

// ---------------------------------------------------------------
// RunUI
// ---------------------------------------------------------------

pub fn runUI(
    _: ?*anyopaque,
    _: ?*const MeshulaLab.ViewInteraction,
) callconv(.c) void
{
    if (zgui.beginChild("Big Child Test", .{}))
    {
        defer zgui.endChild();

        switch (big_text_query.state)
        {
            .loaded =>
            {
                zgui.separatorText("Big text embed test");

                const TEXT = (
                    big_text_query.result_data_buffer
                );

                zgui.textUnformatted(TEXT);
            },
            .failed =>
            {
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

                if (big_text_query.maybe_error != null)
                {
                    zgui.text(
                        "  Error: {s}",
                        .{big_text_query.error_message()},
                    );
                    zgui.text(
                        "  Code: {s}",
                        .{big_text_query.error_name()},
                    );
                    zgui.text(
                        "  Path: {s}",
                        .{big_text_query.target_path},
                    );
                }

                zgui.popStyleColor(.{});
            },
            .loading =>
            {
                zgui.text(
                    "Loading big data...",
                    .{},
                );
            },
        }
    }
}
