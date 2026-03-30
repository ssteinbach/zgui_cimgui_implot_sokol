//! Generic Activity Plugin
//!
//! Comptime-generated plugin boilerplate for a single Activity.
//! Build options select which activity module to wrap and what
//! names to expose.  The activity module must provide:
//!
//!   pub fn runUI(?*anyopaque, ?*const LabViewInteraction) callconv(.c) void
//!
//! Optional declarations detected via @hasDecl:
//!
//!   pub fn activate(?*anyopaque) callconv(.c) void
//!   pub fn deactivate(?*anyopaque) callconv(.c) void
//!   pub fn update(?*anyopaque, f32) callconv(.c) void

const std = @import("std");
const MeshulaLab = @import("MeshulaLab");
const ziis = @import("zgui_cimgui_implot_sokol");
const options = @import("activity_plugin_options");

const activities = @import("demo_activities");
const activity_mod = @field(activities, options.activity_field);

const ACTIVITY_NAME = @as(
    [*:0]const u8,
    @ptrCast(options.activity_name.ptr),
);
const PLUGIN_NAME = @as(
    [*:0]const u8,
    @ptrCast(options.plugin_name.ptr),
);
const PROVENANCE = @as(
    [*:0]const u8,
    @ptrCast(options.provenance.ptr),
);

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
    return "1.0.0";
}

fn getActivityCount() callconv(.c) c_int
{
    return 1;
}

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

    if (@hasDecl(activity_mod, "activate"))
    {
        act.Activate = &activity_mod.activate;
    }
    if (@hasDecl(activity_mod, "deactivate"))
    {
        act.Deactivate = &activity_mod.deactivate;
    }
    if (@hasDecl(activity_mod, "update"))
    {
        act.Update = &activity_mod.update;
    }

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

// -----------------------------------------------------------------
// Plugin descriptor
// -----------------------------------------------------------------

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

// -----------------------------------------------------------------
// Exported entry point
// -----------------------------------------------------------------

export fn LabGetPluginDescriptor() ?*const MeshulaLab.PluginDescriptor
{
    return &DESCRIPTOR;
}
