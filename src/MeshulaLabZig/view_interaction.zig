//! Zig-native view interaction types
//!
//! Mirrors the C LabViewDimensions and LabViewInteraction structs
//! with a more ergonomic Zig interface, and provides conversion
//! to the C types for passing into Activity callbacks.

const MeshulaLab = @import("MeshulaLab");

/// Dimensions of the viewport within the main window.
pub const ViewDimensions = struct
{
    /// Full view width and height.
    w: f32 = 0,
    h: f32 = 0,

    /// Viewport position and size within the view.
    wx: f32 = 0,
    wy: f32 = 0,
    ww: f32 = 0,
    wh: f32 = 0,

    pub fn toLab(
        self: ViewDimensions,
    ) MeshulaLab.ViewDimensions
    {
        return .{
            .w = self.w,
            .h = self.h,
            .wx = self.wx,
            .wy = self.wy,
            .ww = self.ww,
            .wh = self.wh,
        };
    }

    pub fn fromLab(
        lab: MeshulaLab.ViewDimensions,
    ) ViewDimensions
    {
        return .{
            .w = lab.w,
            .h = lab.h,
            .wx = lab.wx,
            .wy = lab.wy,
            .ww = lab.ww,
            .wh = lab.wh,
        };
    }
};

/// Per-frame interaction state for viewport rendering and input.
pub const ViewInteraction = struct
{
    view: ViewDimensions = .{},

    /// Mouse position relative to the viewport.
    x: f32 = 0,
    y: f32 = 0,

    /// Delta time since last frame (seconds).
    dt: f32 = 0,

    /// Drag state: true at the start/end of a drag gesture.
    start: bool = false,
    end: bool = false,

    pub fn toLab(
        self: ViewInteraction,
    ) MeshulaLab.ViewInteraction
    {
        return .{
            .view = self.view.toLab(),
            .x = self.x,
            .y = self.y,
            .dt = self.dt,
            .start = self.start,
            .end = self.end,
        };
    }

    pub fn fromLab(
        lab: MeshulaLab.ViewInteraction,
    ) ViewInteraction
    {
        return .{
            .view = ViewDimensions.fromLab(lab.view),
            .x = lab.x,
            .y = lab.y,
            .dt = lab.dt,
            .start = lab.start,
            .end = lab.end,
        };
    }
};
