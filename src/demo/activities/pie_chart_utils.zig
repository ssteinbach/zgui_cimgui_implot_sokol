//! Shared pie chart utilities for demo activities.

const std = @import("std");
const ziis = @import("zgui_cimgui_implot_sokol");
const zgui = ziis.zgui;
const zplot = zgui.plot;

/// Returns the hovered label, value pair if the mouse is over the plot,
/// otherwise returns null.
///
/// Recomputes the angles and proportions of each slice.  If this is a scaling
/// issue, those could be precomputed and passed in.
pub fn maybe_pie_slice_under_mouse(
    /// type of the values in the pie chart
    comptime T: type,
    labels: []const [*:0]const u8,
    values: []const T,
) ?struct {
    label: [*:0]const u8,
    value: T,
}
{
    switch (@typeInfo(T))
    {
        .@"float", .@"int" => {},
        inline else => @compileError(
            "Only supports pie charts of numeric values",
        ),
    }

    if (zplot.isPlotHovered() == false)
    {
        return null;
    }

    const mouse_pos = zplot.getPlotMousePos(.x1, .y1);
    const plot_limits = zplot.getPlotLimits(.x1, .y1);

    const plot_width = plot_limits.x[1] - plot_limits.x[0];
    const plot_height = plot_limits.y[1] - plot_limits.y[0];
    const center_x = plot_limits.x[0] + plot_width / 2.0;
    const center_y = plot_limits.y[0] + plot_height / 2.0;

    const dx = mouse_pos[0] - center_x;
    const dy = mouse_pos[1] - center_y;
    const dist = @sqrt(dx * dx + dy * dy);

    // pie chart uses half the smaller plot dimension
    const radius = @min(plot_width, plot_height) / 2.0;

    if (dist > radius)
    {
        return null;
    }

    // calculate angle (atan2 from right, CCW)
    // rotate -90 to start from top
    const angle_raw = std.math.radiansToDegrees(
        std.math.atan2(dy, dx),
    );
    const angle = @mod(angle_raw - 90.0, 360.0);

    var total: f64 = 0;
    for (values)
        |v|
    {
        total += @as(f64, @floatCast(v));
    }

    var cumulative_angle: f64 = 0;
    for (labels, values)
        |label, value|
    {
        const slice_angle = (
            @as(f64, @floatCast(value)) / total
        ) * 360.0;
        if (
            angle >= cumulative_angle
            and angle < cumulative_angle + slice_angle
        )
        {
            return .{ .label = label, .value = value };
        }
        cumulative_angle += slice_angle;
    }

    return null;
}
