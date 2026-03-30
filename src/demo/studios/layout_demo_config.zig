//! LayoutDemoStudio configuration — demonstrates panel layout.

pub const ActivityEntry = struct {
    name: [*:0]const u8,
    initially_visible: bool = true,
    panel_id: ?[*:0]const u8 = null,
    window_name: ?[*:0]const u8 = null,
};

pub const ACTIVITIES = [_]ActivityEntry{
    .{
        .name = "LayoutDemoActivity",
        .panel_id = "main-panel",
        .window_name = "Layout Inspector",
    },
    .{
        .name = "PlotDemoActivity",
        .panel_id = "sidebar-panel",
        .window_name = "Plot",
    },
    .{
        .name = "FileDialogActivity",
        .panel_id = "bottom-panel",
        .window_name = "File Dialog",
    },
};

pub const LAYOUT_SPEC: [*:0]const u8 =
    \\panel root
    \\  direction: horizontal
    \\  sizing: grow grow
    \\
    \\  panel main-panel
    \\    sizing: grow grow
    \\
    \\  panel right-area
    \\    direction: vertical
    \\    sizing: fixed(400) grow
    \\
    \\    panel sidebar-panel
    \\      sizing: grow grow
    \\
    \\    panel bottom-panel
    \\      sizing: grow fixed(200)
;

pub const MUST_DEACTIVATE_UNRELATED = true;
