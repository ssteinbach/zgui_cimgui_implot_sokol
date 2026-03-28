const std = @import("std");
const MeshulaLab = @import("MeshulaLab");
const ziis = @import("zgui_cimgui_implot_sokol");
const zgui = ziis.zgui;
const zplot = zgui.plot;

// ---------------------------------------------------------------
// Activity-local state
// ---------------------------------------------------------------

pub var f: f32 = 0;
pub var maybe_journal: ?ziis.undo.Journal = null;
pub var demo_window_gui = false;
pub var demo_window_plot = false;
var state_allocator: std.mem.Allocator = undefined;

pub fn initState(
    allocator: std.mem.Allocator,
    journal_capacity: usize,
) void
{
    state_allocator = allocator;
    maybe_journal = ziis.undo.Journal.init(
        allocator,
        journal_capacity,
    ) catch null;
}

pub fn deinitState() void
{
    if (maybe_journal)
        |*definitely_journal|
    {
        definitely_journal.deinit();
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
    var new = f;
    if (zgui.dragFloat("texture offset", .{ .v = &new }))
    {
        const cmd = ziis.undo.SetValue(f32).init(
            state_allocator,
            &f,
            new,
            "texture offset",
        ) catch return;
        cmd.do() catch return;
        maybe_journal.?.update_if_new_or_add(cmd) catch return;
    }

    for (maybe_journal.?.entries.items, 0..)
        |cmd, ind|
    {
        zgui.bulletText("{d}: {s}", .{ ind, cmd.message });
    }

    zgui.bulletText(
        "Head Entry in Journal: {?d}",
        .{maybe_journal.?.maybe_head_entry},
    );

    if (zgui.beginItemTooltip())
    {
        zgui.text("Hi, this is a tooltip", .{});
        zgui.endTooltip();
    }

    if (zgui.button("undo", .{}))
    {
        maybe_journal.?.undo() catch {};
    }

    zgui.sameLine(.{});

    if (zgui.button("redo", .{}))
    {
        maybe_journal.?.redo() catch {};
    }

    if (zgui.button("show gui demo", .{}))
    {
        demo_window_gui = !demo_window_gui;
    }
    if (zgui.button("show plot demo", .{}))
    {
        demo_window_plot = !demo_window_plot;
    }

    if (demo_window_gui)
    {
        zgui.showDemoWindow(&demo_window_gui);
    }
    if (demo_window_plot)
    {
        zplot.showDemoWindow(&demo_window_plot);
    }
}
