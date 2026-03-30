//! example app using the app wrapper

const std = @import("std");
const builtin = @import("builtin");

const ziis = @import("zgui_cimgui_implot_sokol");
const zgui = ziis.zgui;
const zplot = zgui.plot;
const sg = ziis.sokol.gfx;
const app_wrapper = ziis.app_wrapper;

const cimgui = ziis.cimgui;
const MeshulaLab = @import("MeshulaLabZig");
const activities = @import("demo/activities/root.zig");

/// State container — only fields that are not owned by individual
/// activities remain here.
pub const STATE = struct {
    // Web Worker demo state (WASM only)
    pub var worker_pool_initialized: bool = false;
    pub var maybe_worker_pool: ?ziis.worker_pool.WorkerPool = null;
    pub var worker_counter: std.atomic.Value(u32) = std.atomic.Value(u32).init(0);
    pub var worker_jobs_submitted: u32 = 0;
    pub var worker_jobs_completed: u32 = 0;
};

const IS_WASM = builtin.target.cpu.arch.isWasm();

// Emscripten extern function for fetching data via JavaScript
extern fn emscripten_run_script_string(script: [*:0]const u8) ?[*:0]const u8;

// =========================================================================
// Activities — each former tab is now a MeshulaLab Activity
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
    const FILE_DIALOG = "FileDialogDemoActivity";
    const LAYOUT_DEMO = "LayoutDemoActivity";
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
    file_dialog: MeshulaLab.Activity = MeshulaLab.Activity.init(
        ACTIVITY_NAMES.FILE_DIALOG,
        .{ .run_ui = &activities.file_dialog.runUI },
    ),
    layout_demo: MeshulaLab.Activity = MeshulaLab.Activity.init(
        ACTIVITY_NAMES.LAYOUT_DEMO,
        .{ .run_ui = &activities.layout_demo.runUI },
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
    .{ .name = ACTIVITY_NAMES.FILE_DIALOG },
    .{ .name = ACTIVITY_NAMES.LAYOUT_DEMO },
};

var DEMO_STUDIO = MeshulaLab.Studio.init(
    "ZIIS Demo Studio",
    &STUDIO_CONFIGS,
);

// A second studio that demonstrates LabLayout data plumbing.
// Panel assignments map activities to named layout regions.
const LAYOUT_STUDIO_CONFIGS = [_]MeshulaLab.ActivityConfig{
    .{
        .name = ACTIVITY_NAMES.LAYOUT_DEMO,
        .panel_id = "main-panel",
        .window_name = "Layout Inspector",
    },
    .{
        .name = ACTIVITY_NAMES.PLOT,
        .panel_id = "sidebar-panel",
        .window_name = "Plot",
    },
    .{
        .name = ACTIVITY_NAMES.FILE_DIALOG,
        .panel_id = "bottom-panel",
        .window_name = "File Dialog",
    },
};

const LAYOUT_SPEC =
    \\panel root
    \\  direction: horizontal
    \\  sizing: grow grow
    \\
    \\  panel main-panel
    \\    sizing: grow grow
    \\
    \\  panel right-area
    \\    direction: vertical
    \\    sizing: fixed(400) grow
    \\
    \\    panel sidebar-panel
    \\      sizing: grow grow
    \\
    \\    panel bottom-panel
    \\      sizing: grow fixed(200)
;

var LAYOUT_STUDIO = MeshulaLab.Studio.initWithLayout(
    "Layout Demo Studio",
    &LAYOUT_STUDIO_CONFIGS,
    LAYOUT_SPEC,
);

var ORCHESTRATOR: MeshulaLab.Orchestrator = undefined;

/// the GPA - useful for detecting leaks, but ONLY works in non EMCC builds
var debug_allocator = (
    if (IS_WASM) null
    else std.heap.DebugAllocator(.{}){}
);
pub const allocator = (
    // @TODO: try the smp_allocator
    if (IS_WASM) std.heap.c_allocator
    else debug_allocator.allocator()
);

// =========================================================================
// draw — orchestrator-driven frame
// =========================================================================

/// draw the UI
fn draw() !void
{
    const vp = zgui.getMainViewport();
    const size = vp.getSize();

    // Service the orchestrator (handles deferred activations, updates)
    ORCHESTRATOR.service(0.0);

    zgui.setNextWindowPos(.{ .x = 0, .y = 0 });
    zgui.setNextWindowSize(
        .{
            .w = size[0],
            .h = size[1],
        },
    );

    if (
        zgui.begin(
            "###FULLSCREEN",
            .{
                .flags = .{
                    .no_resize = true,
                    .no_scroll_with_mouse = true,
                    .always_auto_resize = true,
                    .no_move = true,
                    .no_collapse = true,
                    .no_title_bar = true,
                    .no_bring_to_front_on_focus = true,
                },
            },
        )
    )
    {
        defer zgui.end();

        // Studio status bar
        if (ORCHESTRATOR.maybe_current_studio)
            |studio|
        {
            zgui.text(
                "{s}  —  {d} Activities Loaded",
                .{
                    std.mem.span(studio.lab.name),
                    ORCHESTRATOR.activities.count(),
                },
            );
        }
        else
        {
            zgui.text(
                "No Studio Active  —  {d} Activities Loaded",
                .{ORCHESTRATOR.activities.count()},
            );
        }

        zgui.separator();

        if (zgui.beginTabBar("Panes", .{}))
        {
            defer zgui.endTabBar();

            // Iterate active, UI-visible Activities and render each
            // as a tab
            var it = ORCHESTRATOR.active_ui_activities();
            while (it.next())
                |activity|
            {
                if (
                    zgui.beginTabItem(
                        std.mem.span(activity.lab.name),
                        .{},
                    )
                )
                {
                    defer zgui.endTabItem();

                    if (activity.lab.RunUI)
                        |run_ui|
                    {
                        run_ui(activity.lab.instance, null);
                    }
                }
            }
        }
    }
}

fn cleanup() void
{
    activities.json_pie.deinitState(allocator);
    activities.big_text.deinitState(allocator);
    activities.big_plot.deinitState(allocator);
    activities.undo_journal.deinitState();

    // Clean up worker pool resources
    // NOTE: Disabled due to EM_JS linking issues
    _ = STATE.worker_pool_initialized; // Suppress unused warning

    ORCHESTRATOR.deinit();

    if (IS_WASM == false)
    {
        const result = debug_allocator.deinit();
        if (result == .leak)
        {
            std.log.debug("leak!", .{});
        }
    }
}

pub fn init() void
{
    // Initialize activity-local state
    activities.big_plot.initState(allocator);
    activities.texture.initState();
    activities.json_pie.initState(allocator);
    activities.big_text.initState(allocator);

    // Initialize orchestrator and register Activities + Studio
    ORCHESTRATOR = MeshulaLab.Orchestrator.init(allocator);

    ORCHESTRATOR.register_activity(&ACTIVITIES.undo_journal);
    ORCHESTRATOR.register_activity(&ACTIVITIES.plot);
    ORCHESTRATOR.register_activity(&ACTIVITIES.big_plot);
    ORCHESTRATOR.register_activity(&ACTIVITIES.stairs_plot);
    ORCHESTRATOR.register_activity(&ACTIVITIES.polygon_plot);
    ORCHESTRATOR.register_activity(&ACTIVITIES.inflines_pie);
    ORCHESTRATOR.register_activity(&ACTIVITIES.texture);
    ORCHESTRATOR.register_activity(&ACTIVITIES.canvas);
    ORCHESTRATOR.register_activity(&ACTIVITIES.json_pie);
    ORCHESTRATOR.register_activity(&ACTIVITIES.big_text);
    ORCHESTRATOR.register_activity(&ACTIVITIES.list_clipper);
    ORCHESTRATOR.register_activity(&ACTIVITIES.sortable_table);
    ORCHESTRATOR.register_activity(&ACTIVITIES.file_dialog);
    ORCHESTRATOR.register_activity(&ACTIVITIES.layout_demo);

    ORCHESTRATOR.register_studio(&DEMO_STUDIO);
    ORCHESTRATOR.register_studio(&LAYOUT_STUDIO);
    ORCHESTRATOR.activate_studio("ZIIS Demo Studio");
}

pub fn main() !void
{
    activities.undo_journal.initState(allocator, 5);

    app_wrapper.sokol_main(
        .{
            .draw = draw,
            .maybe_pre_zgui_shutdown_cleanup = cleanup,
            .maybe_post_zgui_init = init,
            .title = "ZIIS Demo App",
            .logger = ziis.std_log_scoped,
            .max_vertices = ziis.MAX_VERTICES,
        },
    );
}
