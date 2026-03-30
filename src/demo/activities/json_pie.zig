const std = @import("std");
const pie_chart_utils = @import("pie_chart_utils.zig");
const MeshulaLab = @import("MeshulaLab");
const ziis = @import("zgui_cimgui_implot_sokol");
const zgui = ziis.zgui;
const zplot = zgui.plot;
const app_wrapper = ziis.app_wrapper;

// ---------------------------------------------------------------
// Activity-local state
// ---------------------------------------------------------------

/// Data read from the example json, designed to be displayed by Zplot
const PieChartSliceData = struct {
    label: [*:0]const u8,
    value: f64,
};

pub var json_fetch_query: *app_wrapper.FetchQuery = undefined;
pub var data_from_json_file: std.MultiArrayList(
    PieChartSliceData,
) = .empty;

var state_allocator: std.mem.Allocator = undefined;

pub fn initState(
    allocator: std.mem.Allocator,
) void
{
    state_allocator = allocator;
    json_fetch_query = app_wrapper.fetch_resource(
        allocator,
        "example.json",
        .{
            .maybe_callback = json_parsing_callback,
            .compression = .none,
        },
    ) catch {
        std.log.err(
            "Unable to fetch data: {s}",
            .{"example.json"},
        );
        return;
    };
}

pub fn deinitState(
    allocator: std.mem.Allocator,
) void
{
    json_fetch_query.deinit();
    allocator.destroy(json_fetch_query);
    json_fetch_query = undefined;

    for (data_from_json_file.items(.label))
        |labels|
    {
        allocator.free(std.mem.span(labels));
    }
    data_from_json_file.deinit(allocator);
    data_from_json_file = .empty;
}

/// Plugin lifecycle callback — wraps initState for the generic plugin template.
pub fn activate(
    _: ?*anyopaque,
) callconv(.c) void
{
    initState(std.heap.c_allocator);
}

/// Plugin lifecycle callback — wraps deinitState for the generic plugin template.
pub fn deactivate(
    _: ?*anyopaque,
) callconv(.c) void
{
    deinitState(std.heap.c_allocator);
}

/// Read the JSON from the parsed file blob and populate state
fn json_parsing_callback(
    fetch_query: *app_wrapper.FetchQuery,
) error{CallbackError}!void
{
    const parsed = std.json.parseFromSlice(
        std.json.Value,
        state_allocator,
        fetch_query.result_data_buffer,
        .{},
    ) catch {
        return error.CallbackError;
    };
    defer parsed.deinit();

    const obj = parsed.value.object;
    var iter = obj.iterator();
    while (iter.next())
        |entry|
    {
        // copy the key out into a format that is ready to display
        const key_copy = state_allocator.dupeZ(
            u8,
            entry.key_ptr.*,
        ) catch continue;

        data_from_json_file.append(
            state_allocator,
            .{
                .label = key_copy,
                .value = @as(
                    f64,
                    @floatFromInt(entry.value_ptr.integer),
                ),
            },
        ) catch continue;
    }

    if (data_from_json_file.len == 0)
    {
        return error.CallbackError;
    }
}

// ---------------------------------------------------------------
// Pie chart drawing
// ---------------------------------------------------------------

pub fn draw_pie_chart() !void
{
    const labels = data_from_json_file.items(.label);
    const values = data_from_json_file.items(.value);

    zplot.plotPieChart(
        f64,
        .{
            .label_ids = labels,
            .values = values,
            .flags = .{ .normalize = true },
        },
    );

    // Add tooltip on hover
    if (pie_chart_utils.maybe_pie_slice_under_mouse(
        f64,
        labels,
        values,
    ))
        |hovered|
    {
        const mouse_screen_pos = zgui.getMousePos();

        // scooch it over
        zgui.setNextWindowPos(
            .{
                .x = mouse_screen_pos[0] + 15,
                .y = mouse_screen_pos[1] + 15,
            },
        );
        zgui.setNextWindowBgAlpha(.{ .alpha = 0.75 });

        if (
            zgui.begin(
                "###JSONPieChartTooltip",
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
                "Item: {s}\nValue: {d}",
                .{ hovered.label, hovered.value },
            );
        }
    }
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
            "JSON Pie Chart",
            .{ .w = -1, .h = -1 },
        )
    )
    {
        defer zgui.endChild();

        // Display fetch status with colors
        switch (json_fetch_query.state)
        {
            .failed =>
            {
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

                if (json_fetch_query.maybe_error != null)
                {
                    zgui.text(
                        "  Error: {s}",
                        .{json_fetch_query.error_message()},
                    );
                    zgui.text(
                        "  Code: {s}",
                        .{json_fetch_query.error_name()},
                    );
                    zgui.text(
                        "  Path: {s}",
                        .{json_fetch_query.target_path},
                    );
                }

                zgui.popStyleColor(.{});
            },
            .loading =>
            {
                zgui.pushStyleColor4f(
                    .{
                        .idx = .text,
                        .c = .{ 0.0, 0.5, 1.0, 1.0 },
                    },
                );
                zgui.text(
                    "Loading example.json... ({s})",
                    .{
                        @tagName(json_fetch_query.state),
                    },
                );
                zgui.popStyleColor(.{});
            },
            .loaded =>
            {
                // Display success message in green
                zgui.pushStyleColor4f(
                    .{
                        .idx = .text,
                        .c = .{ 0.0, 1.0, 0.0, 1.0 },
                    },
                );
                zgui.text(
                    (
                        "JSON data loaded successfully via "
                        ++ "sokol.fetch"
                    ),
                    .{},
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

                    draw_pie_chart() catch {};
                }
            },
        }
    }
}
