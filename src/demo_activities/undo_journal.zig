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
    var new = demo.STATE.f;
    if (zgui.dragFloat("texture offset", .{.v = &new}))
    {
        const cmd = ziis.undo.SetValue(f32).init(
                demo.allocator,
                &demo.STATE.f,
                new,
                "texture offset",
        ) catch return;
        cmd.do() catch return;
        demo.STATE.maybe_journal.?.update_if_new_or_add(cmd) catch return;
    }

    for (demo.STATE.maybe_journal.?.entries.items, 0..)
        |cmd, ind|
    {
        zgui.bulletText("{d}: {s}", .{ ind, cmd.message });
    }

    zgui.bulletText(
        "Head Entry in Journal: {?d}",
        .{ demo.STATE.maybe_journal.?.maybe_head_entry },
    );

    if (zgui.beginItemTooltip())
    {
        zgui.text("Hi, this is a tooltip", .{});
        zgui.endTooltip();
    }

    if (zgui.button("undo", .{}))
    {
        demo.STATE.maybe_journal.?.undo() catch {};
    }

    zgui.sameLine(.{});

    if (zgui.button("redo", .{}))
    {
        demo.STATE.maybe_journal.?.redo() catch {};
    }

    if (zgui.button("show gui demo", .{}) )
    {
        demo.STATE.demo_window_gui = ! demo.STATE.demo_window_gui;
    }
    if (zgui.button("show plot demo", .{}))
    {
        demo.STATE.demo_window_plot = ! demo.STATE.demo_window_plot;
    }

    if (demo.STATE.demo_window_gui)
    {
        zgui.showDemoWindow(&demo.STATE.demo_window_gui);
    }
    if (demo.STATE.demo_window_plot)
    {
        zplot.showDemoWindow(&demo.STATE.demo_window_plot);
    }
}
