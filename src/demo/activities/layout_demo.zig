//! Layout Demo Activity
//!
//! Demonstrates the LabLayout panel system. When this activity runs
//! inside the LayoutDemoStudio, the studio's LAYOUT_SPEC arranges
//! windows into named panels. The activity displays the expected
//! layout structure so the user can verify it matches what they see.

const MeshulaLab = @import("MeshulaLab");
const ziis = @import("zgui_cimgui_implot_sokol");
const zgui = ziis.zgui;

pub fn runUI(
    _: ?*anyopaque,
    _: ?*const MeshulaLab.ViewInteraction,
) callconv(.c) void
{
    zgui.textUnformatted("LabLayout Panel Demo");
    zgui.separator();
    zgui.spacing();

    zgui.textUnformatted("Expected Layout Structure:");
    zgui.spacing();

    zgui.indent(.{});
    zgui.textWrapped("{s}", .{LAYOUT_DESCRIPTION});
    zgui.unindent(.{});

    zgui.spacing();
    zgui.separator();
    zgui.spacing();

    zgui.textUnformatted("Panel Assignments:");
    zgui.spacing();

    if (
        zgui.beginTable(
            "##panels",
            .{
                .column = 3,
                .flags = .{
                    .row_bg = true,
                    .borders = .{
                        .inner_h = true,
                        .inner_v = true,
                        .outer_h = true,
                        .outer_v = true,
                    },
                },
            },
        )
    )
    {
        defer zgui.endTable();
        zgui.tableSetupColumn("Activity", .{});
        zgui.tableSetupColumn("Panel", .{});
        zgui.tableSetupColumn("Window", .{});
        zgui.tableHeadersRow();

        for (PANEL_ENTRIES)
            |entry|
        {
            zgui.tableNextRow(.{});

            _ = zgui.tableNextColumn();
            zgui.textUnformatted(entry.activity);

            _ = zgui.tableNextColumn();
            zgui.textUnformatted(entry.panel);

            _ = zgui.tableNextColumn();
            zgui.textUnformatted(entry.window);
        }
    }

    zgui.spacing();
    zgui.textDisabled(
        "{s}",
        .{"Activate the LayoutDemoStudio to see this layout applied."},
    );
}

const PanelEntry = struct {
    activity: []const u8,
    panel: []const u8,
    window: []const u8,
};

const PANEL_ENTRIES = [_]PanelEntry{
    .{
        .activity = "LayoutDemoActivity",
        .panel = "main-panel",
        .window = "Layout Inspector",
    },
    .{
        .activity = "PlotDemoActivity",
        .panel = "sidebar-panel",
        .window = "Plot",
    },
    .{
        .activity = "FileDialogActivity",
        .panel = "bottom-panel",
        .window = "File Dialog",
    },
};

const LAYOUT_DESCRIPTION =
    \\root (horizontal)
    \\  main-panel (grow, grow)
    \\  right-area (vertical, fixed 400px)
    \\    sidebar-panel (grow, grow)
    \\    bottom-panel (grow, fixed 200px)
;
