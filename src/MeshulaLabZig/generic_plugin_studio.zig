//! Generic Studio Plugin
//!
//! Comptime-generated plugin boilerplate for a single Studio.
//! Build options select the studio name, plugin name, and provenance.
//! The `studio_config` module must provide:
//!
//!   pub const ACTIVITIES: []const ActivityConfig
//!
//! Where ActivityConfig is a struct with fields:
//!   name: [*:0]const u8
//!   initially_visible: bool  (default true)
//!
//! Optional declarations detected via @hasDecl on studio_config:
//!
//!   pub const MUST_DEACTIVATE_UNRELATED: bool
//!   pub const LAYOUT_SPEC: [*:0]const u8

const std = @import("std");
const MeshulaLab = @import("MeshulaLab");
const options = @import("studio_plugin_options");

const studio_config = @import("studio_config");

const STUDIO_NAME = @as(
    [*:0]const u8,
    @ptrCast(options.studio_name.ptr),
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
// Build the C-compatible activity config array at comptime
// -----------------------------------------------------------------

const STUDIO_ACTIVITIES = blk:
{
    var configs: [studio_config.ACTIVITIES.len]MeshulaLab.ActivityConfig = undefined;
    for (studio_config.ACTIVITIES, 0..)
        |entry, i|
    {
        configs[i] = .{
            .name = entry.name,
            .uiInitiallyVisible = entry.initially_visible,
            .panelId = entry.panel_id,
            .windowName = entry.window_name,
        };
    }
    break :blk configs;
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
    return "1.0.0";
}

fn getStudioCount() callconv(.c) c_int
{
    return 1;
}

fn getStudioName(
    index: c_int,
) callconv(.c) [*c]const u8
{
    if (index == 0) return STUDIO_NAME;
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
    studio.name = STUDIO_NAME;
    studio.GetActivityCount = &studioGetActivityCount;
    studio.GetActivityConfig = &studioGetActivityConfig;
    studio.MustDeactivateUnrelatedActivities = &studioMustDeactivate;
    if (@hasDecl(studio_config, "LAYOUT_SPEC"))
    {
        studio.GetLayoutSpec = &studioGetLayoutSpec;
    }
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
    return if (@hasDecl(studio_config, "MUST_DEACTIVATE_UNRELATED"))
        studio_config.MUST_DEACTIVATE_UNRELATED
    else
        true;
}

fn studioGetLayoutSpec(
    _: ?*anyopaque,
) callconv(.c) [*c]const u8
{
    return if (@hasDecl(studio_config, "LAYOUT_SPEC"))
        studio_config.LAYOUT_SPEC
    else
        null;
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

// -----------------------------------------------------------------
// Exported entry point
// -----------------------------------------------------------------

export fn LabGetPluginDescriptor() ?*const MeshulaLab.PluginDescriptor
{
    return &DESCRIPTOR;
}
