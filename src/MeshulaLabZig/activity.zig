//! Zig-ergonomic wrapper for LabActivity
//!
//! Provides a Zig-friendly interface for creating Activities that
//! conform to the MeshulaLab Studio-Activity-Provider pattern.
//! Each Activity has a name and a set of optional callbacks.

const std = @import("std");
const MeshulaLab = @import("MeshulaLab");

/// A Zig-friendly Activity that wraps a LabActivity C struct.
///
/// Create one with `init()`, passing the name and callbacks.
/// Register it with an Orchestrator to participate in the
/// Studio lifecycle.
pub const Activity = struct
{
    lab: MeshulaLab.Activity,

    /// Callback signatures for Activity lifecycle and rendering.
    /// All callbacks are optional — null callbacks are simply not invoked.
    pub const Callbacks = struct
    {
        /// Draw UI content for this Activity.
        run_ui: ?RunUIFn = null,

        /// Called each frame with delta time.
        update: ?UpdateFn = null,

        /// Called when the Activity is activated.
        activate: ?LifecycleFn = null,

        /// Called when the Activity is deactivated.
        deactivate: ?LifecycleFn = null,

        /// Draw menu bar contributions.
        menu: ?LifecycleFn = null,

        /// Render 3D/viewport content.
        render: ?RunUIFn = null,

        /// Return a bid for viewport hover handling (-1 = no interest).
        viewport_hover_bid: ?ViewportBidFn = null,

        /// Called when this Activity wins the hover bid.
        viewport_hovering: ?RunUIFn = null,

        /// Return a bid for viewport drag handling (-1 = no interest).
        viewport_drag_bid: ?ViewportBidFn = null,

        /// Called when this Activity wins the drag bid.
        viewport_dragging: ?RunUIFn = null,
    };

    pub const RunUIFn = *const fn (
        ?*anyopaque,
        ?*const MeshulaLab.ViewInteraction,
    ) callconv(.c) void;

    pub const UpdateFn = *const fn (
        ?*anyopaque,
        f32,
    ) callconv(.c) void;

    pub const LifecycleFn = *const fn (
        ?*anyopaque,
    ) callconv(.c) void;

    pub const ViewportBidFn = *const fn (
        ?*anyopaque,
        ?*const MeshulaLab.ViewInteraction,
    ) callconv(.c) c_int;

    /// Create a new Activity with the given name and callbacks.
    /// The name must be a compile-time or static string literal
    /// (its pointer is stored, not copied).
    pub fn init(
        activity_name: [*:0]const u8,
        callbacks: Callbacks,
    ) Activity
    {
        var a: MeshulaLab.Activity = std.mem.zeroes(MeshulaLab.Activity);
        a.name = activity_name;
        a.active = false;
        a.uiVisible = false;

        a.RunUI = callbacks.run_ui;
        a.Update = callbacks.update;
        a.Activate = callbacks.activate;
        a.Deactivate = callbacks.deactivate;
        a.Menu = callbacks.menu;
        a.Render = callbacks.render;
        a.ViewportHoverBid = callbacks.viewport_hover_bid;
        a.ViewportHovering = callbacks.viewport_hovering;
        a.ViewportDragBid = callbacks.viewport_drag_bid;
        a.ViewportDragging = callbacks.viewport_dragging;

        return .{ .lab = a };
    }

    /// Check if the Activity is currently active.
    pub fn isActive(
        self: *const Activity,
    ) bool
    {
        return self.lab.active;
    }

    /// Check if the Activity's UI is currently visible.
    pub fn isUIVisible(
        self: *const Activity,
    ) bool
    {
        return self.lab.uiVisible;
    }

    /// Get the Activity name as a Zig slice.
    pub fn name(
        self: *const Activity,
    ) []const u8
    {
        return std.mem.span(self.lab.name);
    }
};
