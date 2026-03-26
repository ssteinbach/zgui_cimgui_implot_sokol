const MeshulaLab = @import("MeshulaLab");
const ziis = @import("zgui_cimgui_implot_sokol");
const zgui = ziis.zgui;

pub fn runUI(
    _: ?*anyopaque,
    _: ?*const MeshulaLab.ViewInteraction,
) callconv(.c) void
{
    zgui.separatorText("ListClipper Demo");

    zgui.textWrapped(
        \\ListClipper efficiently renders only the visible
        \\ rows in a large scrollable list. This example
        \\ has 10,000 items but only draws the ones on screen.
        ,
        .{},
    );

    zgui.spacing();

    const ITEM_COUNT = 10_000;

    if (
        zgui.beginChild(
            "ClippedList",
            .{
                .w = -1,
                .h = -1,
            },
        )
    )
    {
        defer zgui.endChild();

        var clipper = zgui.ListClipper.init();
        clipper.begin(ITEM_COUNT, null);

        while (clipper.step())
        {
            var row: i32 = clipper.DisplayStart;
            while (row < clipper.DisplayEnd)
                : (row += 1)
            {
                zgui.text(
                    "Item #{d}: value = {d:.3}",
                    .{
                        row,
                        @as(
                            f32,
                            @floatFromInt(row),
                        ) * 0.123,
                    },
                );
            }
        }

        clipper.end();
    }
}
