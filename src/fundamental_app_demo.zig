//! Demo app using FundamentalApp
//!
//! Hosts the same demo activities as app_wrapper_demo.zig but uses
//! the FundamentalApp framework which provides menus, tab bar /
//! dockspace workspace, and orchestrator lifecycle management.

const std = @import("std");
const builtin = @import("builtin");

const ziis = @import("zgui_cimgui_implot_sokol");
const MeshulaLab = @import("MeshulaLabZig");
const activities = @import("demo_activities/root.zig");

const IS_WASM = builtin.target.cpu.arch.isWasm();

// =========================================================================
// Allocator
// =========================================================================

var debug_allocator = (
    if (IS_WASM) null
    else std.heap.DebugAllocator(.{}){}
);
const allocator = (
    if (IS_WASM) std.heap.c_allocator
    else debug_allocator.allocator()
);

// =========================================================================
// Activities
// =========================================================================

const ACTIVITY_NAMES = struct
{
    const UNDO_JOURNAL = "UndoJournalDemoActivity";
    const PLOT = "PlotDemoActivity";
    const BIG_PLOT = "BigPlotDemoActivity";
    const STAIRS_PLOT = "StairsPlotDemoActivity";
    const POLYGON_PLOT = "PolygonPlotDemoActivity";
    const INFLINES_PIE = "InfLinesPieChartDemoActivity";
    const TEXTURE = "TextureDemoActivity";
    const CANVAS = "CanvasDrawingDemoActivity";
    const JSON_PIE = "JSONPieChartDemoActivity";
    const BIG_TEXT = "BigTextDemoActivity";
    const LIST_CLIPPER = "ListClipperDemoActivity";
    const SORTABLE_TABLE = "SortableTableDemoActivity";
};

var ACTIVITIES = struct
{
    undo_journal: MeshulaLab.Activity = MeshulaLab.Activity.init(
        ACTIVITY_NAMES.UNDO_JOURNAL,
        .{ .run_ui = &activities.undo_journal.runUI },
    ),
    plot: MeshulaLab.Activity = MeshulaLab.Activity.init(
        ACTIVITY_NAMES.PLOT,
        .{ .run_ui = &activities.plot.runUI },
    ),
    big_plot: MeshulaLab.Activity = MeshulaLab.Activity.init(
        ACTIVITY_NAMES.BIG_PLOT,
        .{ .run_ui = &activities.big_plot.runUI },
    ),
    stairs_plot: MeshulaLab.Activity = MeshulaLab.Activity.init(
        ACTIVITY_NAMES.STAIRS_PLOT,
        .{ .run_ui = &activities.stairs_plot.runUI },
    ),
    polygon_plot: MeshulaLab.Activity = MeshulaLab.Activity.init(
        ACTIVITY_NAMES.POLYGON_PLOT,
        .{ .run_ui = &activities.polygon_plot.runUI },
    ),
    inflines_pie: MeshulaLab.Activity = MeshulaLab.Activity.init(
        ACTIVITY_NAMES.INFLINES_PIE,
        .{ .run_ui = &activities.inflines_pie.runUI },
    ),
    texture: MeshulaLab.Activity = MeshulaLab.Activity.init(
        ACTIVITY_NAMES.TEXTURE,
        .{
            .run_ui = &activities.texture.runUI,
            .update = &activities.texture.update,
        },
    ),
    canvas: MeshulaLab.Activity = MeshulaLab.Activity.init(
        ACTIVITY_NAMES.CANVAS,
        .{ .run_ui = &activities.canvas.runUI },
    ),
    json_pie: MeshulaLab.Activity = MeshulaLab.Activity.init(
        ACTIVITY_NAMES.JSON_PIE,
        .{ .run_ui = &activities.json_pie.runUI },
    ),
    big_text: MeshulaLab.Activity = MeshulaLab.Activity.init(
        ACTIVITY_NAMES.BIG_TEXT,
        .{ .run_ui = &activities.big_text.runUI },
    ),
    list_clipper: MeshulaLab.Activity = MeshulaLab.Activity.init(
        ACTIVITY_NAMES.LIST_CLIPPER,
        .{ .run_ui = &activities.list_clipper.runUI },
    ),
    sortable_table: MeshulaLab.Activity = MeshulaLab.Activity.init(
        ACTIVITY_NAMES.SORTABLE_TABLE,
        .{ .run_ui = &activities.sortable_table.runUI },
    ),
}{};

const STUDIO_CONFIGS = [_]MeshulaLab.ActivityConfig{
    .{ .name = ACTIVITY_NAMES.UNDO_JOURNAL },
    .{ .name = ACTIVITY_NAMES.PLOT },
    .{ .name = ACTIVITY_NAMES.BIG_PLOT },
    .{ .name = ACTIVITY_NAMES.STAIRS_PLOT },
    .{ .name = ACTIVITY_NAMES.POLYGON_PLOT },
    .{ .name = ACTIVITY_NAMES.INFLINES_PIE },
    .{ .name = ACTIVITY_NAMES.TEXTURE },
    .{ .name = ACTIVITY_NAMES.CANVAS },
    .{ .name = ACTIVITY_NAMES.JSON_PIE },
    .{ .name = ACTIVITY_NAMES.BIG_TEXT },
    .{ .name = ACTIVITY_NAMES.LIST_CLIPPER },
    .{ .name = ACTIVITY_NAMES.SORTABLE_TABLE },
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

/// Called after zgui/sokol are initialised — safe to create GPU
/// resources and register activities.
fn postInit() void
{
    // Initialise activity-local state (GPU resources need sokol up)
    activities.big_plot.initState(allocator);
    activities.texture.initState();
    activities.json_pie.initState(allocator);
    activities.big_text.initState(allocator);

    // Register activities with the FundamentalApp's orchestrator
    APP.registerActivity(&ACTIVITIES.undo_journal);
    APP.registerActivity(&ACTIVITIES.plot);
    APP.registerActivity(&ACTIVITIES.big_plot);
    APP.registerActivity(&ACTIVITIES.stairs_plot);
    APP.registerActivity(&ACTIVITIES.polygon_plot);
    APP.registerActivity(&ACTIVITIES.inflines_pie);
    APP.registerActivity(&ACTIVITIES.texture);
    APP.registerActivity(&ACTIVITIES.canvas);
    APP.registerActivity(&ACTIVITIES.json_pie);
    APP.registerActivity(&ACTIVITIES.big_text);
    APP.registerActivity(&ACTIVITIES.list_clipper);
    APP.registerActivity(&ACTIVITIES.sortable_table);

    APP.registerStudio(&DEMO_STUDIO);
    APP.activateStudio("ZIIS Demo Studio");
}

/// Called before zgui/sokol shut down — free activity state.
/// Note: debug_allocator must NOT be deinited here because
/// FundamentalApp.deinit() (orchestrator, csp, plugins) runs
/// after this callback and still needs the allocator.
fn preCleanup() void
{
    activities.json_pie.deinitState(allocator);
    activities.big_text.deinitState(allocator);
    activities.big_plot.deinitState(allocator);
    activities.undo_journal.deinitState();
}

// =========================================================================
// Entry point
// =========================================================================

pub fn main() !void
{
    activities.undo_journal.initState(allocator, 5);

    APP = MeshulaLab.FundamentalApp.init(allocator);

    APP.run(
        .{
            .title = "ZIIS FundamentalApp Demo",
            .logger = ziis.std_log_scoped,
            .maybe_post_zgui_init = &postInit,
            .maybe_pre_zgui_shutdown_cleanup = &preCleanup,
        },
    );

    // Debug allocator check runs after FundamentalApp has fully
    // torn down (orchestrator, csp, plugins all deinited).
    if (!IS_WASM)
    {
        const result = debug_allocator.deinit();
        if (result == .leak)
        {
            std.log.debug("leak!", .{});
        }
    }
}
