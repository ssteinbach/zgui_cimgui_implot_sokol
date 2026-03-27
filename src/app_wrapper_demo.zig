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
const activities = @import("demo_activities/root.zig");

/// Data read from the example json, designed to be displayed by Zplot
const PieChartSliceData = struct {
    label: [*:0]const u8,
    value: f64,
};

/// Context for sorting table rows
pub const SortContext = struct {
    column: i16,
    ascending: bool,

    /// Compare two TableRowData items based on the sort column and direction
    pub fn lessThan(
        ctx: SortContext,
        a: STATE.TableRowData,
        b: STATE.TableRowData,
    ) bool
    {
        const result = switch (ctx.column) {
            // ID column
            0 => std.math.order(a.id, b.id),
            // Name column
            1 => std.mem.order(u8, a.name, b.name),
            // Quantity column
            2 => std.math.order(a.quantity, b.quantity),
            // Price column
            3 => std.math.order(a.price, b.price),
            // Default
            else => .eq,
        };

        return if (ctx.ascending)
            result == .lt
        else
            result == .gt;
    }
};

/// State container
/// @TODO: break this out into activity-specific states
pub const STATE = struct {
    pub var f: f32 = 0;
    pub var demo_window_gui = false;
    pub var demo_window_plot = false;
    pub const TEX_DIM : [2]i32 = .{ 256, 256 };
    pub const COLOR_CHANNELS:usize = 4;
    pub var tex: sg.Image = .{};
    pub var view: sg.View = .{};
    pub var texid: u64 = 0;
    pub var frame_number: usize = 0;
    pub var buffer = std.mem.zeroes(
        [STATE.TEX_DIM[0]][STATE.TEX_DIM[1]][COLOR_CHANNELS]u8,
    );
    pub var maybe_journal : ?ziis.undo.Journal = null;
    pub var image_data = ziis.sokol.gfx.ImageData{};

    pub var point_buffers: std.MultiArrayList(struct{ x: f32, y: f32 }) = .empty;

    // Fetch buffer for loading JSON file
    // will be created on initialization
    pub var json_fetch_query: *app_wrapper.FetchQuery = undefined;

    // JSON data storage... gets filled when the FetchQuery gets returned
    pub var data_from_json_file: std.MultiArrayList(PieChartSliceData) = .empty;

    // big text example (this source file)
    pub var big_text_query: *app_wrapper.FetchQuery = undefined;
    pub var big_text_example: []const u8 = undefined;

    // Sortable table demo state
    pub const TableRowData = struct {
        id: u32,
        name: [:0]const u8,
        quantity: i32,
        price: f32,
        is_active: bool,
    };

    // Sample data for the sortable table
    pub var table_data = [_]TableRowData{
        .{
            .id = 1,
            .name = "Apples",
            .quantity = 150,
            .price = 1.25,
            .is_active = true,
        },
        .{
            .id = 2,
            .name = "Bananas",
            .quantity = 200,
            .price = 0.75,
            .is_active = true,
        },
        .{
            .id = 3,
            .name = "Cherries",
            .quantity = 50,
            .price = 4.50,
            .is_active = false,
        },
        .{
            .id = 4,
            .name = "Dates",
            .quantity = 80,
            .price = 6.00,
            .is_active = true,
        },
        .{
            .id = 5,
            .name = "Elderberries",
            .quantity = 25,
            .price = 8.99,
            .is_active = false,
        },
        .{
            .id = 6,
            .name = "Figs",
            .quantity = 120,
            .price = 3.25,
            .is_active = true,
        },
        .{
            .id = 7,
            .name = "Grapes",
            .quantity = 300,
            .price = 2.50,
            .is_active = true,
        },
        .{
            .id = 8,
            .name = "Honeydew",
            .quantity = 45,
            .price = 5.00,
            .is_active = false,
        },
    };

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
        .{ .run_ui = &activities.texture.runUI },
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

/// Returns the hovered label, value pair if the mouse is over the plot,
/// otherwise returns null.
///
/// Recomputes the angles and proportions of each slice.  If this is a scaling
/// issue, those could be precomputed and passed in.
pub fn maybe_pie_slice_under_mouse(
    /// type of the values in the pie chart
    comptime T: type,
    labels: []const [*:0]const u8,
    values: []const T,
) ?struct{
    label: [*:0]const u8,
    value: T,
}
{
    switch (@typeInfo(T)) {
        .@"float", .@"int" => {},
        inline else => @compileError(
            "Only supports pie charts of numeric values"
        ),
    }

    if (zplot.isPlotHovered() == false)
    {
        return null;
    }

    const mouse_pos = zplot.getPlotMousePos(.x1, .y1);
    const plot_limits = zplot.getPlotLimits(.x1, .y1);

    const plot_width = plot_limits.x[1] - plot_limits.x[0];
    const plot_height = plot_limits.y[1] - plot_limits.y[0];
    const center_x = plot_limits.x[0] + plot_width / 2.0;
    const center_y = plot_limits.y[0] + plot_height / 2.0;

    const dx = mouse_pos[0] - center_x;
    const dy = mouse_pos[1] - center_y;
    const dist = @sqrt(dx * dx + dy * dy);

    // pie chart uses half the smaller plot dimension
    const radius = @min(plot_width, plot_height) / 2.0;

    if (dist > radius)
    {
        return null;
    }

    // calculate angle (atan2 from right, CCW)
    // rotate -90° to start from top
    const angle_raw = std.math.radiansToDegrees(
        std.math.atan2(dy, dx),
    );
    const angle = @mod(angle_raw - 90.0, 360.0);

    var total: f64 = 0;
    for (values)
        |v|
    {
        total += @as(f64, @floatCast(v));
    }

    var cumulative_angle: f64 = 0;
    for (labels, values)
        |label, value|
    {
        const slice_angle = (@as(f64, @floatCast(value)) / total) * 360.0;
        if (
            angle >= cumulative_angle
            and angle < cumulative_angle + slice_angle
        )
        {
            return .{ .label = label, .value = value };
        }
        cumulative_angle += slice_angle;
    }

    return null;
}

pub fn draw_pie_chart(
) !void
{
    const labels = STATE.data_from_json_file.items(.label);
    const values = STATE.data_from_json_file.items(.value);

    zplot.plotPieChart(
        f64,
        .{
            .label_ids = labels,
            .values = values,
            .flags = .{ .normalize = true },
        },
    );

    // Add tooltip on hover
    if (maybe_pie_slice_under_mouse( f64, labels, values))
        |hovered|
    {
        const mouse_screen_pos = zgui.getMousePos();

        // scooch it over
        zgui.setNextWindowPos(
            .{
                .x = mouse_screen_pos[0] + 15,
                .y = mouse_screen_pos[1] + 15,
            },
        );
        zgui.setNextWindowBgAlpha(.{ .alpha = 0.75 });

        if (
            zgui.begin(
                "###JSONPieChartTooltip",
                .{
                    .flags = .{
                        .no_title_bar = true,
                        .no_resize = true,
                        .no_move = true,
                        .always_auto_resize = true,
                        .no_saved_settings = true,
                        .no_focus_on_appearing = true,
                        .no_nav_inputs = true,
                        .no_nav_focus = true,
                    },
                },
            )
        )
        {
            defer zgui.end();

            zgui.text(
                "Item: {s}\nValue: {d}",
                .{hovered.label, hovered.value},
            );
        }
    }

}

// RunUI callbacks are in src/demo_activities/

// =========================================================================
// draw — orchestrator-driven frame
// =========================================================================

/// draw the UI
fn draw(
) !void
{
    const vp = zgui.getMainViewport();
    const size = vp.getSize();

    STATE.frame_number = @intFromFloat(@abs(STATE.f));

    sg.updateImage(
        STATE.tex,
        init: {
            // initialize the image STATE.buffer
            var x:usize = 0;
            const iw_m_one: f64 = @floatFromInt(STATE.TEX_DIM[0] - 1);
            const ih_m_one: f64 = @floatFromInt(STATE.TEX_DIM[1] - 1);
            while (x < STATE.TEX_DIM[0])
                : (x += 1)
            {
                const fx: f64 = @floatFromInt(
                    @mod(x + STATE.frame_number, STATE.TEX_DIM[0])
                );
                var y:usize = 0;
                while (y < STATE.TEX_DIM[1])
                    : (y += 1)
                {
                    const fy: f64 = @floatFromInt(
                        @mod(y + STATE.frame_number, STATE.TEX_DIM[1])
                    );

                    const r = fx / iw_m_one;
                    const g = fy / ih_m_one;
                    const b:f64 = 0.0;

                    STATE.buffer[x][y][0] = @intFromFloat(255.999 * r);
                    STATE.buffer[x][y][1] = @intFromFloat(255.999 * g);
                    STATE.buffer[x][y][2] = @intFromFloat(255.999 * b);
                    STATE.buffer[x][y][3] = 255;
                }
            }

            STATE.image_data.mip_levels[0] = ziis.sokol.gfx.asRange(
                &STATE.buffer,
            );

            break :init STATE.image_data;
        },
    );

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
                    .no_scroll_with_mouse  = true, 
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
                .{ ORCHESTRATOR.activities.count() },
            );
        }

        zgui.separator();

        if (zgui.beginTabBar("Panes", .{}))
        {
            defer zgui.endTabBar();

            // Iterate active, UI-visible Activities and render each as a tab
            var it = ORCHESTRATOR.activeUIActivities();
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

fn cleanup (
) void
{
    STATE.json_fetch_query.deinit();
    allocator.destroy(STATE.json_fetch_query);

    STATE.big_text_query.deinit();
    allocator.destroy(STATE.big_text_query);

    STATE.point_buffers.deinit(allocator);

    for (STATE.data_from_json_file.items(.label))
        |labels|
    {
        allocator.free(std.mem.span(labels));
    }
    STATE.data_from_json_file.deinit(allocator);

    if (STATE.maybe_journal)
        |*definitely_journal|
    {
        definitely_journal.deinit();
    }

    // Clean up worker pool resources
    // NOTE: Disabled due to EM_JS linking issues
    // if (STATE.worker_pool_initialized)
    // {
    //     if (STATE.maybe_worker_pool) |*pool| {
    //         pool.deinit();
    //     }
    // }
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

/// read the JSON from the parsed file blob and configure the STATE variables
fn json_parsing_callback(
    /// fetch response
    fetch_query: *app_wrapper.FetchQuery,
) error{CallbackError}!void
{
    const parsed = std.json.parseFromSlice(
        std.json.Value,
        allocator,
        fetch_query.result_data_buffer,
        .{}
    ) catch {
        return error.CallbackError;
    }; 
    defer parsed.deinit();

    const obj = parsed.value.object;
    var iter = obj.iterator();
    while (iter.next())
        |entry|
    {
        // copy the key out into a format that is ready to display in zplot
        const key_copy = allocator.dupeZ(
            u8, 
            entry.key_ptr.*,
        ) catch continue;

        STATE.data_from_json_file.append(
            allocator,
            .{
                .label = key_copy,
                .value = @as(
                    f64,
                    @floatFromInt(entry.value_ptr.integer),
                ),
            },
        ) catch continue;
    }

    if (STATE.data_from_json_file.len == 0)
    {
        return error.CallbackError;
    }
}

pub fn init(
) void
{
    // right around the minimum number of points to make the plot disapear
    const BIGCOUNT = if (IS_WASM) 7000 else 75000;
    STATE.point_buffers.ensureUnusedCapacity(
        allocator,
        BIGCOUNT,
    ) catch {};

    const inc = 0.01;
    var cur:f32 = -10.0;
    for (0..(BIGCOUNT-1))
        |_|
    {
        STATE.point_buffers.appendAssumeCapacity(
            .{
                .x = cur,
                .y = std.math.sin(cur),
            }
        );

        cur += inc;
    }

    STATE.tex = sg.makeImage(
        .{
            .width = STATE.TEX_DIM[0],
            .height = STATE.TEX_DIM[1],
            .usage = .{ .stream_update = true },
            .pixel_format = .RGBA8,
        },
    );

    STATE.view = sg.makeView(
        .{
            .texture = .{
                .image = STATE.tex,
            },
        },
    );

    STATE.texid = ziis.sokol.imgui.imtextureid(STATE.view);

    // configure initial fetch
    STATE.json_fetch_query = app_wrapper.fetch_resource(
        allocator,
        "example.json",
        .{
            .maybe_callback = json_parsing_callback,
            .compression = .none,
        },
    ) catch {
        std.log.err(
            "Unable to fetch data: {s}",
            .{ "example.json" },
        );
        return;
    };

    STATE.big_text_query = app_wrapper.fetch_resource(
        allocator,
        "src/app_wrapper_demo.zig",
        .{
            // zig file should be uncomporessed
            .compression = .none,
        },
    ) catch {
        std.log.err(
            "Unable to fetch data: {s}",
            .{ "src/app_wrapper_demo.zig" },
        );
        return;
    };

    // Initialize orchestrator and register Activities + Studio
    ORCHESTRATOR = MeshulaLab.Orchestrator.init(allocator);

    ORCHESTRATOR.registerActivity(&ACTIVITIES.undo_journal);
    ORCHESTRATOR.registerActivity(&ACTIVITIES.plot);
    ORCHESTRATOR.registerActivity(&ACTIVITIES.big_plot);
    ORCHESTRATOR.registerActivity(&ACTIVITIES.stairs_plot);
    ORCHESTRATOR.registerActivity(&ACTIVITIES.polygon_plot);
    ORCHESTRATOR.registerActivity(&ACTIVITIES.inflines_pie);
    ORCHESTRATOR.registerActivity(&ACTIVITIES.texture);
    ORCHESTRATOR.registerActivity(&ACTIVITIES.canvas);
    ORCHESTRATOR.registerActivity(&ACTIVITIES.json_pie);
    ORCHESTRATOR.registerActivity(&ACTIVITIES.big_text);
    ORCHESTRATOR.registerActivity(&ACTIVITIES.list_clipper);
    ORCHESTRATOR.registerActivity(&ACTIVITIES.sortable_table);

    ORCHESTRATOR.registerStudio(&DEMO_STUDIO);
    ORCHESTRATOR.activateStudio("ZIIS Demo Studio");
}

pub fn main(
) !void 
{
    STATE.maybe_journal = ziis.undo.Journal.init(
        allocator,
        5,
    ) catch null;

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
