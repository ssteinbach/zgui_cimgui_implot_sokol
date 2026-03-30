//! Layout Demo Activity
//!
//! Shows the current studio's LabLayout spec and panel assignments,
//! demonstrating that layout data flows through the C API.

const std = @import("std");
const MeshulaLab = @import("MeshulaLab");
const MeshulaLabZig = @import("MeshulaLabZig");
const ziis = @import("zgui_cimgui_implot_sokol");
const zgui = ziis.zgui;

var maybe_orchestrator: ?*MeshulaLabZig.Orchestrator = null;

pub fn setOrchestrator(
    orch: *MeshulaLabZig.Orchestrator,
) void
{
    maybe_orchestrator = orch;
}

pub fn runUI(
    _: ?*anyopaque,
    _: ?*const MeshulaLab.ViewInteraction,
) callconv(.c) void
{
    zgui.textUnformatted("LabLayout Data Plumbing Demo");
    zgui.separator();

    const orch = maybe_orchestrator orelse
    {
        zgui.textUnformatted("No orchestrator set.");
        return;
    };

    // Show current studio info
    if (orch.maybe_current_studio)
        |studio|
    {
        zgui.text(
            "Active Studio: {s}",
            .{std.mem.span(studio.lab.name)},
        );

        // Show layout spec
        zgui.spacing();
        zgui.textUnformatted("Layout Spec:");
        if (studio.layout_spec)
            |spec|
        {
            zgui.indent(.{});
            zgui.textWrapped(
                "{s}",
                .{std.mem.span(spec)},
            );
            zgui.unindent(.{});
        }
        else
        {
            zgui.indent(.{});
            zgui.textDisabled("{s}", .{"(none — using default ImGui layout)"});
            zgui.unindent(.{});
        }

        // Show activity panel assignments
        zgui.spacing();
        zgui.textUnformatted("Activity Panel Assignments:");

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
            zgui.tableSetupColumn("Panel ID", .{});
            zgui.tableSetupColumn("Window Name", .{});
            zgui.tableHeadersRow();

            for (studio.configs)
                |cfg|
            {
                zgui.tableNextRow(.{});

                _ = zgui.tableNextColumn();
                zgui.text(
                    "{s}",
                    .{std.mem.span(cfg.name)},
                );

                _ = zgui.tableNextColumn();
                if (cfg.panel_id)
                    |pid|
                {
                    zgui.text("{s}", .{std.mem.span(pid)});
                }
                else
                {
                    zgui.textDisabled("{s}", .{"(none)"});
                }

                _ = zgui.tableNextColumn();
                if (cfg.window_name)
                    |wn|
                {
                    zgui.text("{s}", .{std.mem.span(wn)});
                }
                else
                {
                    zgui.textDisabled("{s}", .{"(none)"});
                }
            }
        }
    }
    else
    {
        zgui.textUnformatted("No studio active.");
    }
}
