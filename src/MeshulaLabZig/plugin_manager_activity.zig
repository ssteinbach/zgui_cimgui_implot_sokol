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
const FundamentalApp = @import("fundamental_app.zig").FundamentalApp;
const Orchestrator = @import("orchestrator.zig").Orchestrator;
const plugin_loader_mod = @import("plugin_loader.zig");
const PluginLoader = plugin_loader_mod.PluginLoader;
const PluginInfo = plugin_loader_mod.PluginInfo;

const options = @import("fundamental_app_options");
const PLUGIN_DIR = options.plugin_dir;

/// Index of the plugin row that was clicked in the table.
/// When set, the detail section scrolls to this plugin.
var scroll_to_plugin: ?usize = null;

/// Deferred action to execute after all UI drawing is done,
/// so we never mutate the plugin list mid-iteration.
const DeferredAction = enum { none, unload, reload, load };
var deferred_action: DeferredAction = .none;
var deferred_index: usize = 0;

pub fn runUI(
    instance: ?*anyopaque,
    _: ?*const MeshulaLab.ViewInteraction,
) callconv(.c) void
{
    const app: *FundamentalApp = (
        if (instance)
            |ptr| @ptrCast(@alignCast(ptr))
            else
        {
            zgui.textUnformatted("Plugin manager not available.");
            return;
        }
    );

    const loader = &app.plugin_loader;

    zgui.separatorText("Plugin Manager");


    // Plugin directory + refresh button
    zgui.text("Plugin directory: {s}", .{PLUGIN_DIR});
    zgui.sameLine(.{});
    if (zgui.smallButton("Refresh"))
    {
        var threaded: std.Io.Threaded = .init_single_threaded;
        const io = threaded.io();
        // TODO:should we plumb the Io context/monad through ZIIS?
        loader.rescan(
            io,
            PLUGIN_DIR,
        );
    }

    zgui.text(
        "Discovered plugins: {d}",
        .{loader.plugins.items.len},
    );

    zgui.spacing();

    // Summary counts
    var loaded_count: usize = 0;
    var compatible_count: usize = 0;
    var enabled_count: usize = 0;
    var total_activities: usize = 0;
    var total_providers: usize = 0;
    var total_studios: usize = 0;
    for (loader.plugins.items)
        |info|
    {
        if (info.loaded)
        {
            loaded_count += 1;
        }
        if (info.compatible)
        {
            compatible_count += 1;
        }
        if (info.enabled)
        {
            enabled_count += 1;
        }
        total_activities += info.activity_names.items.len;
        total_providers += info.provider_names.items.len;
        total_studios += info.studio_names.items.len;
    }
    zgui.text(
        (
            "Loaded: {d}/{d}  |  Compatible: {d}  |  Enabled: {d}  |  "
            ++ "Activities: {d}  |  Providers: {d}  |  Studios: {d}"
        ),
        .{
            loaded_count,
            loader.plugins.items.len,
            compatible_count,
            enabled_count,
            total_activities,
            total_providers,
            total_studios,
        },
    );

    zgui.spacing();
    zgui.separator();
    zgui.spacing();

    draw_plugin_table(app);

    // Per-plugin detail section with collapsible headers
    zgui.spacing();
    zgui.separatorText("Plugin Details");

    for (loader.plugins.items, 0..)
        |*info, idx|
    {
        const header = slice_or_none(info.name);
        const should_open = (
            if (scroll_to_plugin) |target| target == idx
            else false
        );

        if (should_open)
        {
            zgui.setNextItemOpen(.{ .is_open = true });
        }

        zgui.pushIntId(@intCast(idx));
        defer zgui.popId();

        if (zgui.collapsingHeader(to_sentinel(header), .{}))
        {
            if (should_open)
            {
                zgui.setScrollHereY(.{});
                scroll_to_plugin = null;
            }

            zgui.indent(.{});

            zgui.text("Path: {s}", .{slice_or_none(info.path)});
            zgui.text(
                "Version: {s}",
                .{slice_or_none(info.version)},
            );
            zgui.text(
                "Provenance: {s}",
                .{slice_or_none(info.provenance)},
            );
            zgui.text(
                "ABI Version: {d}",
                .{info.abi_version},
            );
            zgui.text(
                "Loaded: {s}",
                .{if (info.loaded) "yes" else "no"},
            );
            if (info.loaded)
            {
                zgui.text(
                    "Enabled: {s}",
                    .{if (info.enabled) "yes" else "no"},
                );
            }

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
        else
        {
            // Header was not opened — if we wanted to scroll
            // here, clear the request so we don't loop forever.
            if (should_open)
            {
                scroll_to_plugin = null;
            }
        }
    }

    // Execute deferred unload/reload now that all UI drawing
    // (table + detail section) is complete.
    execute_deferred_action(app);
}

// -----------------------------------------------------------------
// Table drawing
// -----------------------------------------------------------------

fn draw_plugin_table(
    app: *FundamentalApp,
) void
{
    const loader = &app.plugin_loader;

    if (
        zgui.beginTable(
            "PluginTableFull",
            .{
                .column = 7,
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
                },
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
            "Exports",
            .{
                .flags = .{},
                .init_width_or_height = 1.0,
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
            "##Actions",
            .{
                .flags = .{ .no_resize = true },
                .init_width_or_height = 0.8,
            },
        );

        zgui.tableSetupScrollFreeze(0, 1);
        zgui.tableHeadersRow();

        for (loader.plugins.items, 0..)
            |*info, idx|
        {
            zgui.tableNextRow(.{});
            zgui.pushIntId(@intCast(idx));
            defer zgui.popId();

            // Name — clickable to scroll to detail section
            _ = zgui.tableNextColumn();
            if (
                zgui.selectable(
                    to_sentinel(slice_or_none(info.name)),
                    .{},
                )
            )
            {
                scroll_to_plugin = idx;
            }

            // Version
            _ = zgui.tableNextColumn();
            zgui.textUnformatted(slice_or_none(info.version));

            // ABI version
            _ = zgui.tableNextColumn();
            zgui.text("{d}", .{info.abi_version});

            // Status
            _ = zgui.tableNextColumn();
            if (!info.loaded)
            {
                zgui.textDisabled("Unloaded", .{});
            }
            else if (!info.enabled)
            {
                zgui.textDisabled("Disabled", .{});
            }
            else if (info.compatible)
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

            // Exports — counts by type
            _ = zgui.tableNextColumn();
            draw_export_counts(info);

            // Provenance
            _ = zgui.tableNextColumn();
            zgui.textUnformatted(slice_or_none(info.provenance));

            // Actions
            _ = zgui.tableNextColumn();
            if (info.loaded)
            {
                // Loaded plugin: Enable/Disable + Unload + Reload
                if (info.enabled)
                {
                    if (zgui.smallButton("Disable"))
                    {
                        loader.disable_plugin(idx);
                        deactivate_plugin_activities(
                            &app.orchestrator,
                            info,
                        );
                    }
                }
                else
                {
                    if (zgui.smallButton("Enable"))
                    {
                        loader.enable_plugin(idx);
                        activate_plugin_activities(
                            &app.orchestrator,
                            info,
                        );
                    }
                }
                zgui.sameLine(.{});
                if (deferred_action == .none)
                {
                    if (zgui.smallButton("Unload"))
                    {
                        deferred_action = .unload;
                        deferred_index = idx;
                    }
                    zgui.sameLine(.{});
                    if (zgui.smallButton("Reload"))
                    {
                        deferred_action = .reload;
                        deferred_index = idx;
                    }
                }
                else
                {
                    zgui.textDisabled("Unload", .{});
                    zgui.sameLine(.{});
                    zgui.textDisabled("Reload", .{});
                }
            }
            else
            {
                // Unloaded plugin: only Load
                if (deferred_action == .none)
                {
                    if (zgui.smallButton("Load"))
                    {
                        deferred_action = .load;
                        deferred_index = idx;
                    }
                }
                else
                {
                    zgui.textDisabled("Load", .{});
                }
            }
        }
    }
}

/// Execute the deferred unload/reload/load after all UI drawing
/// is done.
fn execute_deferred_action(
    app: *FundamentalApp,
) void
{
    const action = deferred_action;
    const idx = deferred_index;
    deferred_action = .none;

    const loader = &app.plugin_loader;
    if (idx >= loader.plugins.items.len)
    {
        return;
    }

    switch (action) {
        .none => {},
        .unload =>
        {
            app.teardown_plugin_activities(
                &loader.plugins.items[idx],
            );
            loader.unload_plugin(idx);
        },
        .reload =>
        {
            app.teardown_plugin_activities(
                &loader.plugins.items[idx],
            );
            loader.unload_plugin(idx);
            if (loader.load_plugin_at(idx))
            {
                const info = &loader.plugins.items[idx];
                app.load_activities_for_plugin(info);
                activate_plugin_activities(
                    &app.orchestrator,
                    info,
                );
            }
        },
        .load =>
        {
            if (loader.load_plugin_at(idx))
            {
                const info = &loader.plugins.items[idx];
                app.load_activities_for_plugin(info);
                activate_plugin_activities(
                    &app.orchestrator,
                    info,
                );
            }
        },
    }
}

// -----------------------------------------------------------------
// Helpers
// -----------------------------------------------------------------

/// Deactivate all activities belonging to a plugin.
/// Only calls deactivate on activities that are currently active,
/// to avoid calling the plugin's Deactivate callback on
/// uninitialized state.
fn deactivate_plugin_activities(
    orchestrator: *Orchestrator,
    info: *const PluginInfo,
) void
{
    for (info.activity_names.items)
        |act_name|
    {
        const activity = orchestrator.find_activity(
            act_name,
        ) orelse continue;
        if (!activity.lab.active)
        {
            continue;
        }

        var name_buf: [256:0]u8 = undefined;
        const nlen = @min(act_name.len, name_buf.len - 1);
        @memcpy(name_buf[0..nlen], act_name[0..nlen]);
        name_buf[nlen] = 0;
        orchestrator.deactivate_activity(@ptrCast(&name_buf));
    }
}

/// Reactivate all activities belonging to a plugin.
/// Only calls activate on activities that are not currently active,
/// to avoid double-calling the plugin's Activate callback
/// (which may allocate resources).
fn activate_plugin_activities(
    orchestrator: *Orchestrator,
    info: *const PluginInfo,
) void
{
    for (info.activity_names.items)
        |act_name|
    {
        const activity = orchestrator.find_activity(
            act_name,
        ) orelse continue;
        if (activity.lab.active)
        {
            continue;
        }

        var name_buf: [256:0]u8 = undefined;
        const nlen = @min(act_name.len, name_buf.len - 1);
        @memcpy(name_buf[0..nlen], act_name[0..nlen]);
        name_buf[nlen] = 0;
        orchestrator.activate_activity(@ptrCast(&name_buf));
    }
}

fn slice_or_none(
    s: []const u8,
) []const u8
{
    return if (s.len > 0) s else "(none)";
}

/// Show export counts by type in a compact format.
fn draw_export_counts(
    info: *const PluginInfo,
) void
{
    const na = info.activity_names.items.len;
    const np = info.provider_names.items.len;
    const ns = info.studio_names.items.len;
    const total = na + np + ns;

    if (total == 0)
    {
        zgui.textDisabled("0", .{});
        return;
    }

    // If all exports are of one type, just show the count.
    // Otherwise break down by type.
    if (np == 0 and ns == 0)
    {
        zgui.text("{d} act", .{na});
    }
    else if (na == 0 and ns == 0)
    {
        zgui.text("{d} prov", .{np});
    }
    else if (na == 0 and np == 0)
    {
        zgui.text("{d} studio", .{ns});
    }
    else
    {
        zgui.text(
            "{d} act, {d} prov, {d} studio",
            .{ na, np, ns },
        );
    }
}

/// Convert a Zig slice to a sentinel-terminated pointer using a
/// static buffer. Only valid until the next call.
fn to_sentinel(
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
