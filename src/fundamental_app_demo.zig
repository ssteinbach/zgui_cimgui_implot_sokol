//! Demo app using FundamentalApp
//!
//! Activities are discovered at runtime from plugin shared libraries.
//! This file defines the Studio layout (which activities appear) and
//! provides lifecycle hooks. The plugins themselves own the Activity
//! implementations and their state init/deinit via Activate/Deactivate.

const std = @import("std");
const builtin = @import("builtin");

const ziis = @import("zgui_cimgui_implot_sokol");
const MeshulaLab = @import("MeshulaLabZig");

const IS_WASM = builtin.target.cpu.arch.isWasm();

// =========================================================================
// Studio configuration — declares which activities belong in this studio.
// The actual Activity instances come from plugins at runtime.
// =========================================================================

const STUDIO_CONFIGS = [_]MeshulaLab.ActivityConfig{
    .{ .name = "UndoJournalDemoActivity" },
    .{ .name = "PlotDemoActivity" },
    .{ .name = "BigPlotDemoActivity" },
    .{ .name = "StairsPlotDemoActivity" },
    .{ .name = "PolygonPlotDemoActivity" },
    .{ .name = "InfLinesPieChartDemoActivity" },
    .{ .name = "TextureDemoActivity" },
    .{ .name = "CanvasDrawingDemoActivity" },
    .{ .name = "JSONPieChartDemoActivity" },
    .{ .name = "BigTextDemoActivity" },
    .{ .name = "ListClipperDemoActivity" },
    .{ .name = "SortableTableDemoActivity" },
};

var DEMO_STUDIO = MeshulaLab.Studio.init(
    "ZIIS Demo Studio",
    &STUDIO_CONFIGS,
);

// =========================================================================
// FundamentalApp instance
// =========================================================================

var APP: MeshulaLab.FundamentalApp = undefined;

// =========================================================================
// Lifecycle callbacks
// =========================================================================

/// Called after zgui/sokol are initialised and plugin activities have
/// been created+registered. Register the Studio and activate it.
fn postInit() void
{
    APP.registerStudio(&DEMO_STUDIO);
    APP.activateStudio("ZIIS Demo Studio");
}

// =========================================================================
// Entry point
// =========================================================================

pub fn main() !void
{
    APP = MeshulaLab.FundamentalApp.init(std.heap.c_allocator);

    APP.run(
        .{
            .title = "ZIIS FundamentalApp Demo",
            .logger = ziis.std_log_scoped,
            .maybe_post_zgui_init = &postInit,
        },
    );
}
