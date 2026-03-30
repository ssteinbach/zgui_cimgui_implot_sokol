//! DemoStudio configuration — activity list for the demo workspace.

pub const ActivityEntry = struct {
    name: [*:0]const u8,
    initially_visible: bool = true,
    panel_id: ?[*:0]const u8 = null,
    window_name: ?[*:0]const u8 = null,
};

pub const ACTIVITIES = [_]ActivityEntry{
    .{ .name = "UndoJournalDemoActivity" },
    .{ .name = "PlotDemoActivity" },
    .{ .name = "BigPlotDemoActivity" },
    .{ .name = "StairsPlotDemoActivity" },
    .{ .name = "PolygonPlotDemoActivity" },
    .{ .name = "InfLinesPieChartDemoActivity" },
    .{ .name = "TextureDemoActivity" },
    .{ .name = "CanvasDrawingDemoActivity" },
    .{ .name = "JSONPieChartDemoActivity" },
    .{ .name = "BigTextDemoActivity" },
    .{ .name = "ListClipperDemoActivity" },
    .{ .name = "SortableTableDemoActivity" },
    .{ .name = "LayoutDemoActivity" },
};
