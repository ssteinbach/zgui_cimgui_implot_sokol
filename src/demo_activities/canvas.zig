const MeshulaLab = @import("MeshulaLab");
const ziis = @import("zgui_cimgui_implot_sokol");
const zgui = ziis.zgui;

pub fn runUI(
    _: ?*anyopaque,
    _: ?*const MeshulaLab.ViewInteraction,
) callconv(.c) void
{
    if (
        zgui.beginChild(
            "GraphView",
            .{
                .h = -1,
                .w = -1,
                .child_flags = .{},
                .window_flags = .{
                    .menu_bar = false,
                }
            },
        )
    )
    {
        defer zgui.endChild();

        zgui.beginGroup();

        zgui.textUnformatted("hi");

        const dl = zgui.getWindowDrawList();

        dl.addQuad(
            .{
                .p1 = .{ 170, 420 },
                .p2 = .{ 270, 420 },
                .p3 = .{ 220, 520 },
                .p4 = .{ 120, 520 },
                .col = 0xff_00_00_ff,
                .thickness = 3.0,
            }
        );
        dl.addText(
            .{ 130, 130 },
            0xff_00_00_ff,
            "The number is: {}",
            .{7}
        );
        dl.addCircleFilled(
            .{
                .p = .{ 200, 600 },
                .r = 50,
                .col = 0xff_ff_ff_ff
            },
        );
        dl.addCircle(
            .{
                .p = .{ 200, 600 },
                .r = 30,
                .col = 0xff_00_00_ff,
                .thickness = 11,
            }
        );
        dl.addPolyline(
            &.{
                .{ 100, 700 },
                .{ 200, 600 },
                .{ 300, 700 },
                .{ 400, 600 },
            },
            .{
                .col = 0xff_00_aa_11,
                .thickness = 7,
            },
        );


        const c1 = zgui.colorConvertFloat4ToU32(
            .{0.8, 0.2, 0.2, 0.4},
        );
        const c2 = zgui.colorConvertFloat4ToU32(
            .{0.2, 0.8, 0.2, 0.4},
        );
        const c3 = zgui.colorConvertFloat4ToU32(
            .{0.2, 0.2, 0.8, 0.4},
        );
        const c4 = zgui.colorConvertFloat4ToU32(
            .{0.8, 0.8, 0.8, 0.9},
        );

        dl.addRect(
            .{
                // .col = 0xff_bb_bb_ff,
                .col = c4,
                .pmin = .{ 200, 200 },
                .pmax = .{ 300, 300 },
                .rounding = 0.4,
            },
        );

        dl.addCircleFilled(
            .{
                .col = c1,
                .p = .{ 100, 100 },
                .r = 60,
            },
        );
        dl.addCircleFilled(
            .{
                .col = c2,
                .p = .{ 300, 312 },
                .r = 30,
            },
        );
        dl.addCircleFilled(
            .{
                .col = c3,
                .p = .{ 120, 120 },
                .r = 60,
            },
        );

        zgui.endGroup();
    }
}
