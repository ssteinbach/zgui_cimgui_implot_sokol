//! Studio Plugin: DemoStudio
//!
//! Exports a LabPluginDescriptor providing one Studio.
//! Edit STUDIO_ACTIVITIES to declare which activities belong
//! in this studio.

const std = @import("std");
const MeshulaLab = @import("MeshulaLab");

const PLUGIN_NAME = "DemoStudioPlugin";
const PLUGIN_VERSION = "1.0.0";
const PROVENANCE = "ZIIS";
const STUDIO_NAME: [*c]const u8 = "DemoStudio";

// -----------------------------------------------------------------
// Studio activity configuration — add your activities here
// -----------------------------------------------------------------

const STUDIO_ACTIVITIES = [_]MeshulaLab.ActivityConfig{
    .{ .name = "UndoJournalDemoActivity", .uiInitiallyVisible = true },
    .{ .name = "PlotDemoActivity", .uiInitiallyVisible = true },
    .{ .name = "BigPlotDemoActivity", .uiInitiallyVisible = true },
    .{ .name = "StairsPlotDemoActivity", .uiInitiallyVisible = true },
    .{ .name = "PolygonPlotDemoActivity", .uiInitiallyVisible = true },
    .{ .name = "InfLinesPieChartDemoActivity", .uiInitiallyVisible = true },
    .{ .name = "TextureDemoActivity", .uiInitiallyVisible = true },
    .{ .name = "CanvasDrawingDemoActivity", .uiInitiallyVisible = true },
    .{ .name = "JSONPieChartDemoActivity", .uiInitiallyVisible = true },
    .{ .name = "BigTextDemoActivity", .uiInitiallyVisible = true },
    .{ .name = "ListClipperDemoActivity", .uiInitiallyVisible = true },
    .{ .name = "SortableTableDemoActivity", .uiInitiallyVisible = true },
};

// -----------------------------------------------------------------
// Descriptor callbacks
// -----------------------------------------------------------------

fn getABIVersion() callconv(.c) c_int
{
    return 1;
}

fn getProvenance() callconv(.c) [*c]const u8
{
    return PROVENANCE;
}

fn getPluginName() callconv(.c) [*c]const u8
{
    return PLUGIN_NAME;
}

fn getPluginVersion() callconv(.c) [*c]const u8
{
    return PLUGIN_VERSION;
}

fn getStudioCount() callconv(.c) c_int
{
    return 1;
}

fn getStudioName(
    index: c_int,
) callconv(.c) [*c]const u8
{
    if (index == 0) return "DemoStudio";
    return null;
}

fn createStudio(
    _: [*c]const u8,
) callconv(.c) [*c]MeshulaLab.Studio
{
    const studio = std.heap.c_allocator.create(
        MeshulaLab.Studio,
    ) catch return null;
    studio.* = std.mem.zeroes(MeshulaLab.Studio);
    studio.name = "DemoStudio";
    studio.GetActivityCount = &studioGetActivityCount;
    studio.GetActivityConfig = &studioGetActivityConfig;
    studio.MustDeactivateUnrelatedActivities = &studioMustDeactivate;
    return studio;
}

fn destroyStudio(
    studio: [*c]MeshulaLab.Studio,
) callconv(.c) void
{
    if (studio != null)
    {
        std.heap.c_allocator.destroy(
            @as(*MeshulaLab.Studio, @ptrCast(studio)),
        );
    }
}

fn studioGetActivityCount(
    _: ?*anyopaque,
) callconv(.c) c_int
{
    return @intCast(STUDIO_ACTIVITIES.len);
}

fn studioGetActivityConfig(
    _: ?*anyopaque,
    index: c_int,
) callconv(.c) ?*const MeshulaLab.ActivityConfig
{
    const i: usize = @intCast(index);
    if (i >= STUDIO_ACTIVITIES.len) return null;
    return &STUDIO_ACTIVITIES[i];
}

fn studioMustDeactivate(
    _: ?*anyopaque,
) callconv(.c) bool
{
    return true;
}

// -----------------------------------------------------------------
// Plugin descriptor
// -----------------------------------------------------------------

const DESCRIPTOR = MeshulaLab.PluginDescriptor{
    .GetABIVersion = &getABIVersion,
    .GetProvenance = &getProvenance,
    .GetPluginName = &getPluginName,
    .GetPluginVersion = &getPluginVersion,
    .GetStudioCount = &getStudioCount,
    .GetStudioName = &getStudioName,
    .CreateStudio = &createStudio,
    .DestroyStudio = &destroyStudio,
};

export fn LabGetPluginDescriptor() ?*const MeshulaLab.PluginDescriptor
{
    return &DESCRIPTOR;
}
