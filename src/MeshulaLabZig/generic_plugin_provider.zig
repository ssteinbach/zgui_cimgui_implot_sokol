//! Generic Provider Plugin
//!
//! Comptime-generated plugin boilerplate for a single Provider.
//! Build options select the provider name, plugin name, and provenance.
//!
//! The `provider_impl` module must provide:
//!
//!   pub fn documentation(?*anyopaque) callconv(.c) [*c]const u8
//!     (optional — detected via @hasDecl)

const std = @import("std");
const MeshulaLab = @import("MeshulaLab");
const options = @import("provider_plugin_options");

const provider_impl = @import("provider_impl");

const PROVIDER_NAME = @as(
    [*:0]const u8,
    @ptrCast(options.provider_name.ptr),
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

fn getProviderCount() callconv(.c) c_int
{
    return 1;
}

fn getProviderName(
    index: c_int,
) callconv(.c) [*c]const u8
{
    if (index == 0) return PROVIDER_NAME;
    return null;
}

fn createProvider(
    _: [*c]const u8,
) callconv(.c) [*c]MeshulaLab.Provider
{
    const provider = std.heap.c_allocator.create(
        MeshulaLab.Provider,
    ) catch return null;
    provider.* = std.mem.zeroes(MeshulaLab.Provider);
    provider.name = PROVIDER_NAME;

    if (@hasDecl(provider_impl, "documentation"))
    {
        provider.Documentation = &provider_impl.documentation;
    }

    return provider;
}

fn destroyProvider(
    provider: [*c]MeshulaLab.Provider,
) callconv(.c) void
{
    if (provider != null)
    {
        std.heap.c_allocator.destroy(
            @as(*MeshulaLab.Provider, @ptrCast(provider)),
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
    .GetProviderCount = &getProviderCount,
    .GetProviderName = &getProviderName,
    .CreateProvider = &createProvider,
    .DestroyProvider = &destroyProvider,
};

// -----------------------------------------------------------------
// Exported entry point
// -----------------------------------------------------------------

export fn LabGetPluginDescriptor() ?*const MeshulaLab.PluginDescriptor
{
    return &DESCRIPTOR;
}
