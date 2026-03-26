const demo = @import("../app_wrapper_demo.zig");
const MeshulaLab = @import("MeshulaLab");
const ziis = @import("zgui_cimgui_implot_sokol");
const zgui = ziis.zgui;

pub fn runUI(
    _: ?*anyopaque,
    _: ?*const MeshulaLab.ViewInteraction,
) callconv(.c) void
{
    const wsize = zgui.getWindowSize();

    ziis.cimgui.igImage(
        .{ ._TexID = demo.STATE.texid },
        .{ .x = wsize[0], .y = wsize[1]},
    );
}
