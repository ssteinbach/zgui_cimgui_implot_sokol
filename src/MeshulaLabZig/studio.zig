//! Zig-ergonomic wrapper for LabStudio
//!
//! A Studio defines a workspace configuration: which Activities
//! should be active and whether their UI is initially visible.

const std = @import("std");
const MeshulaLab = @import("MeshulaLab");

/// Configuration for one Activity within a Studio.
pub const ActivityConfig = struct {
    name: [*:0]const u8,
    ui_initially_visible: bool = true,
    panel_id: ?[*:0]const u8 = null,
    window_name: ?[*:0]const u8 = null,
};

/// A Zig-friendly Studio that wraps a LabStudio C struct.
///
/// Create one with `init()`, passing the name and a static
/// slice of ActivityConfig entries. Register it with an
/// Orchestrator to make it available for activation.
pub const Studio = struct {
    lab: MeshulaLab.Studio,
    configs: []const ActivityConfig,

    /// For plugin-created studios: the original pointer returned
    /// by the plugin's CreateStudio, which must be passed back to
    /// DestroyStudio. Null for built-in studios.
    maybe_plugin_studio: ?*MeshulaLab.Studio = null,

    /// Optional LabLayout spec string for spatial arrangement.
    /// null means use default ImGui layout (no LabLayout).
    layout_spec: ?[*:0]const u8 = null,

    /// Create a new Studio with the given name and Activity configuration.
    /// Both `name` and `configs` must have static lifetime (pointers are
    /// stored, not copied).
    pub fn init(
        comptime studio_name: [*:0]const u8,
        configs: []const ActivityConfig,
    ) Studio
    {
        return initWithLayout(studio_name, configs, null);
    }

    /// Create a new Studio with a LabLayout spec and Activity configuration.
    /// All arguments must have static lifetime.
    pub fn initWithLayout(
        comptime studio_name: [*:0]const u8,
        configs: []const ActivityConfig,
        layout_spec: ?[*:0]const u8,
    ) Studio
    {
        var s: MeshulaLab.Studio = std.mem.zeroes(MeshulaLab.Studio);
        s.name = studio_name;
        s.active = false;

        // Wire up the C function pointers to query our config slice.
        s.GetActivityCount = &getActivityCount;
        s.GetActivityConfig = &getActivityConfig;
        s.MustDeactivateUnrelatedActivities = &mustDeactivate;
        s.GetLayoutSpec = &getLayoutSpec;

        return .{
            .lab = s,
            .configs = configs,
            .layout_spec = layout_spec,
        };
    }

    /// Check if the Studio is currently active.
    pub fn is_active(
        self: *const Studio,
    ) bool
    {
        return self.lab.active;
    }

    /// Get the Studio name as a Zig slice.
    pub fn name(
        self: *const Studio,
    ) []const u8
    {
        return std.mem.span(self.lab.name);
    }

    // ---------------------------------------------------------------
    // C-ABI callbacks for LabStudio function pointers.
    //
    // The LabStudio.instance pointer is set to the Studio struct by
    // the Orchestrator when it registers the Studio. However, since
    // our Zig orchestrator manages Studios directly, these callbacks
    // receive the instance pointer that was set during registration.
    // We use @fieldParentPtr on the lab field to recover the Zig Studio.
    // ---------------------------------------------------------------

    fn getActivityCount(
        instance: ?*anyopaque,
    ) callconv(.c) c_int
    {
        const studio = studio_from_instance(instance) orelse return 0;
        return @intCast(studio.configs.len);
    }

    fn getActivityConfig(
        instance: ?*anyopaque,
        index: c_int,
    ) callconv(.c) ?*const MeshulaLab.ActivityConfig
    {
        const studio = studio_from_instance(instance) orelse return null;
        const i: usize = @intCast(index);
        if (i >= studio.configs.len)
        {
            return null;
        }

        // Return a pointer to a static LabActivityConfig.
        // This is safe because the configs slice has static lifetime.
        const cfg = &studio.configs[i];
        const S = struct {
            var c_cfg: MeshulaLab.ActivityConfig = undefined;
        };
        S.c_cfg.name = cfg.name;
        S.c_cfg.uiInitiallyVisible = cfg.ui_initially_visible;
        S.c_cfg.panelId = if (cfg.panel_id) |p| p else null;
        S.c_cfg.windowName = if (cfg.window_name) |w| w else null;
        return &S.c_cfg;
    }

    fn mustDeactivate(
        _: ?*anyopaque,
    ) callconv(.c) bool
    {
        return true;
    }

    fn getLayoutSpec(
        instance: ?*anyopaque,
    ) callconv(.c) ?[*:0]const u8
    {
        const studio = studio_from_instance(instance) orelse return null;
        return studio.layout_spec;
    }

    fn studio_from_instance(
        instance: ?*anyopaque,
    ) ?*const Studio
    {
        const lab_ptr: *MeshulaLab.Studio = @ptrCast(
            @alignCast(instance orelse return null),
        );
        return @fieldParentPtr("lab", lab_ptr);
    }
};
