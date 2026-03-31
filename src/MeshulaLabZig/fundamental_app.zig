//! FundamentalApp — Zig port of MeshulaLab's App.h/App.cpp
//!
//! Provides the main application class for MeshulaLab-style applications:
//! plugin discovery, orchestrator lifecycle, main menu system, DockSpace
//! viewport (optional), viewport interaction with hover/drag bidding,
//! power save, and file drop handling.
//!
//! FundamentalApp provides its own `draw` callback to `app_wrapper.sokol_main()`
//! and owns the orchestrator, CSP engine, plugin loader, and all per-frame
//! interaction state.

const std = @import("std");
const builtin = @import("builtin");

const ziis = @import("zgui_cimgui_implot_sokol");
const zgui = ziis.zgui;
const sokol = ziis.sokol;
const sapp = sokol.app;
const app_wrapper = ziis.app_wrapper;

const MeshulaLab = @import("MeshulaLab");
const Orchestrator = @import("orchestrator.zig").Orchestrator;
const Activity = @import("activity.zig").Activity;
const Studio = @import("studio.zig").Studio;
const ActivityConfig = @import("studio.zig").ActivityConfig;
const CspEngine = @import("csp.zig").CspEngine;
const plugin_loader_mod = @import("plugin_loader.zig");
const PluginLoader = plugin_loader_mod.PluginLoader;
const PluginInfo = plugin_loader_mod.PluginInfo;
const plugin_manager = @import("plugin_manager_activity.zig");
const ViewInteraction = @import("view_interaction.zig").ViewInteraction;
const ViewDimensions = @import("view_interaction.zig").ViewDimensions;
const layout_mod = @import("layout.zig");
const Layout = layout_mod.Layout;
const LayoutRect = layout_mod.Rect;

const options = @import("fundamental_app_options");
const ENABLE_DOCKING = options.enable_docking;
const PLUGIN_DIR = options.plugin_dir;

const IS_WASM = builtin.target.cpu.arch.isWasm();

const log = std.log.scoped(.fundamental_app);

/// Global instance pointer — needed because app_wrapper callbacks are
/// comptime function pointers with no user-data parameter.
var INSTANCE: ?*FundamentalApp = null;

pub const FundamentalApp = struct {
    orchestrator: Orchestrator,
    csp_engine: CspEngine,
    plugin_loader: PluginLoader,
    vi: ViewInteraction = .{},
    power_save: bool = true,
    suspend_power_save: i32 = 0,
    should_terminate: bool = false,
    was_dragging: bool = false,
    allocator: std.mem.Allocator,

    /// Parsed layout for the current studio (if it has a layout_spec).
    maybe_layout: ?Layout = null,
    /// Track which studio the layout was parsed for.
    layout_studio_ptr: ?*Studio = null,

    show: struct {
        plugin_manager: bool = false,
        demo_studio: bool = false,
        imgui_demo: bool = false,
        implot_demo: bool = false,
    } = .{},

    // User-provided callbacks
    maybe_post_zgui_init: ?*const fn () void = null,
    maybe_pre_zgui_shutdown_cleanup: ?*const fn () void = null,
    maybe_file_drop: ?*const fn (
        count: i32,
        paths: []const [:0]const u8,
    ) void = null,

    /// Configuration for `run()`.
    pub const RunConfig = struct {
        title: [:0]const u8 = "MeshulaLab",
        dimensions: [2]i32 = .{ 1280, 800 },
        logger: ?app_wrapper.LogFn = null,
        max_vertices: i32 =
        if (IS_WASM) 64 * 1024 else 256 * 1024 * 1024,
        maybe_post_zgui_init: ?*const fn () void = null,
        maybe_pre_zgui_shutdown_cleanup: ?*const fn () void = null,
        maybe_file_drop: ?*const fn (
            count: i32,
            paths: []const [:0]const u8,
        ) void = null,
    };

    // -----------------------------------------------------------------
    // Lifecycle
    // -----------------------------------------------------------------

    pub fn init(
        allocator: std.mem.Allocator,
    ) FundamentalApp
    {
        var self = FundamentalApp{
            .orchestrator = Orchestrator.init(allocator),
            .csp_engine = CspEngine.init(allocator),
            .plugin_loader = PluginLoader.init(allocator),
            .allocator = allocator,
        };

        // Discover plugins (native only). Activity creation is
        // deferred to postZguiInit so sokol/imgui are available
        // for stateful activities.
        if (!IS_WASM)
        {
            log.info("plugin directory: {s}", .{PLUGIN_DIR});
            self.plugin_loader.discover_plugins_in_directory(PLUGIN_DIR);
        }

        // Start CSP engine
        self.csp_engine.run();

        return self;
    }

    pub fn deinit(
        self: *FundamentalApp,
    ) void
    {
        self.csp_engine.deinit();
        self.plugin_loader.deinit();
        self.orchestrator.deinit();
        if (INSTANCE == self)
        {
            INSTANCE = null;
        }
    }

    /// Launch the sokol application loop. This function does not
    /// return until the application exits.
    ///
    /// `config` must be comptime-known because the underlying
    /// sokol_main requires a comptime parameter.
    pub fn run(
        self: *FundamentalApp,
        comptime config: RunConfig,
    ) void
    {
        INSTANCE = self;
        self.maybe_post_zgui_init = config.maybe_post_zgui_init;
        self.maybe_pre_zgui_shutdown_cleanup =
        config.maybe_pre_zgui_shutdown_cleanup;
        self.maybe_file_drop = config.maybe_file_drop;

        app_wrapper.sokol_main(
            .{
                .draw = &draw_thunk,
                .title = config.title,
                .dimensions = config.dimensions,
                .logger = config.logger,
                .max_vertices = config.max_vertices,
                .maybe_post_zgui_init = &post_zgui_init_thunk,
                .maybe_pre_zgui_shutdown_cleanup =
                &pre_zgui_shutdown_thunk,
                .event = &event_thunk,
                .enable_dragndrop = true,
                .max_dropped_files = 8,
                .max_dropped_file_path_length = 8192,
            },
        );
    }

    // -----------------------------------------------------------------
    // Delegation helpers
    // -----------------------------------------------------------------

    pub fn register_activity(
        self: *FundamentalApp,
        activity: *Activity,
    ) void
    {
        self.orchestrator.register_activity(activity);
    }

    pub fn register_studio(
        self: *FundamentalApp,
        studio: *Studio,
    ) void
    {
        self.orchestrator.register_studio(studio);
    }

    pub fn activate_studio(
        self: *FundamentalApp,
        studio_name: []const u8,
    ) void
    {
        self.orchestrator.activate_studio(studio_name);
    }

    // -----------------------------------------------------------------
    // Plugin loading
    // -----------------------------------------------------------------

    /// Create Activity instances from discovered plugins and register
    /// them with the orchestrator.
    fn load_plugin_activities(
        self: *FundamentalApp,
    ) void
    {
        for (self.plugin_loader.plugins.items)
            |info|
        {
            if (!info.loaded or !info.compatible)
            {
                continue;
            }
            self.load_activities_for_plugin(&info);
        }
    }

    /// Create and register Activity instances for a single plugin.
    pub fn load_activities_for_plugin(
        self: *FundamentalApp,
        info: *const PluginInfo,
    ) void
    {
        for (info.activity_names.items)
            |act_name|
        {
            // The activity names originate from the plugin's
            // GetActivityName which returns [*:0]const u8. The
            // underlying memory is null-terminated even though we
            // store them as []const u8, so we can recover the
            // sentinel pointer safely. This pointer is stable for
            // the lifetime of the loaded dylib, which is critical
            // because the plugin's CreateActivity may store it.
            const name_z: [*:0]const u8 = (
                act_name.ptr[0..act_name.len :0]
            );

            const maybe_c_activity = self.plugin_loader.create_activity(
                name_z,
            );
            const c_activity = maybe_c_activity orelse {
                log.warn(
                    "plugin failed to create activity: {s}",
                    .{act_name},
                );
                continue;
            };

            // Wrap the C activity in a Zig Activity and register it.
            // Heap-allocate since the orchestrator stores a pointer.
            const wrapper = self.allocator.create(
                Activity,
            ) catch {
                log.warn(
                    "alloc failed for plugin activity: {s}",
                    .{act_name},
                );
                continue;
            };
            wrapper.* = .{
                .lab = c_activity.*,
                .maybe_plugin_activity = c_activity,
            };
            self.orchestrator.register_activity(wrapper);

            log.info(
                "registered plugin activity: {s}",
                .{act_name},
            );
        }
    }

    /// Create Studio instances from discovered plugins and register
    /// them with the orchestrator.
    fn load_plugin_studios(
        self: *FundamentalApp,
    ) void
    {
        for (self.plugin_loader.plugins.items)
            |info|
        {
            if (!info.loaded or !info.compatible)
            {
                continue;
            }
            self.load_studios_for_plugin(&info);
        }
    }

    /// Create and register Studio instances for a single plugin.
    pub fn load_studios_for_plugin(
        self: *FundamentalApp,
        info: *const PluginInfo,
    ) void
    {
        for (info.studio_names.items)
            |st_name|
        {
            const name_z: [*:0]const u8 = (
                st_name.ptr[0..st_name.len :0]
            );

            const maybe_c_studio = self.plugin_loader.create_studio(
                name_z,
            );
            const c_studio = maybe_c_studio orelse {
                log.warn(
                    "plugin failed to create studio: {s}",
                    .{st_name},
                );
                continue;
            };

            // Read configs from the C studio's vtable callbacks
            const configs = self.read_studio_configs(c_studio) orelse {
                log.warn(
                    "failed to read configs for studio: {s}",
                    .{st_name},
                );
                continue;
            };

            // Wrap in a Zig Studio and register
            const wrapper = self.allocator.create(
                Studio,
            ) catch {
                log.warn(
                    "alloc failed for plugin studio: {s}",
                    .{st_name},
                );
                continue;
            };
            wrapper.* = .{
                .lab = c_studio.*,
                .configs = configs,
                .maybe_plugin_studio = c_studio,
            };
            self.orchestrator.register_studio(wrapper);

            log.info(
                "registered plugin studio: {s}",
                .{st_name},
            );
        }
    }

    /// Read ActivityConfig entries from a C studio's vtable callbacks,
    /// returning a heap-allocated slice of Zig ActivityConfigs.
    fn read_studio_configs(
        self: *FundamentalApp,
        c_studio: *MeshulaLab.Studio,
    ) ?[]const ActivityConfig
    {
        const count_fn = c_studio.GetActivityCount orelse return null;
        const config_fn = c_studio.GetActivityConfig orelse return null;

        const count: usize = @intCast(count_fn(c_studio.instance));
        if (count == 0)
        {
            return &.{};
        }

        const configs = self.allocator.alloc(
            ActivityConfig,
            count,
        ) catch return null;

        for (0..count)
            |i|
        {
            const maybe_c_cfg = config_fn(
                c_studio.instance,
                @intCast(i),
            );
            const c_cfg = maybe_c_cfg orelse {
                self.allocator.free(configs);
                return null;
            };
            configs[i] = .{
                .name = @ptrCast(c_cfg.*.name),
                .ui_initially_visible = c_cfg.*.uiInitiallyVisible,
                .panel_id = @ptrCast(c_cfg.*.panelId),
                .window_name = @ptrCast(c_cfg.*.windowName),
            };
        }
        return configs;
    }

    /// Tear down all Activity instances belonging to a plugin:
    /// deactivate (if active), unregister from orchestrator, destroy
    /// via plugin, and free the wrapper. Must be called before
    /// unloading a plugin.
    pub fn teardown_plugin_activities(
        self: *FundamentalApp,
        info: *const PluginInfo,
    ) void
    {
        const desc = info.maybe_descriptor orelse return;
        const destroy_fn = desc.DestroyActivity orelse null;

        for (info.activity_names.items)
            |act_name|
        {
            // Only deactivate if the activity is currently active,
            // to avoid double-calling the plugin's Deactivate
            // callback (which may free resources).
            if (self.orchestrator.find_activity(act_name))
                |activity|
            {
                if (activity.lab.active)
                {
                    var name_buf: [256:0]u8 = undefined;
                    const nlen = @min(
                        act_name.len,
                        name_buf.len - 1,
                    );
                    @memcpy(name_buf[0..nlen], act_name[0..nlen]);
                    name_buf[nlen] = 0;
                    self.orchestrator.deactivate_activity(
                        @ptrCast(&name_buf),
                    );
                }
            }

            // Unregister from orchestrator
            if (self.orchestrator.unregister_activity(act_name))
                |wrapper|
            {
                // Destroy via the plugin using the original pointer
                // that the plugin allocated (not our wrapper copy).
                if (destroy_fn)
                    |dfn|
                {
                    if (wrapper.maybe_plugin_activity)
                        |original|
                    {
                        dfn(original);
                    }
                }
                // Free the Zig wrapper
                self.allocator.destroy(wrapper);

                log.info(
                    "torn down plugin activity: {s}",
                    .{act_name},
                );
            }
        }
    }

    // -----------------------------------------------------------------
    // Power save
    // -----------------------------------------------------------------

    pub fn is_power_save(
        self: *const FundamentalApp,
    ) bool
    {
        return self.power_save and self.suspend_power_save <= 0;
    }

    pub fn set_power_save(
        self: *FundamentalApp,
        enable: bool,
    ) void
    {
        self.power_save = enable;
    }

    pub fn set_suspend_power_save(
        self: *FundamentalApp,
        frames: i32,
    ) void
    {
        self.suspend_power_save = frames;
    }

    // -----------------------------------------------------------------
    // Diagnostics
    // -----------------------------------------------------------------

    pub fn print_status(
        self: *const FundamentalApp,
    ) void
    {
        const writer = std.io.getStdOut().writer();

        writer.print(
                \\
                \\=======================================================
                \\MeshulaLab Framework Status Report (Zig)
                \\=======================================================
                \\
                \\
            ,
            .{},
        ) catch {};

        // Studios
        writer.print("Registered Studios:\n", .{}) catch {};
        writer.print(
            "---------------------------------------------------\n",
            .{},
        ) catch {};
        {
            var orch = @constCast(&self.orchestrator);
            var it = orch.studio_names();
            var count: usize = 0;
            while (it.next())
                |name|
            {
                const active = (
                    if (orch.current_studio())
                        |cs|
                        std.mem.eql(u8, cs.name(), name)
                    else false
                );
                writer.print("  - {s}", .{name}) catch {};
                if (active)
                {
                    writer.print(" (ACTIVE)", .{}) catch {};
                }
                writer.print("\n", .{}) catch {};
                count += 1;
            }
            if (count == 0)
            {
                writer.print("  (none)\n", .{}) catch {};
            }
        }

        // Activities
        writer.print("\nRegistered Activities:\n", .{}) catch {};
        writer.print(
            "---------------------------------------------------\n",
            .{},
        ) catch {};
        {
            var orch = @constCast(&self.orchestrator);
            var it = orch.activity_names();
            var count: usize = 0;
            while (it.next())
                |name|
            {
                if (orch.find_activity(name))
                    |activity|
                {
                    writer.print("  - {s}", .{name}) catch {};
                    if (activity.is_active())
                    {
                        writer.print(" (active", .{}) catch {};
                        if (activity.is_ui_visible())
                        {
                            writer.print(", visible", .{}) catch {};
                        }
                        writer.print(")", .{}) catch {};
                    }
                    writer.print("\n", .{}) catch {};
                }
                count += 1;
            }
            if (count == 0)
            {
                writer.print("  (none)\n", .{}) catch {};
            }
        }

        // Plugins
        if (!IS_WASM)
        {
            writer.print("\nDiscovered Plugins:\n", .{}) catch {};
            writer.print(
                "---------------------------------------------------\n",
                .{},
            ) catch {};
            if (self.plugin_loader.plugins.items.len == 0)
            {
                writer.print("  (none)\n", .{}) catch {};
            }
            else
            {
                for (self.plugin_loader.plugins.items)
                    |info|
                {
                    writer.print(
                        "  - {s} v{s}",
                        .{ info.name, info.version },
                    ) catch {};
                    if (!info.loaded)
                    {
                        writer.print(" [UNLOADED]", .{}) catch {};
                    }
                    else if (info.compatible)
                    {
                        writer.print(" [LOADED]", .{}) catch {};
                    }
                    else
                    {
                        writer.print(
                            " [INCOMPATIBLE]",
                            .{},
                        ) catch {};
                    }
                    writer.print("\n", .{}) catch {};
                }
            }
        }

        writer.print(
            \\
            \\=======================================================
            \\
            \\
            ,
            .{},
        ) catch {};
    }

    // -----------------------------------------------------------------
    // Frame callback — the core of the port
    // -----------------------------------------------------------------

    fn draw(
        self: *FundamentalApp,
    ) !void
    {
        // Power save tick
        if (self.suspend_power_save > 0)
        {
            self.suspend_power_save -= 1;
        }

        const dt: f32 = @floatCast(sapp.frameDuration());

        // Process CSP events (non-blocking poll)
        self.csp_engine.process_all();

        // Service orchestrator (deferred activations + update)
        self.orchestrator.service(dt);

        // Reparse layout if the studio changed
        self.update_layout();

        // --- Main menu bar ---
        if (zgui.beginMainMenuBar())
        {
            self.draw_studio_menu();
            self.draw_activities_menu();
            self.draw_help_menu();
            self.orchestrator.run_main_menu();
            if (ENABLE_DOCKING)
            {
                self.draw_window_menu();
            }
            zgui.endMainMenuBar();
        }

        // --- Workspace area ---
        if (ENABLE_DOCKING)
        {
            self.draw_docking_workspace(dt);
        }
        else
        {
            self.draw_tab_bar_workspace(dt);
        }

        // --- Floating windows ---
        if (self.show.plugin_manager)
        {
            self.draw_plugin_manager_window();
        }

        if (self.show.demo_studio)
        {
            self.draw_demo_studio_window();
        }
        
        if (self.show.imgui_demo)
        {
            zgui.showDemoWindow(&self.show.imgui_demo);
        }

        if (self.show.implot_demo)
        {
            zgui.plot.showDemoWindow(&self.show.implot_demo);
        }
    }

    // -----------------------------------------------------------------
    // Menu rendering
    // -----------------------------------------------------------------

    fn draw_studio_menu(
        self: *FundamentalApp,
    ) void
    {
        // Build the menu title from the current studio name
        const current_name = (
            if (self.orchestrator.current_studio()) |cs| cs.name()
            else "Welcome"
        );

        // We need a sentinel-terminated string for zgui
        var title_buf: [256:0]u8 = undefined;
        const title_len = @min(current_name.len, title_buf.len - 5);
        @memcpy(title_buf[0..title_len], current_name[0..title_len]);
        // Append "###St" for stable ImGui ID
        const suffix = "###St";
        @memcpy(
            title_buf[title_len .. title_len + suffix.len],
            suffix,
        );
        title_buf[title_len + suffix.len] = 0;
        const menu_title: [:0]const u8 = (
            title_buf[0 .. title_len + suffix.len :0]
        );

        if (zgui.beginMenu(menu_title, true))
        {
            var names_it = self.orchestrator.studio_names();
            while (names_it.next())
                |name|
            {
                // Need sentinel-terminated name for zgui
                var name_buf: [256:0]u8 = undefined;
                const nlen = @min(name.len, name_buf.len - 1);
                @memcpy(name_buf[0..nlen], name[0..nlen]);
                name_buf[nlen] = 0;
                const name_z: [:0]const u8 = name_buf[0..nlen :0];

                const is_active = std.mem.eql(
                    u8,
                    name,
                    current_name,
                );
                if (
                    zgui.menuItem(
                        name_z,
                        .{
                            .selected = is_active,
                        },
                    )
                )
                {
                    if (!is_active)
                    {
                        self.orchestrator.activate_studio(name);
                        std.log.info("Activating studio {s}", .{name});
                    }
                }
            }

            zgui.separator();
            if (
                zgui.menuItem(
                    "Plugin Manager",
                    .{ .selected = self.show.plugin_manager },
                )
            )
            {
                self.show.plugin_manager = !self.show.plugin_manager;
            }
            zgui.separator();
            if (zgui.menuItem("Quit", .{}))
            {
                self.should_terminate = true;
                sapp.quit();
            }
            zgui.endMenu();
        }

    }

    fn draw_activities_menu(
        self: *FundamentalApp,
    ) void
    {
        if (zgui.beginMenu("Activities##mmenu", true))
        {
            var names_it = self.orchestrator.activity_names();
            while (names_it.next())
                |name|
            {
                const activity = self.orchestrator.find_activity(
                    name,
                ) orelse continue;

                const disabled_by_plugin = (
                    self.plugin_loader.is_activity_disabled(name)
                );

                const is_active = (
                    activity.is_active() and activity.is_ui_visible()
                );

                var name_buf: [256:0]u8 = undefined;
                const nlen = @min(name.len, name_buf.len - 1);
                @memcpy(name_buf[0..nlen], name[0..nlen]);
                name_buf[nlen] = 0;
                const name_z: [:0]const u8 = name_buf[0..nlen :0];

                if (
                    zgui.menuItem(
                        name_z,
                        .{
                            .selected = is_active,
                            .enabled = !disabled_by_plugin,
                        },
                    )
                )
                {
                    var act_buf: [256:0]u8 = undefined;
                    @memcpy(act_buf[0..nlen], name[0..nlen]);
                    act_buf[nlen] = 0;
                    if (is_active)
                    {
                        self.orchestrator.deactivate_activity(
                            @ptrCast(&act_buf),
                        );
                    }
                    else
                    {
                        self.orchestrator.activate_activity(
                            @ptrCast(&act_buf),
                        );
                    }
                }
            }
            zgui.endMenu();
        }
    }

    fn draw_window_menu(
        _: *FundamentalApp,
    ) void
    {
        if (!ENABLE_DOCKING)
        {
            return;
        }
        if (zgui.beginMenu("Window", true))
        {
            if (zgui.menuItem("Reset Layout", .{}))
            {
                zgui.dockBuilderRemoveNode(
                    zgui.DockSpace(
                        "DockSpace",
                        .{ 0.0, 0.0 },
                        .{},
                    ),
                );
            }
            zgui.endMenu();
        }
    }

    fn draw_help_menu(
        self: *@This(),
    ) void
    {
        // help menu
        if (zgui.beginMenu("Help", true))
        {
            defer zgui.endMenu();

            if (
                zgui.menuItem(
                    "ZIIS Demo Studio",
                    .{ .selected = self.show.demo_studio },
                )
            )
            {
                self.show.demo_studio = !self.show.demo_studio;
            }

            zgui.separator();

            if (
                zgui.menuItem(
                    "ImGui Demo Page",
                    .{ .selected = self.show.imgui_demo },
                )
            )
            {
                self.show.imgui_demo = !self.show.imgui_demo;
            }

            if (
                zgui.menuItem(
                    "ImPlot Demo Page",
                    .{ .selected = self.show.implot_demo },
                )
            )
            {
                self.show.implot_demo = !self.show.implot_demo;
            }
        }
    }

    // -----------------------------------------------------------------
    // Floating windows
    // -----------------------------------------------------------------

    fn draw_plugin_manager_window(
        self: *FundamentalApp,
    ) void
    {
        zgui.setNextWindowSize(
            .{
                .w = 800,
                .h = 500,
                .cond = .first_use_ever,
            },
        );
        if (
            zgui.begin(
                "Plugin Manager###PluginMgr",
                .{
                    .popen = &self.show.plugin_manager,
                },
            )
        )
        {
            plugin_manager.runUI(
                @ptrCast(self),
                null,
            );
        }
        zgui.end();
    }

    fn draw_demo_studio_window(
        self: *FundamentalApp,
    ) void
    {
        zgui.setNextWindowSize(
            .{
                .w = 800,
                .h = 500,
                .cond = .first_use_ever,
            },
        );
        if (
            zgui.begin(
                "Demo Studio###DemoStd",
                .{
                    .popen = &self.show.demo_studio,
                },
            )
        )
        {
            // XXX
            if (self.orchestrator.find_studio("DemoStudio"))
                |studio|
            {
                if (zgui.beginTabBar("Demo Activities", .{}))
                {
                    defer zgui.endTabBar();

                    for (studio.configs)
                        |activity_config|
                    {
                        const act_name = (
                            std.mem.span(activity_config.name)
                        );
                        if (self.orchestrator.find_activity(act_name))
                            |activity|
                        {
                            const BUFLEN = 256;
                            var name_buf:[BUFLEN:0]u8 = undefined;
                            const name_z = std.fmt.bufPrintZ(
                                &name_buf,
                                "{s}",
                                .{ act_name[0..@min(BUFLEN, act_name.len)] },
                            ) catch unreachable;

                            if (zgui.beginTabItem(name_z, .{}))
                            {
                                defer zgui.endTabItem();

                                if (activity.lab.RunUI)
                                    |run_ui_fn|
                                {
                                    run_ui_fn(activity.lab.instance, null);
                                }
                            }
                        }
                    }
                }
            }
            else 
            {
                zgui.text(
                    "Unable to find the Demo Studio - check logs?",
                    .{}
                );
            }
        }
        zgui.end();
    }

    // -----------------------------------------------------------------
    // Layout positioning
    // -----------------------------------------------------------------

    /// Reparse the layout if the active studio changed.
    fn update_layout(
        self: *FundamentalApp,
    ) void
    {
        const current = self.orchestrator.maybe_current_studio;
        if (current != self.layout_studio_ptr)
        {
            self.layout_studio_ptr = current;
            if (current)
                |studio|
            {
                if (studio.layout_spec)
                    |spec|
                {
                    self.maybe_layout = Layout.parse(
                        std.mem.span(spec),
                    );
                }
                else
                {
                    self.maybe_layout = null;
                }
            }
            else
            {
                self.maybe_layout = null;
            }
        }
    }

    /// If a layout is active, position each activity's ImGui window
    /// according to its panel assignment before running its UI.
    fn position_activity_windows(
        self: *FundamentalApp,
        layout: *Layout,
        area: LayoutRect,
    ) void
    {
        layout.solve(area);

        const studio = self.orchestrator.maybe_current_studio orelse return;
        for (studio.configs)
            |cfg|
        {
            const panel_id = cfg.panel_id orelse continue;
            const window_name = cfg.window_name orelse continue;

            const rect = layout.find_panel(
                std.mem.span(panel_id),
            ) orelse continue;

            zgui.setNextWindowPos(.{
                .x = rect.x,
                .y = rect.y,
                .cond = .always,
            });
            zgui.setNextWindowSize(.{
                .w = rect.w,
                .h = rect.h,
                .cond = .always,
            });

            // Run this activity's UI inside a positioned window
            const act_name = std.mem.span(cfg.name);
            if (self.orchestrator.find_activity(act_name))
                |activity|
            {
                if (activity.lab.active and activity.lab.uiVisible)
                {
                    if (activity.lab.RunUI)
                        |run_ui_fn|
                    {
                        const wn_span = std.mem.span(window_name);
                        var name_buf: [256:0]u8 = undefined;
                        const nlen = @min(
                            wn_span.len,
                            name_buf.len - 1,
                        );
                        @memcpy(name_buf[0..nlen], wn_span[0..nlen]);
                        name_buf[nlen] = 0;
                        const name_z: [:0]const u8 = (
                            name_buf[0..nlen :0]
                        );

                        if (
                            zgui.begin(
                                name_z,
                                .{
                                    .flags = .{
                                        .no_move = true,
                                        .no_resize = true,
                                        .no_collapse = true,
                                    },
                                },
                            )
                        )
                        {
                            run_ui_fn(activity.lab.instance, null);
                        }
                        zgui.end();
                    }
                }
            }
        }
    }

    // -----------------------------------------------------------------
    // Workspace rendering — docking variant
    // -----------------------------------------------------------------

    fn draw_docking_workspace(
        self: *FundamentalApp,
        dt: f32,
    ) void
    {
        if (!ENABLE_DOCKING)
        {
            return;
        }

        const viewport = zgui.getMainViewport();
        const vp_size = viewport.getSize();
        const vp_pos = viewport.getWorkPos();
        const vp_work_size = viewport.getWorkSize();

        // Set up the host window for the dockspace
        zgui.setNextWindowPos(.{ .x = vp_pos[0], .y = vp_pos[1] });
        zgui.setNextWindowSize(.{ .w = vp_work_size[0], .h = vp_work_size[1] });
        zgui.setNextWindowViewport(viewport.getId());

        zgui.pushStyleVar1f(.{ .idx = .window_rounding, .v = 0.0 });
        zgui.pushStyleVar1f(.{ .idx = .window_border_size, .v = 0.0 });
        zgui.pushStyleVar2f(.{ .idx = .window_padding, .v = .{ 0.0, 0.0 } });

        _ = zgui.begin(
            "DockSpaceHost",
            .{
                .flags = .{
                    .no_title_bar = true,
                    .no_collapse = true,
                    .no_background = true,
                },
            },
        );
        zgui.popStyleVar(.{ .count = 3 });

        const dockspace_id = zgui.DockSpace(
            "DockSpace",
            .{ 0.0, 0.0 },
            .{ .passthru_central_node = true },
        );
        zgui.end();

        // Get the central node for viewport rendering
        const maybe_central_node = (
            zgui.dockBuilderGetCentralNode(dockspace_id)
        );

        var lab_vi = self.vi.to_lab();
        lab_vi.dt = dt;
        lab_vi.view.w = vp_size[0];
        lab_vi.view.h = vp_size[1];

        if (maybe_central_node)
            |central_node|
        {
            var node_rect: [4]f32 = undefined;
            zgui.dockNodeRect(central_node, &node_rect);
            lab_vi.view.wx = node_rect[0];
            lab_vi.view.wy = node_rect[1];
            lab_vi.view.ww = node_rect[2] - node_rect[0];
            lab_vi.view.wh = node_rect[3] - node_rect[1];
        }

        // If a layout is active, use panel positioning instead of
        // free-form docking.
        if (self.maybe_layout)
            |*layout|
        {
            self.position_activity_windows(
                layout,
                .{
                    .x = vp_pos[0],
                    .y = vp_pos[1],
                    .w = vp_work_size[0],
                    .h = vp_work_size[1],
                },
            );
        }
        else
        {
            // Run Activity UIs (they create their own dockable windows)
            self.orchestrator.run_activity_uis(&lab_vi);
        }

        // Viewport interaction
        self.process_viewport_interaction(&lab_vi);
    }

    // -----------------------------------------------------------------
    // Workspace rendering — tab bar variant (no docking)
    // -----------------------------------------------------------------

    fn draw_tab_bar_workspace(
        self: *FundamentalApp,
        dt: f32,
    ) void
    {
        const viewport = zgui.getMainViewport();
        const vp_size = viewport.getSize();
        const work_pos = viewport.getWorkPos();
        const work_size = viewport.getWorkSize();

        var lab_vi = self.vi.to_lab();
        lab_vi.dt = dt;
        lab_vi.view.w = vp_size[0];
        lab_vi.view.h = vp_size[1];
        lab_vi.view.wx = work_pos[0];
        lab_vi.view.wy = work_pos[1];
        lab_vi.view.ww = work_size[0];
        lab_vi.view.wh = work_size[1];

        // If a layout is active, use panel positioning instead of tabs
        if (self.maybe_layout)
            |*layout|
        {
            self.position_activity_windows(
                layout,
                .{
                    .x = work_pos[0],
                    .y = work_pos[1],
                    .w = work_size[0],
                    .h = work_size[1],
                },
            );

            // Viewport interaction
            self.process_viewport_interaction(&lab_vi);
            return;
        }

        // Fill the work area (below the main menu bar)
        zgui.setNextWindowPos(
            .{
                .x = work_pos[0],
                .y = work_pos[1],
            },
        );
        zgui.setNextWindowSize(
            .{
                .w = work_size[0],
                .h = work_size[1],
            },
        );

        _ = zgui.begin(
            "##MainWindow",
            .{
                .flags = .{
                    .no_title_bar = true,
                    .no_resize = true,
                    .no_move = true,
                    .no_collapse = true,
                },
            },
        );

        // Tab bar with active activities
        if (zgui.beginTabBar("Activities", .{}))
        {
            var it = self.orchestrator.active_ui_activities();
            while (it.next())
                |activity|
            {
                const act_name = activity.name();
                var name_buf: [256:0]u8 = undefined;
                const nlen = @min(act_name.len, name_buf.len - 1);
                @memcpy(name_buf[0..nlen], act_name[0..nlen]);
                name_buf[nlen] = 0;
                const name_z: [:0]const u8 = (
                    name_buf[0..nlen :0]
                );

                if (zgui.beginTabItem(name_z, .{}))
                {
                    if (activity.lab.RunUI)
                        |run_ui_fn|
                    {
                        run_ui_fn(activity.lab.instance, &lab_vi);
                    }
                    zgui.endTabItem();
                }
            }
            zgui.endTabBar();
        }

        zgui.end();

        // Viewport interaction
        self.process_viewport_interaction(&lab_vi);
    }

    // -----------------------------------------------------------------
    // Viewport interaction (hover/drag bidding)
    // -----------------------------------------------------------------

    fn process_viewport_interaction(
        self: *FundamentalApp,
        lab_vi: *MeshulaLab.ViewInteraction,
    ) void
    {
        // Update mouse position in ViewInteraction
        const mouse_pos = zgui.getMousePos();
        lab_vi.x = mouse_pos[0] - lab_vi.view.wx;
        lab_vi.y = mouse_pos[1] - lab_vi.view.wy;

        const viewport_hovered = zgui.isWindowHovered(.{});
        const is_dragging = viewport_hovered
        and zgui.isMouseDown(.left);

        if (is_dragging)
        {
            lab_vi.start = !self.was_dragging;
            lab_vi.end = false;
            self.orchestrator.run_viewport_dragging(lab_vi);
        }
        else
        {
            if (self.was_dragging)
            {
                lab_vi.start = false;
                lab_vi.end = true;
                self.orchestrator.run_viewport_dragging(lab_vi);
            }
            else
            {
                self.orchestrator.run_viewport_hovering(lab_vi);
            }
        }
        self.was_dragging = is_dragging;

        // Update stored ViewInteraction for next frame
        self.vi = ViewInteraction.from_lab(lab_vi.*);
    }

    // -----------------------------------------------------------------
    // Event handling
    // -----------------------------------------------------------------

    fn handle_event(
        self: *FundamentalApp,
        ev: [*c]const sapp.Event,
    ) void
    {
        _ = sokol.imgui.handleEvent(ev.*);

        switch (ev.*.type) {
            .KEY_DOWN =>
            {
                if (ev.*.key_code == .ESCAPE)
                {
                    self.should_terminate = true;
                    sapp.quit();
                }
            },
            .FILES_DROPPED =>
            {
                if (self.maybe_file_drop)
                    |file_drop_fn|
                {
                    const count = sapp.getNumDroppedFiles();
                    // Build a temporary slice of paths
                    var paths_buf: [8][:0]const u8 = undefined;
                    const n: usize = @intCast(
                        @min(count, @as(i32, @intCast(paths_buf.len))),
                    );
                    var i: usize = 0;
                    while (i < n)
                        : (i += 1)
                    {
                        paths_buf[i] = sapp.getDroppedFilePath(
                            @intCast(i),
                        );
                    }
                    file_drop_fn(count, paths_buf[0..n]);
                }
            },
            else => {},
        }
    }

    // -----------------------------------------------------------------
    // Static thunks — bridge comptime callbacks to instance methods
    // -----------------------------------------------------------------

    fn draw_thunk(
    ) anyerror!void
    {
        const self = INSTANCE orelse return;
        try self.draw();
    }

    fn event_thunk(
        ev: [*c]const sapp.Event,
    ) callconv(.c) void
    {
        const self = INSTANCE orelse return;
        self.handle_event(ev);
    }

    fn post_zgui_init_thunk(
    ) void
    {
        const self = INSTANCE orelse return;

        // Create and register Activities and Studios from discovered
        // plugins. This runs after zgui/sokol init, so Activate
        // callbacks can safely create GPU resources.
        if (!IS_WASM)
        {
            self.load_plugin_activities();
            self.load_plugin_studios();
        }

        if (self.maybe_post_zgui_init)
            |init_fn|
        {
            init_fn();
        }
    }

    fn pre_zgui_shutdown_thunk(
    ) void
    {
        const self = INSTANCE orelse return;
        if (self.maybe_pre_zgui_shutdown_cleanup)
            |cleanup_fn|
        {
            cleanup_fn();
        }
        self.deinit();
    }

};
