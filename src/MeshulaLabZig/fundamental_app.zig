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
const PluginLoader = @import("plugin_loader.zig").PluginLoader;
const plugin_manager = @import("plugin_manager_activity.zig");
const ViewInteraction = @import("view_interaction.zig").ViewInteraction;
const ViewDimensions = @import("view_interaction.zig").ViewDimensions;

const options = @import("fundamental_app_options");
const ENABLE_DOCKING = options.enable_docking;
const PLUGIN_DIR = options.plugin_dir;

const IS_WASM = builtin.target.cpu.arch.isWasm();

const log = std.log.scoped(.fundamental_app);

/// Global instance pointer — needed because app_wrapper callbacks are
/// comptime function pointers with no user-data parameter.
var INSTANCE: ?*FundamentalApp = null;

pub const FundamentalApp = struct
{
    orchestrator: Orchestrator,
    csp_engine: CspEngine,
    plugin_loader: PluginLoader,
    vi: ViewInteraction = .{},
    power_save: bool = true,
    suspend_power_save: i32 = 0,
    should_terminate: bool = false,
    was_dragging: bool = false,
    show_plugin_manager: bool = false,
    allocator: std.mem.Allocator,

    // User-provided callbacks
    maybe_post_zgui_init: ?*const fn () void = null,
    maybe_pre_zgui_shutdown_cleanup: ?*const fn () void = null,
    maybe_file_drop: ?*const fn (
        count: i32,
        paths: []const [:0]const u8,
    ) void = null,

    /// Configuration for `run()`.
    pub const RunConfig = struct
    {
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
            self.plugin_loader.discoverPluginsInDirectory(PLUGIN_DIR);
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
        if (INSTANCE == self) INSTANCE = null;
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
                .draw = &drawThunk,
                .title = config.title,
                .dimensions = config.dimensions,
                .logger = config.logger,
                .max_vertices = config.max_vertices,
                .maybe_post_zgui_init = &postZguiInitThunk,
                .maybe_pre_zgui_shutdown_cleanup =
                    &preZguiShutdownThunk,
                .event = &eventThunk,
                .enable_dragndrop = true,
                .max_dropped_files = 8,
                .max_dropped_file_path_length = 8192,
            },
        );
    }

    // -----------------------------------------------------------------
    // Delegation helpers
    // -----------------------------------------------------------------

    pub fn registerActivity(
        self: *FundamentalApp,
        activity: *Activity,
    ) void
    {
        self.orchestrator.registerActivity(activity);
    }

    pub fn registerStudio(
        self: *FundamentalApp,
        studio: *Studio,
    ) void
    {
        self.orchestrator.registerStudio(studio);
    }

    pub fn activateStudio(
        self: *FundamentalApp,
        studio_name: [*:0]const u8,
    ) void
    {
        self.orchestrator.activateStudio(studio_name);
    }

    // -----------------------------------------------------------------
    // Plugin loading
    // -----------------------------------------------------------------

    /// Create Activity instances from discovered plugins and register
    /// them with the orchestrator.
    fn loadPluginActivities(
        self: *FundamentalApp,
    ) void
    {
        for (self.plugin_loader.plugins.items)
            |info|
        {
            if (!info.compatible) continue;

            for (info.activity_names.items)
                |act_name|
            {
                // Need a sentinel-terminated name for createActivity
                var name_buf: [256:0]u8 = undefined;
                const nlen = @min(act_name.len, name_buf.len - 1);
                @memcpy(name_buf[0..nlen], act_name[0..nlen]);
                name_buf[nlen] = 0;
                const name_z: [*:0]const u8 = @ptrCast(&name_buf);

                const maybe_c_activity = self.plugin_loader.createActivity(
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
                wrapper.* = .{ .lab = c_activity.* };
                self.orchestrator.registerActivity(wrapper);

                log.info(
                    "registered plugin activity: {s}",
                    .{act_name},
                );
            }
        }

    }

    // -----------------------------------------------------------------
    // Power save
    // -----------------------------------------------------------------

    pub fn powerSave(
        self: *const FundamentalApp,
    ) bool
    {
        return self.power_save and self.suspend_power_save <= 0;
    }

    pub fn setPowerSave(
        self: *FundamentalApp,
        enable: bool,
    ) void
    {
        self.power_save = enable;
    }

    pub fn suspendPowerSave(
        self: *FundamentalApp,
        frames: i32,
    ) void
    {
        self.suspend_power_save = frames;
    }

    // -----------------------------------------------------------------
    // Diagnostics
    // -----------------------------------------------------------------

    pub fn printStatus(
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
        , .{}) catch {};

        // Studios
        writer.print("Registered Studios:\n", .{}) catch {};
        writer.print(
            "---------------------------------------------------\n",
            .{},
        ) catch {};
        {
            var orch = @constCast(&self.orchestrator);
            var it = orch.studioNames();
            var count: usize = 0;
            while (it.next())
                |name|
            {
                const active = if (orch.currentStudio())
                    |cs|
                blk: {
                    break :blk std.mem.eql(u8, cs.name(), name);
                }
                else
                    false;
                writer.print("  - {s}", .{name}) catch {};
                if (active) writer.print(" (ACTIVE)", .{}) catch {};
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
            var it = orch.activityNames();
            var count: usize = 0;
            while (it.next())
                |name|
            {
                if (orch.findActivity(name))
                    |activity|
                {
                    writer.print("  - {s}", .{name}) catch {};
                    if (activity.isActive())
                    {
                        writer.print(" (active", .{}) catch {};
                        if (activity.isUIVisible())
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
                    if (info.compatible)
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
        , .{}) catch {};
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
        self.csp_engine.processAll();

        // Service orchestrator (deferred activations + update)
        self.orchestrator.service(dt);

        // --- Main menu bar ---
        if (zgui.beginMainMenuBar())
        {
            self.drawStudioMenu();
            self.drawActivitiesMenu();
            self.orchestrator.runMainMenu();
            if (ENABLE_DOCKING) self.drawWindowMenu();
            zgui.endMainMenuBar();
        }

        // --- Workspace area ---
        if (ENABLE_DOCKING)
        {
            self.drawDockingWorkspace(dt);
        }
        else
        {
            self.drawTabBarWorkspace(dt);
        }

        // --- Floating windows ---
        if (self.show_plugin_manager)
        {
            self.drawPluginManagerWindow();
        }
    }

    // -----------------------------------------------------------------
    // Menu rendering
    // -----------------------------------------------------------------

    fn drawStudioMenu(
        self: *FundamentalApp,
    ) void
    {
        // Build the menu title from the current studio name
        const current_name = if (self.orchestrator.currentStudio())
            |cs|
            cs.name()
        else
            "Welcome";

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
        const menu_title: [:0]const u8 =
            title_buf[0 .. title_len + suffix.len :0];

        if (zgui.beginMenu(menu_title, true))
        {
            var names_it = self.orchestrator.studioNames();
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
                if (zgui.menuItem(name_z, .{
                    .selected = is_active,
                }))
                {
                    if (!is_active)
                    {
                        // Need sentinel-terminated for orchestrator
                        var act_buf: [256:0]u8 = undefined;
                        @memcpy(
                            act_buf[0..nlen],
                            name[0..nlen],
                        );
                        act_buf[nlen] = 0;
                        self.orchestrator.activateStudio(
                            @ptrCast(&act_buf),
                        );
                    }
                }
            }

            zgui.separator();
            if (zgui.menuItem(
                "Plugin Manager",
                .{ .selected = self.show_plugin_manager },
            ))
            {
                self.show_plugin_manager =
                    !self.show_plugin_manager;
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

    fn drawActivitiesMenu(
        self: *FundamentalApp,
    ) void
    {
        if (zgui.beginMenu("Activities##mmenu", true))
        {
            var names_it = self.orchestrator.activityNames();
            while (names_it.next())
                |name|
            {
                const activity = self.orchestrator.findActivity(
                    name,
                ) orelse continue;

                const is_active =
                    activity.isActive() and activity.isUIVisible();

                var name_buf: [256:0]u8 = undefined;
                const nlen = @min(name.len, name_buf.len - 1);
                @memcpy(name_buf[0..nlen], name[0..nlen]);
                name_buf[nlen] = 0;
                const name_z: [:0]const u8 = name_buf[0..nlen :0];

                if (zgui.menuItem(name_z, .{
                    .selected = is_active,
                }))
                {
                    var act_buf: [256:0]u8 = undefined;
                    @memcpy(act_buf[0..nlen], name[0..nlen]);
                    act_buf[nlen] = 0;
                    if (is_active)
                    {
                        self.orchestrator.deactivateActivity(
                            @ptrCast(&act_buf),
                        );
                    }
                    else
                    {
                        self.orchestrator.activateActivity(
                            @ptrCast(&act_buf),
                        );
                    }
                }
            }
            zgui.endMenu();
        }
    }

    fn drawWindowMenu(
        _: *FundamentalApp,
    ) void
    {
        if (!ENABLE_DOCKING) return;
        if (zgui.beginMenu("Window", true))
        {
            if (zgui.menuItem("Reset Layout", .{}))
            {
                zgui.dockBuilderRemoveNode(zgui.getID("DockSpace"));
            }
            zgui.endMenu();
        }
    }

    // -----------------------------------------------------------------
    // Floating windows
    // -----------------------------------------------------------------

    fn drawPluginManagerWindow(
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
                    .popen = &self.show_plugin_manager,
                },
            )
        )
        {
            plugin_manager.runUI(
                @ptrCast(&self.plugin_loader),
                null,
            );
        }
        zgui.end();
    }

    // -----------------------------------------------------------------
    // Workspace rendering — docking variant
    // -----------------------------------------------------------------

    fn drawDockingWorkspace(
        self: *FundamentalApp,
        dt: f32,
    ) void
    {
        if (!ENABLE_DOCKING) return;

        const viewport = zgui.getMainViewport();
        const vp_size = viewport.getSize();
        const vp_pos = viewport.getWorkPos();
        const vp_work_size = viewport.getWorkSize();

        // Set up the host window for the dockspace
        zgui.setNextWindowPos(vp_pos);
        zgui.setNextWindowSize(vp_work_size);
        zgui.setNextWindowViewport(viewport.getId());

        zgui.pushStyleVar(.{ .window_rounding = 0.0 });
        zgui.pushStyleVar(.{ .window_border_size = 0.0 });
        zgui.pushStyleVar(.{ .window_padding = .{ 0.0, 0.0 } });

        _ = zgui.begin("DockSpaceHost", .{
            .flags = .{
                .no_title_bar = true,
                .no_collapse = true,
                .no_background = true,
            },
        });
        zgui.popStyleVar(.{ .count = 3 });

        const dockspace_id = zgui.DockSpace(
            "DockSpace",
            .{ 0.0, 0.0 },
            .{ .passthru_central_node = true },
        );
        zgui.end();

        // Get the central node for viewport rendering
        const maybe_central_node =
            zgui.dockBuilderGetCentralNode(dockspace_id);

        var lab_vi = self.vi.toLab();
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

        // Run Activity UIs (they create their own dockable windows)
        self.orchestrator.runActivityUIs(&lab_vi);

        // Viewport interaction
        self.processViewportInteraction(&lab_vi);
    }

    // -----------------------------------------------------------------
    // Workspace rendering — tab bar variant (no docking)
    // -----------------------------------------------------------------

    fn drawTabBarWorkspace(
        self: *FundamentalApp,
        dt: f32,
    ) void
    {
        const viewport = zgui.getMainViewport();
        const vp_size = viewport.getSize();
        const work_pos = viewport.getWorkPos();
        const work_size = viewport.getWorkSize();

        // Fill the work area (below the main menu bar)
        zgui.setNextWindowPos(.{
            .x = work_pos[0],
            .y = work_pos[1],
        });
        zgui.setNextWindowSize(.{
            .w = work_size[0],
            .h = work_size[1],
        });

        _ = zgui.begin("##MainWindow", .{
            .flags = .{
                .no_title_bar = true,
                .no_resize = true,
                .no_move = true,
                .no_collapse = true,
            },
        });

        var lab_vi = self.vi.toLab();
        lab_vi.dt = dt;
        lab_vi.view.w = vp_size[0];
        lab_vi.view.h = vp_size[1];
        lab_vi.view.wx = work_pos[0];
        lab_vi.view.wy = work_pos[1];
        lab_vi.view.ww = work_size[0];
        lab_vi.view.wh = work_size[1];

        // Tab bar with active activities
        if (zgui.beginTabBar("Activities", .{}))
        {
            var it = self.orchestrator.activeUIActivities();
            while (it.next())
                |activity|
            {
                const act_name = activity.name();
                var name_buf: [256:0]u8 = undefined;
                const nlen = @min(act_name.len, name_buf.len - 1);
                @memcpy(name_buf[0..nlen], act_name[0..nlen]);
                name_buf[nlen] = 0;
                const name_z: [:0]const u8 =
                    name_buf[0..nlen :0];

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
        self.processViewportInteraction(&lab_vi);
    }

    // -----------------------------------------------------------------
    // Viewport interaction (hover/drag bidding)
    // -----------------------------------------------------------------

    fn processViewportInteraction(
        self: *FundamentalApp,
        lab_vi: *MeshulaLab.ViewInteraction,
    ) void
    {
        // Update mouse position in ViewInteraction
        const mouse_pos = zgui.getMousePos();
        lab_vi.x = mouse_pos[0] - lab_vi.view.wx;
        lab_vi.y = mouse_pos[1] - lab_vi.view.wy;

        const viewport_hovered = zgui.isWindowHovered(.{});
        const is_dragging = viewport_hovered and
            zgui.isMouseDown(.left);

        if (is_dragging)
        {
            lab_vi.start = !self.was_dragging;
            lab_vi.end = false;
            self.orchestrator.runViewportDragging(lab_vi);
        }
        else
        {
            if (self.was_dragging)
            {
                lab_vi.start = false;
                lab_vi.end = true;
                self.orchestrator.runViewportDragging(lab_vi);
            }
            else
            {
                self.orchestrator.runViewportHovering(lab_vi);
            }
        }
        self.was_dragging = is_dragging;

        // Update stored ViewInteraction for next frame
        self.vi = ViewInteraction.fromLab(lab_vi.*);
    }

    // -----------------------------------------------------------------
    // Event handling
    // -----------------------------------------------------------------

    fn handleEvent(
        self: *FundamentalApp,
        ev: [*c]const sapp.Event,
    ) void
    {
        _ = sokol.imgui.handleEvent(ev.*);

        switch (ev.*.type)
        {
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
                    while (i < n) : (i += 1)
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

    fn drawThunk() anyerror!void
    {
        const self = INSTANCE orelse return;
        try self.draw();
    }

    fn eventThunk(
        ev: [*c]const sapp.Event,
    ) callconv(.c) void
    {
        const self = INSTANCE orelse return;
        self.handleEvent(ev);
    }

    fn postZguiInitThunk() void
    {
        const self = INSTANCE orelse return;

        // Create and register Activities from discovered plugins.
        // This runs after zgui/sokol init, so Activate callbacks
        // can safely create GPU resources.
        if (!IS_WASM)
        {
            self.loadPluginActivities();
        }

        if (self.maybe_post_zgui_init)
            |init_fn|
        {
            init_fn();
        }
    }

    fn preZguiShutdownThunk() void
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
