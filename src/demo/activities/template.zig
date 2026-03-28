//! Template Activity — starting point for new activities.
//!
//! Copy this file and its corresponding plugin wrapper to create
//! a new activity. Replace "Template" with your activity name.

const MeshulaLab = @import("MeshulaLab");
const ziis = @import("zgui_cimgui_implot_sokol");
const zgui = ziis.zgui;

pub fn runUI(
    _: ?*anyopaque,
    _: ?*const MeshulaLab.ViewInteraction,
) callconv(.c) void
{
    zgui.textUnformatted("Hello from TemplateActivity!");
}
