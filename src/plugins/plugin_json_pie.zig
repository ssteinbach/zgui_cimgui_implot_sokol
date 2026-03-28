//! Plugin: JSONPieChartDemoActivity
//!
//! Stateful — host must call json_pie.initState()/deinitState().

const std = @import("std");
const MeshulaLab = @import("MeshulaLab");
const ziis = @import("zgui_cimgui_implot_sokol");
const activities = @import("demo_activities");
const activity_mod = activities.json_pie;

const PLUGIN_NAME = "JSONPieChartDemoPlugin";
const PLUGIN_VERSION = "1.0.0";
const PROVENANCE = "ZIIS Demo";
const ACTIVITY_NAME: [*c]const u8 = "JSONPieChartDemoActivity";

fn getABIVersion() callconv(.c) c_int { return 1; }
fn getProvenance() callconv(.c) [*c]const u8 { return PROVENANCE; }
fn getPluginName() callconv(.c) [*c]const u8 { return PLUGIN_NAME; }
fn getPluginVersion() callconv(.c) [*c]const u8 { return PLUGIN_VERSION; }
fn getActivityCount() callconv(.c) c_int { return 1; }

fn getActivityName(
    index: c_int,
) callconv(.c) [*c]const u8
{
    if (index == 0) return ACTIVITY_NAME;
    return null;
}

fn activate(
    _: ?*anyopaque,
) callconv(.c) void
{
    activity_mod.initState(std.heap.c_allocator);
}

fn deactivate(
    _: ?*anyopaque,
) callconv(.c) void
{
    activity_mod.deinitState(std.heap.c_allocator);
}

fn createActivity(
    _: [*c]const u8,
) callconv(.c) [*c]MeshulaLab.Activity
{
    ziis.zgui.initNoContext(std.heap.c_allocator);
    const act = std.heap.c_allocator.create(
        MeshulaLab.Activity,
    ) catch return null;
    act.* = std.mem.zeroes(MeshulaLab.Activity);
    act.name = ACTIVITY_NAME;
    act.RunUI = &activity_mod.runUI;
    act.Activate = &activate;
    act.Deactivate = &deactivate;
    return act;
}

fn destroyActivity(
    act: [*c]MeshulaLab.Activity,
) callconv(.c) void
{
    if (act != null)
    {
        std.heap.c_allocator.destroy(
            @as(*MeshulaLab.Activity, @ptrCast(act)),
        );
    }
}

const DESCRIPTOR = MeshulaLab.PluginDescriptor{
    .GetABIVersion = &getABIVersion,
    .GetProvenance = &getProvenance,
    .GetPluginName = &getPluginName,
    .GetPluginVersion = &getPluginVersion,
    .GetActivityCount = &getActivityCount,
    .GetActivityName = &getActivityName,
    .CreateActivity = &createActivity,
    .DestroyActivity = &destroyActivity,
};

export fn LabGetPluginDescriptor() ?*const MeshulaLab.PluginDescriptor
{
    return &DESCRIPTOR;
}
