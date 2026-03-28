//! Plugin: TemplateActivity

const std = @import("std");
const MeshulaLab = @import("MeshulaLab");
const ziis = @import("zgui_cimgui_implot_sokol");
const activities = @import("demo_activities");
const activity_mod = activities.template;

const PLUGIN_NAME = "TemplatePlugin";
const PLUGIN_VERSION = "1.0.0";
const PROVENANCE = "ZIIS Template";
const ACTIVITY_NAME: [*c]const u8 = "TemplateActivity";

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
