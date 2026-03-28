//! Plugin Manager Activity
//!
//! Built-in Activity that displays information about all discovered
//! plugins: name, version, provenance, ABI version, compatibility
//! status, library path, and exported activities/providers/studios.
//!
//! Receives the PluginLoader pointer through the Activity's instance
//! field and the plugin directory path through PLUGIN_DIR.

const std = @import("std");
const MeshulaLab = @import("MeshulaLab");
const ziis = @import("zgui_cimgui_implot_sokol");
const zgui = ziis.zgui;
const plugin_loader_mod = @import("plugin_loader.zig");
const PluginLoader = plugin_loader_mod.PluginLoader;
const PluginInfo = plugin_loader_mod.PluginInfo;

const options = @import("fundamental_app_options");
const PLUGIN_DIR = options.plugin_dir;

pub fn runUI(
    instance: ?*anyopaque,
    _: ?*const MeshulaLab.ViewInteraction,
) callconv(.c) void
{
    const loader: *PluginLoader = if (instance)
        |ptr|
        @ptrCast(@alignCast(ptr))
    else
    {
        zgui.textUnformatted("Plugin loader not available.");
        return;
    };

    const plugins = loader.plugins.items;

    zgui.separatorText("Plugin Manager");

    // Plugin directory
    zgui.text("Plugin directory: {s}", .{PLUGIN_DIR});
    zgui.text(
        "Discovered plugins: {d}",
        .{plugins.len},
    );

    zgui.spacing();

    // Summary counts
    var compatible_count: usize = 0;
    var total_activities: usize = 0;
    var total_providers: usize = 0;
    var total_studios: usize = 0;
    for (plugins)
        |info|
    {
        if (info.compatible) compatible_count += 1;
        total_activities += info.activity_names.items.len;
        total_providers += info.provider_names.items.len;
        total_studios += info.studio_names.items.len;
    }
    zgui.text(
        "Compatible: {d}/{d}  |  Activities: {d}  |  Providers: {d}  |  Studios: {d}",
        .{
            compatible_count,
            plugins.len,
            total_activities,
            total_providers,
            total_studios,
        },
    );

    zgui.spacing();
    zgui.separator();
    zgui.spacing();

    // Plugin table
    if (
        zgui.beginTable(
            "PluginTable",
            .{
                .column = 6,
                .flags = .{
                    .resizable = true,
                    .row_bg = true,
                    .borders = .{
                        .inner_h = true,
                        .inner_v = true,
                        .outer_h = true,
                        .outer_v = true,
                    },
                    .sizing = .stretch_prop,
                    // .scroll_y = true,
                },
                // .outer_size = .{ 0, 0 },
            },
        )
    )
    {
        defer zgui.endTable();

        zgui.tableSetupColumn(
            "Name",
            .{
                .flags = .{},
                .init_width_or_height = 1.2,
            },
        );
        zgui.tableSetupColumn(
            "Version",
            .{
                .flags = .{},
                .init_width_or_height = 0.6,
            },
        );
        zgui.tableSetupColumn(
            "ABI",
            .{
                .flags = .{},
                .init_width_or_height = 0.3,
            },
        );
        zgui.tableSetupColumn(
            "Status",
            .{
                .flags = .{},
                .init_width_or_height = 0.6,
            },
        );
        zgui.tableSetupColumn(
            "Provenance",
            .{
                .flags = .{},
                .init_width_or_height = 0.8,
            },
        );
        zgui.tableSetupColumn(
            "Exports",
            .{
                .flags = .{},
                .init_width_or_height = 2.0,
            },
        );

        zgui.tableSetupScrollFreeze(0, 1);
        zgui.tableHeadersRow();

        for (plugins)
            |info|
        {
            zgui.tableNextRow(.{});

            // Name
            _ = zgui.tableNextColumn();
            zgui.textUnformatted(sliceOrNone(info.name));

            // Version
            _ = zgui.tableNextColumn();
            zgui.textUnformatted(sliceOrNone(info.version));

            // ABI version
            _ = zgui.tableNextColumn();
            zgui.text("{d}", .{info.abi_version});

            // Status
            _ = zgui.tableNextColumn();
            if (info.compatible)
            {
                zgui.pushStyleColor4f(
                    .{
                        .idx = .text,
                        .c = .{ 0.0, 1.0, 0.0, 1.0 },
                    },
                );
                zgui.textUnformatted("Compatible");
                zgui.popStyleColor(.{});
            }
            else
            {
                zgui.pushStyleColor4f(
                    .{
                        .idx = .text,
                        .c = .{ 1.0, 0.3, 0.3, 1.0 },
                    },
                );
                zgui.textUnformatted("Incompatible");
                zgui.popStyleColor(.{});
            }

            // Provenance
            _ = zgui.tableNextColumn();
            zgui.textUnformatted(sliceOrNone(info.provenance));

            // Exports — compact list
            _ = zgui.tableNextColumn();
            drawExports(info);
        }
    }

    // Per-plugin detail section with collapsible headers
    zgui.spacing();
    zgui.separatorText("Plugin Details");

    for (plugins)
        |info|
    {
        const header = sliceOrNone(info.name);

        if (zgui.collapsingHeader(toSentinel(header), .{}))
        {
            zgui.indent(.{});

            zgui.text("Path: {s}", .{sliceOrNone(info.path)});
            zgui.text("Version: {s}", .{sliceOrNone(info.version)});
            zgui.text(
                "Provenance: {s}",
                .{sliceOrNone(info.provenance)},
            );
            zgui.text("ABI Version: {d}", .{info.abi_version});

            if (info.activity_names.items.len > 0)
            {
                zgui.spacing();
                zgui.textUnformatted("Activities:");
                for (info.activity_names.items)
                    |act_name|
                {
                    zgui.bulletText("  {s}", .{act_name});
                }
            }

            if (info.provider_names.items.len > 0)
            {
                zgui.spacing();
                zgui.textUnformatted("Providers:");
                for (info.provider_names.items)
                    |prov_name|
                {
                    zgui.bulletText("  {s}", .{prov_name});
                }
            }

            if (info.studio_names.items.len > 0)
            {
                zgui.spacing();
                zgui.textUnformatted("Studios:");
                for (info.studio_names.items)
                    |studio_name|
                {
                    zgui.bulletText("  {s}", .{studio_name});
                }
            }

            zgui.unindent(.{});
            zgui.spacing();
        }
    }
}

// -----------------------------------------------------------------
// Helpers
// -----------------------------------------------------------------

fn sliceOrNone(
    s: []const u8,
) []const u8
{
    return if (s.len > 0) s else "(none)";
}

/// Format the exports column as a compact comma-separated list.
fn drawExports(
    info: PluginInfo,
) void
{
    var first = true;
    for (info.activity_names.items)
        |act_name|
    {
        if (!first) zgui.sameLine(.{});
        first = false;
        zgui.textUnformatted(act_name);
    }
    for (info.provider_names.items)
        |prov_name|
    {
        if (!first) zgui.sameLine(.{});
        first = false;
        zgui.textUnformatted(prov_name);
    }
    for (info.studio_names.items)
        |studio_name|
    {
        if (!first) zgui.sameLine(.{});
        first = false;
        zgui.textUnformatted(studio_name);
    }
    if (first)
    {
        zgui.textDisabled("(none)", .{});
    }
}

/// Convert a Zig slice to a sentinel-terminated pointer using a
/// static buffer. Only valid until the next call.
fn toSentinel(
    s: []const u8,
) [:0]const u8
{
    const S = struct {
        var buf: [512:0]u8 = undefined;
    };
    const len = @min(s.len, S.buf.len - 1);
    @memcpy(S.buf[0..len], s[0..len]);
    S.buf[len] = 0;
    return S.buf[0..len :0];
}
