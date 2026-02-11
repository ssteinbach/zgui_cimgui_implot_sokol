//! example app using the app wrapper

const std = @import("std");
const builtin = @import("builtin");

const ziis = @import("zgui_cimgui_implot_sokol");
const zgui = ziis.zgui;
const zplot = zgui.plot;
const sg = ziis.sokol.gfx;
const app_wrapper = ziis.app_wrapper;

const cimgui = ziis.cimgui;

/// Data read from the example json, designed to be displayed by Zplot
const PieChartSliceData = struct
{
    label: [*:0]const u8,
    value: f64,
};

/// Context for sorting table rows
const SortContext = struct
{
    column: i16,
    ascending: bool,

    /// Compare two TableRowData items based on the sort column and direction
    pub fn lessThan(
        ctx: SortContext,
        a: STATE.TableRowData,
        b: STATE.TableRowData,
    ) bool
    {
        const result = switch (ctx.column)
        {
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
const STATE = struct {
    var f: f32 = 0;
    var demo_window_gui = false;
    var demo_window_plot = false;
    const TEX_DIM : [2]i32 = .{ 256, 256 };
    const COLOR_CHANNELS:usize = 4;
    var tex: sg.Image = .{};
    var view: sg.View = .{};
    var texid: u64 = 0;
    var frame_number: usize = 0;
    var buffer = std.mem.zeroes(
        [STATE.TEX_DIM[0]][STATE.TEX_DIM[1]][COLOR_CHANNELS]u8
    );
    var maybe_journal : ?ziis.undo.Journal = null;
    var image_data = ziis.sokol.gfx.ImageData{};

    var point_buffers: std.MultiArrayList(struct{ x: f32, y: f32 }) = .empty;

    // Fetch buffer for loading JSON file
    // will be created on initialization
    var json_fetch_query: *app_wrapper.FetchQuery = undefined;

    // JSON data storage... gets filled when the FetchQuery gets returned
    var data_from_json_file: std.MultiArrayList(PieChartSliceData) = .empty;

    // big text example (this source file)
    var big_text_query: *app_wrapper.FetchQuery = undefined;
    var big_text_example: []const u8 = undefined;

    // Threading demo state
    var thread_counter: std.atomic.Value(u32) = std.atomic.Value(u32).init(0);
    var threads_spawned: u32 = 0;
    var thread_task_queue: ziis.TaskQueue(*std.atomic.Value(u32)) = undefined;
    var task_queue_initialized: bool = false;
    var auto_process_tasks: bool = false; // Control auto-processing

    // Sortable table demo state
    const TableRowData = struct
    {
        id: u32,
        name: [:0]const u8,
        quantity: i32,
        price: f32,
        is_active: bool,
    };

    // Sample data for the sortable table
    var table_data = [_]TableRowData{
        .{ .id = 1, .name = "Apples", .quantity = 150, .price = 1.25, .is_active = true },
        .{ .id = 2, .name = "Bananas", .quantity = 200, .price = 0.75, .is_active = true },
        .{ .id = 3, .name = "Cherries", .quantity = 50, .price = 4.50, .is_active = false },
        .{ .id = 4, .name = "Dates", .quantity = 80, .price = 6.00, .is_active = true },
        .{ .id = 5, .name = "Elderberries", .quantity = 25, .price = 8.99, .is_active = false },
        .{ .id = 6, .name = "Figs", .quantity = 120, .price = 3.25, .is_active = true },
        .{ .id = 7, .name = "Grapes", .quantity = 300, .price = 2.50, .is_active = true },
        .{ .id = 8, .name = "Honeydew", .quantity = 45, .price = 5.00, .is_active = false },
    };

    // Web Worker demo state (WASM only)
    var worker_pool_initialized: bool = false;
    var maybe_worker_pool: ?ziis.worker_pool.WorkerPool = null;
    var worker_counter: std.atomic.Value(u32) = std.atomic.Value(u32).init(0);
    var worker_jobs_submitted: u32 = 0;
    var worker_jobs_completed: u32 = 0;
};

const IS_WASM = builtin.target.cpu.arch.isWasm();

// Emscripten extern function for fetching data via JavaScript
extern fn emscripten_run_script_string(script: [*:0]const u8) ?[*:0]const u8;

/// the GPA - useful for detecting leaks, but ONLY works in non EMCC builds
var debug_allocator = (
    if (IS_WASM) null 
    else std.heap.DebugAllocator(.{}){}
);
const allocator = (
    // @TODO: try the smp_allocator
    if (IS_WASM) std.heap.c_allocator
    else debug_allocator.allocator()
);

/// Returns the hovered label, value pair if the mouse is over the plot,
/// otherwise returns null.
///
/// Recomputes the angles and proportions of each slice.  If this is a scaling
/// issue, those could be precomputed and passed in.
fn maybe_pie_slice_under_mouse(
    /// type of the values in the pie chart
    comptime T: type,
    labels: []const [*:0]const u8,
    values: []const T,
) ?struct{
    label: [*:0]const u8,
    value: T,
}
{
    switch (@typeInfo(T))
    {
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
        std.math.atan2(dy, dx)
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

fn draw_pie_chart(
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
        }
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
            }
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
                .{hovered.label, hovered.value}
            );
        }
    }

}

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

        var new = STATE.f;
        if (zgui.dragFloat("texture offset", .{.v = &new})) 
        {
            const cmd = try ziis.undo.SetValue(f32).init(
                    allocator,
                    &STATE.f,
                    new,
                    "texture offset"
            );
            try cmd.do();
            try STATE.maybe_journal.?.update_if_new_or_add(cmd);
        }

        for (STATE.maybe_journal.?.entries.items, 0..)
            |cmd, ind|
        {
            zgui.bulletText("{d}: {s}", .{ ind, cmd.message });
        }

        zgui.bulletText(
            "Head Entry in Journal: {?d}",
            .{ STATE.maybe_journal.?.maybe_head_entry }
        );

        if (zgui.beginItemTooltip()) 
        {
            zgui.text("Hi, this is a tooltip", .{});
            zgui.endTooltip();
        }

        if (zgui.button("undo", .{}))
        {
            try STATE.maybe_journal.?.undo();
        }

        zgui.sameLine(.{});

        if (zgui.button("redo", .{}))
        {
            try STATE.maybe_journal.?.redo();
        }

        if (zgui.button("show gui demo", .{}) )
        { 
            STATE.demo_window_gui = ! STATE.demo_window_gui; 
        }
        if (zgui.button("show plot demo", .{}))
        {
            STATE.demo_window_plot = ! STATE.demo_window_plot; 
        }

        if (STATE.demo_window_gui) 
        {
            zgui.showDemoWindow(&STATE.demo_window_gui);
        }
        if (STATE.demo_window_plot) 
        {
            zplot.showDemoWindow(&STATE.demo_window_plot);
        }

        if (zgui.beginTabBar("Panes", .{}))
        {
            defer zgui.endTabBar();

            if (zgui.beginTabItem("PlotTab", .{}))
            {
                defer zgui.endTabItem();

                if (
                    zgui.beginChild(
                        "Plot", 
                        .{ .w = -1, .h = -1, },
                    )
                )
                {
                    defer zgui.endChild();

                    if (
                        zgui.plot.beginPlot(
                            "Test ZPlot Plot",
                            .{ 
                                .w = -1.0,
                                .h = -1.0,
                                .flags = .{ .equal = true },
                            },
                        )
                    ) 
                    {
                        defer zgui.plot.endPlot();

                        zgui.plot.setupAxis(
                            .x1,
                            .{ .label = "input" },
                        );
                        zgui.plot.setupAxis(
                            .y1,
                            .{ .label = "output" },
                        );
                        zgui.plot.setupLegend(
                            .{ 
                                .south = true,
                                .west = true 
                            },
                            .{},
                        );
                        zgui.plot.setupFinish();

                        const xs= [_]f32{0, 1, 2, 3, 4};
                        const ys= [_]f32{0, 1, 2, 3, 6};

                        zplot.pushStyleVar1f(
                            .{
                                .idx = .fill_alpha,
                                .v = 0.1,
                            }
                        );
                        defer zplot.popStyleVar(.{ .count = 1, });

                        zplot.plotText(
                            "start",
                            .{
                                .x = xs[0],
                                .y = ys[0],
                                .pix_offset = .{ -15, -10 },
                            }
                        );
                        zplot.plotText(
                            "end",
                            .{
                                .x = xs[xs.len-1],
                                .y = ys[ys.len-1],
                                .pix_offset = .{ 15, 0 },
                            }
                        );

                        zplot.plotLine(
                            "example function",
                            f32, 
                            .{
                                .xv = &xs,
                                .yv = &ys,
                                .flags = .{ .shaded = true }
                            },
                        );
                    }
                }
            }

            if (zgui.beginTabItem("Plot with LOTS of items", .{}))
            {
                defer zgui.endTabItem();

                if (
                    zgui.beginChild(
                        "Big Plot", 
                        .{ .w = -1, .h = -1, },
                    )
                )
                {
                    defer zgui.endChild();

                    if (
                        zgui.plot.beginPlot(
                            "Lots of items in plot test",
                            .{ 
                                .w = -1.0,
                                .h = -1.0,
                                .flags = .{ .equal = true },
                            },
                        )
                    ) 
                    {
                        defer zgui.plot.endPlot();

                        zgui.plot.setupAxis(
                            .x1,
                            .{ .label = "input" },
                        );
                        zgui.plot.setupAxis(
                            .y1,
                            .{ .label = "output" },
                        );
                        zgui.plot.setupLegend(
                            .{ 
                                .south = true,
                                .west = true 
                            },
                            .{},
                        );
                        zgui.plot.setupFinish();

                        const xs= STATE.point_buffers.items(.x);
                        const ys= STATE.point_buffers.items(.y);

                        zplot.pushStyleVar1f(
                            .{
                                .idx = .fill_alpha,
                                .v = 0.1,
                            }
                        );
                        defer zplot.popStyleVar(.{ .count = 1, });

                        zplot.plotLine(
                            "Sine wave with lots of samples",
                            f32, 
                            .{
                                .xv = xs,
                                .yv = ys,
                                .flags = .{ .shaded = true }
                            },
                        );
                    }
                }
            }

            if (zgui.beginTabItem("Stairs Plot Example", .{}))
            {
                defer zgui.endTabItem();

                if (
                    zgui.beginChild(
                        "Stairs Plot",
                        .{ .w = -1, .h = -1, },
                    )
                )
                {
                    defer zgui.endChild();

                    if (
                        zgui.plot.beginPlot(
                            "Stairstep Plot Demo",
                            .{
                                .w = -1.0,
                                .h = -1.0,
                            },
                        )
                    )
                    {
                        defer zgui.plot.endPlot();

                        zgui.plot.setupAxis(
                            .x1,
                            .{ .label = "Time" },
                        );
                        zgui.plot.setupAxis(
                            .y1,
                            .{ .label = "Value" },
                        );
                        zgui.plot.setupLegend(
                            .{
                                .north = true,
                                .east = true
                            },
                            .{},
                        );
                        zgui.plot.setupFinish();

                        // Example 1: Simple stairs with values only
                        const values= [_]f32{1.0, 3.0, 2.0, 5.0, 4.0, 6.0, 3.0};
                        zplot.plotStairsValues(
                            "Auto X-axis",
                            f32,
                            .{
                                .v = &values,
                            },
                        );

                        // Example 2: Stairs with explicit X and Y values
                        const xs= [_]f32{0.0, 1.0, 2.5, 3.5, 5.0, 6.0, 7.5};
                        const ys= [_]f32{2.0, 4.0, 3.0, 6.0, 5.0, 7.0, 4.0};
                        zplot.plotStairs(
                            "Explicit X-Y",
                            f32,
                            .{
                                .xv = &xs,
                                .yv = &ys,
                            },
                        );

                        // Example 3: Pre-step stairs (y value extends left)
                        const xs2= [_]f32{0.5, 1.5, 2.5, 3.5, 4.5, 5.5, 6.5};
                        const ys2= [_]f32{1.5, 2.5, 4.5, 3.5, 5.5, 4.5, 6.5};
                        zplot.plotStairs(
                            "Pre-step Mode",
                            f32,
                            .{
                                .xv = &xs2,
                                .yv = &ys2,
                                .flags = .{ .pre_step = true },
                            },
                        );

                        // Example 4: Shaded stairs
                        const xs3= [_]f32{0.25, 1.25, 2.25, 3.25, 4.25, 5.25, 6.25};
                        const ys3= [_]f32{0.5, 1.5, 1.0, 2.5, 2.0, 3.0, 2.5};
                        zplot.plotStairs(
                            "Shaded Stairs",
                            f32,
                            .{
                                .xv = &xs3,
                                .yv = &ys3,
                                .flags = .{ .shaded = true },
                            },
                        );
                    }
                }
            }

            if (
                zgui.beginTabItem(
                    "InfLines & PieChart Example",
                    .{},
                )
            )
            {
                defer zgui.endTabItem();

                if (
                    zgui.beginChild(
                        "InfLinesPieChartDemo",
                        .{ .w = -1, .h = -1, },
                    )
                )
                {
                    defer zgui.endChild();

                    if (
                        zgui.plot.beginPlot(
                            "Infinite Lines Demo",
                            .{
                                .w = -1.0,
                                .h = 300.0,
                            },
                        )
                    )
                    {
                        defer zgui.plot.endPlot();

                        zgui.plot.setupAxis(
                            .x1,
                            .{ .label = "X Axis" }
                        );
                        zgui.plot.setupAxis(
                            .y1,
                            .{ .label = "Y Axis" }
                        );
                        zgui.plot.setupAxisLimits(
                            .x1,
                            .{ .min = -1, .max = 10 }
                        );
                        zgui.plot.setupAxisLimits(
                            .y1,
                            .{ .min = -1, .max = 10 }
                        );
                        zgui.plot.setupFinish();

                        // Vertical infinite lines at x positions
                        const v_lines = [_]f64{1.0, 3.0, 5.0, 7.0};
                        zplot.plotInfLines(
                            "Vertical Lines",
                            f64,
                            .{ .v = &v_lines }
                        );

                        // Horizontal infinite lines at y positions
                        const h_lines = [_]f64{2.0, 4.0, 6.0};
                        zplot.plotInfLines(
                            "Horizontal Lines",
                            f64, .{
                                .v = &h_lines,
                                .flags = .{
                                    .horizontal = true,
                                },
                            }
                        );
                    }

                    const pie_labels = [_][*:0]const u8{
                        "Tacos",
                        "Pizza",
                        "Pasta",
                        "Sushi"
                    };
                    const pie_values = (
                        [_]f64{ 30.0, 25.0, 20.0, 15.0 }
                    );

                    if (
                        zgui.plot.beginPlot(
                            "Pie Chart Demo",
                            .{
                                .w = -1.0,
                                .h = -1.0,
                                .flags = .{ .equal = true },
                            },
                        )
                    )
                    {
                        defer zgui.plot.endPlot();

                        zplot.plotPieChart(
                            f64,
                            .{
                                .label_ids = &pie_labels,
                                .values = &pie_values,
                                .flags = .{ .normalize = true },
                            }
                        );

                        // tooltip on hover/click
                        if (
                            maybe_pie_slice_under_mouse(
                                f64,
                                &pie_labels,
                                &pie_values
                            )
                        ) |hovered|
                        {
                            const mouse_screen_pos = zgui.getMousePos();
                            zgui.setNextWindowPos(
                                .{
                                    .x = mouse_screen_pos[0] + 15,
                                    .y = mouse_screen_pos[1] + 15,
                                }
                            );
                            zgui.setNextWindowBgAlpha(.{ .alpha = 0.75 });

                            if (
                                zgui.begin(
                                    "###PieChartTooltip",
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
                                    "Hovered\n  slice: {s}\n  value: {d}",
                                    .{hovered.label, hovered.value});
                            }

                            // print on click as well
                            if (zgui.isMouseClicked(.left))
                            {
                                std.debug.print(
                                    "Clicked on {s} slice!\n",
                                    .{hovered.label}
                                );
                            }
                        }
                    }
                }
            }

            if (zgui.beginTabItem("Texture Example", .{}))
            {
                defer zgui.endTabItem();

                const wsize = zgui.getWindowSize();

                ziis.cimgui.igImage(
                    .{ ._TexID = STATE.texid },
                    .{ .x = wsize[0], .y = wsize[1]},
                );
            }

            if (
                zgui.beginTabItem("Canvas Drawing Example", .{})
                and zgui.beginChild(
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
                defer zgui.endTabItem();
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


                const c1 = zgui.colorConvertFloat4ToU32(.{0.8, 0.2, 0.2, 0.4});
                const c2 = zgui.colorConvertFloat4ToU32(.{0.2, 0.8, 0.2, 0.4});
                const c3 = zgui.colorConvertFloat4ToU32(.{0.2, 0.2, 0.8, 0.4});
                const c4 = zgui.colorConvertFloat4ToU32(.{0.8, 0.8, 0.8, 0.9});

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

            if (zgui.beginTabItem("JSON Pie Chart", .{}))
            {
                defer zgui.endTabItem();

                if (
                    zgui.beginChild(
                        "JSON Pie Chart",
                        .{ .w = -1, .h = -1, },
                    )
                )
                {
                    defer zgui.endChild();

                    // Display fetch status with colors
                    switch (STATE.json_fetch_query.state)
                    {
                        .failed => {
                            zgui.pushStyleColor4f(
                                .{
                                    .idx = .text,
                                    .c = .{ 1.0, 0.0, 0.0, 1.0 },
                                },
                            );
                            zgui.text(
                                "Failed to load example.json via sokol.fetch",
                                .{},
                            );

                            if (STATE.json_fetch_query.maybe_error != null)
                            {
                                zgui.text(
                                    "  Error: {s}",
                                    .{STATE.json_fetch_query.error_message()},
                                );
                                zgui.text(
                                    "  Code: {s}",
                                    .{STATE.json_fetch_query.error_name()},
                                );
                                zgui.text(
                                    "  Path: {s}",
                                    .{STATE.json_fetch_query.target_path},
                                );
                            }

                            zgui.popStyleColor(.{});
                        },
                        .loading => {
                            zgui.pushStyleColor4f(
                                .{ 
                                    .idx = .text,
                                    .c = .{ 0.0, 0.5, 1.0, 1.0 },
                                },
                            );
                            zgui.text(
                                "Loading example.json... ({s})",
                                .{
                                    @tagName(STATE.json_fetch_query.state)
                                }
                            );
                            zgui.popStyleColor(.{});
                        },
                        .loaded => {
                            // Display success message in green
                            zgui.pushStyleColor4f(
                                .{
                                    .idx = .text,
                                    .c = .{ 0.0, 1.0, 0.0, 1.0 },
                                }
                            );
                            zgui.text(
                                "JSON data loaded successfully via sokol.fetch",
                                .{}
                            );
                            zgui.popStyleColor(.{});

                            if (
                                zgui.plot.beginPlot(
                                    "Data from example.json",
                                    .{
                                        .w = -1.0,
                                        .h = -1.0,
                                        .flags = .{ .equal = true },
                                    },
                                )
                            )
                            {
                                defer zgui.plot.endPlot();

                                try draw_pie_chart();
                            }
                        }
                    }
                }
            }

            if (
                zgui.beginTabItem("Big Text Test", .{})
                and zgui.beginChild("Big Child Test",.{})
            )
            {
                defer zgui.endTabItem();
                defer zgui.endChild();

                switch (STATE.big_text_query.state)
                {
                    .loaded => {
                        zgui.separatorText("Big text embed test");

                        const TEXT = (
                            STATE.big_text_query.result_data_buffer
                        );

                        zgui.textUnformatted(TEXT);
                    },
                    .failed => {
                        zgui.pushStyleColor4f(
                            .{
                                .idx = .text,
                                .c = .{ 1.0, 0.0, 0.0, 1.0 },
                            },
                        );
                        zgui.text(
                            "Failed to load big text file",
                            .{},
                        );

                        if (STATE.big_text_query.maybe_error != null)
                        {
                            zgui.text(
                                "  Error: {s}",
                                .{STATE.big_text_query.error_message()},
                            );
                            zgui.text(
                                "  Code: {s}",
                                .{STATE.big_text_query.error_name()},
                            );
                            zgui.text(
                                "  Path: {s}",
                                .{STATE.big_text_query.target_path},
                            );
                        }

                        zgui.popStyleColor(.{});
                    },
                    .loading => {
                        zgui.text(
                            "Loading big data...",
                            .{},
                        );
                    },
                }

            }

            // Sortable Table Demo Tab
            if (zgui.beginTabItem("Sortable Table", .{}))
            {
                defer zgui.endTabItem();

                zgui.separatorText("Sortable Table Demo");

                zgui.textWrapped(
                    \\Click on column headers to sort. Hold Shift to multi-sort.
                    \\Columns can be resized and reordered.
                    ,
                    .{},
                );

                zgui.spacing();

                // Begin the table with sorting enabled
                if (
                    zgui.beginTable(
                        "SortableTable",
                        .{
                            .column = 5,
                            .flags = .{
                                .sortable = true,
                                .sort_multi = true,
                                .resizable = true,
                                .reorderable = true,
                                .hideable = true,
                                .row_bg = true,
                                .borders = .{
                                    .inner_h = true,
                                    .inner_v = true,
                                    .outer_h = true,
                                    .outer_v = true,
                                },
                                .sizing = .stretch_prop,
                                .scroll_y = true,
                            },
                            .outer_size = .{ 0, 300 },
                        },
                    )
                )
                {
                    defer zgui.endTable();

                    // Setup columns with sorting preferences
                    zgui.tableSetupColumn(
                        "ID",
                        .{
                            .flags = .{
                                .default_sort = true,
                                .prefer_sort_ascending = true,
                            },
                        },
                    );
                    zgui.tableSetupColumn(
                        "Name",
                        .{
                            .flags = .{ .prefer_sort_ascending = true },
                        },
                    );
                    zgui.tableSetupColumn(
                        "Quantity",
                        .{
                            .flags = .{ .prefer_sort_descending = true },
                        },
                    );
                    zgui.tableSetupColumn(
                        "Price",
                        .{
                            .flags = .{ .prefer_sort_descending = true },
                        },
                    );
                    zgui.tableSetupColumn(
                        "Active",
                        .{
                            .flags = .{ .no_sort = true },
                        },
                    );

                    // Freeze header row
                    zgui.tableSetupScrollFreeze(0, 1);
                    zgui.tableHeadersRow();

                    // Handle sorting
                    if (zgui.tableGetSortSpecs())
                        |sort_specs|
                    {
                        if (sort_specs.dirty)
                        {
                            // Sort the data based on specs
                            const specs = sort_specs.specs[0..@intCast(sort_specs.count)];
                            if (specs.len > 0)
                            {
                                const spec = specs[0];
                                const ascending = spec.sort_direction == .ascending;

                                std.mem.sort(
                                    STATE.TableRowData,
                                    &STATE.table_data,
                                    SortContext{ .column = spec.index, .ascending = ascending },
                                    SortContext.lessThan,
                                );
                            }
                            sort_specs.dirty = false;
                        }
                    }

                    // Draw rows
                    for (&STATE.table_data)
                        |*row|
                    {
                        zgui.tableNextRow(.{});

                        // ID column
                        _ = zgui.tableNextColumn();
                        zgui.text("{d}", .{row.id});

                        // Name column
                        _ = zgui.tableNextColumn();
                        zgui.textUnformatted(row.name);

                        // Quantity column
                        _ = zgui.tableNextColumn();
                        zgui.text("{d}", .{row.quantity});

                        // Price column
                        _ = zgui.tableNextColumn();
                        zgui.text("${d:.2}", .{row.price});

                        // Active column with colored indicator
                        _ = zgui.tableNextColumn();
                        if (row.is_active)
                        {
                            zgui.pushStyleColor4f(
                                .{
                                    .idx = .text,
                                    .c = .{ 0.0, 1.0, 0.0, 1.0 },
                                },
                            );
                            zgui.textUnformatted("Yes");
                            zgui.popStyleColor(.{});
                        }
                        else
                        {
                            zgui.pushStyleColor4f(
                                .{
                                    .idx = .text,
                                    .c = .{ 1.0, 0.3, 0.3, 1.0 },
                                },
                            );
                            zgui.textUnformatted("No");
                            zgui.popStyleColor(.{});
                        }
                    }
                }

                zgui.spacing();
                zgui.separator();
                zgui.spacing();

                // Summary stats
                var total_quantity: i32 = 0;
                var total_value: f32 = 0;
                var active_count: u32 = 0;

                for (&STATE.table_data)
                    |row|
                {
                    total_quantity += row.quantity;
                    total_value += @as(f32, @floatFromInt(row.quantity)) * row.price;
                    if (row.is_active)
                    {
                        active_count += 1;
                    }
                }

                zgui.text("Total Items: {d}", .{STATE.table_data.len});
                zgui.text("Total Quantity: {d}", .{total_quantity});
                zgui.text("Total Value: ${d:.2}", .{total_value});
                zgui.text("Active Products: {d}/{d}", .{ active_count, STATE.table_data.len });
            }

            // Threading Demo Tab
            if (zgui.beginTabItem("Threading Demo", .{}))
            {
                defer zgui.endTabItem();

                zgui.separatorText("Platform-Agnostic Threading Demo");

                // Initialize task queue on first use
                if (!STATE.task_queue_initialized)
                {
                    STATE.thread_task_queue = ziis.TaskQueue(
                        *std.atomic.Value(u32)
                    ).init(allocator);
                    STATE.task_queue_initialized = true;
                }

                const HAS_THREADS = ziis.thread.HAS_THREADS;
                const IS_WASM_TARGET = ziis.thread.IS_WASM;

                zgui.text("Platform: {s}", .{
                    if (IS_WASM_TARGET) "WASM (Emscripten)"
                    else "Native"
                });
                zgui.text("Threading: {s}", .{
                    if (HAS_THREADS) "True Multithreading (std.Thread)"
                    else "Synchronous Fallback"
                });

                zgui.spacing();
                zgui.separator();
                zgui.spacing();

                // Counter display
                const current_count = STATE.thread_counter.load(.seq_cst);
                zgui.text("Counter Value: {d}", .{current_count});
                zgui.text("Threads/Tasks Spawned: {d}", .{STATE.threads_spawned});
                zgui.text("Pending Tasks in Queue: {d}", .{
                    STATE.thread_task_queue.pending()
                });

                zgui.spacing();

                // Spawn thread button
                if (zgui.button("Spawn Thread (adds 100)", .{}))
                {
                    if (HAS_THREADS)
                    {
                        // True multithreading
                        if (ziis.Thread.spawn(
                            .{},
                            struct {
                                fn work(counter: *std.atomic.Value(u32)) void {
                                    var i: u32 = 0;
                                    while (i < 100) : (i += 1)
                                    {
                                        _ = counter.fetchAdd(1, .seq_cst);
                                    }
                                }
                            }.work,
                            .{&STATE.thread_counter},
                        )) |t|
                        {
                            t.detach();
                            STATE.threads_spawned += 1;
                        }
                        else |err|
                        {
                            std.log.err("Failed to spawn thread: {any}", .{err});
                        }
                    }
                    else
                    {
                        // WASM: executes synchronously
                        _ = ziis.Thread.spawn(
                            .{},
                            struct {
                                fn work(counter: *std.atomic.Value(u32)) void {
                                    var i: u32 = 0;
                                    while (i < 100) : (i += 1)
                                    {
                                        _ = counter.fetchAdd(1, .seq_cst);
                                    }
                                }
                            }.work,
                            .{&STATE.thread_counter},
                        ) catch {};
                        STATE.threads_spawned += 1;
                    }
                }

                if (zgui.isItemHovered(.{}) and zgui.beginItemTooltip())
                {
                    defer zgui.endTooltip();
                    zgui.text(
                        if (HAS_THREADS)
                            "Spawns a real thread that increments counter"
                        else
                            "Executes synchronously (no true threading on WASM)",
                        .{},
                    );
                }

                zgui.sameLine(.{});

                // Add to task queue button
                if (zgui.button("Add to Task Queue (adds 1)", .{}))
                {
                    STATE.thread_task_queue.enqueue(.{
                        .context = &STATE.thread_counter,
                        .work = struct {
                            fn work(counter: *std.atomic.Value(u32)) void {
                                _ = counter.fetchAdd(1, .seq_cst);
                            }
                        }.work,
                    }) catch {};
                    STATE.threads_spawned += 1;
                }

                if (zgui.isItemHovered(.{}) and zgui.beginItemTooltip())
                {
                    defer zgui.endTooltip();
                    zgui.text("Adds task to queue (processed per-frame)", .{});
                }

                zgui.spacing();

                if (zgui.button("Process One Task", .{}))
                {
                    _ = STATE.thread_task_queue.processOne();
                }

                zgui.sameLine(.{});

                if (zgui.button("Process All Tasks", .{}))
                {
                    _ = STATE.thread_task_queue.processAll();
                }

                zgui.spacing();

                _ = zgui.checkbox("Auto-process tasks each frame", .{
                    .v = &STATE.auto_process_tasks
                });

                zgui.spacing();

                if (zgui.button("Reset Counter", .{}))
                {
                    STATE.thread_counter.store(0, .seq_cst);
                    STATE.threads_spawned = 0;
                }

                zgui.spacing();
                zgui.separator();
                zgui.spacing();

                zgui.textWrapped(
                    \\This demo shows platform-agnostic threading:
                    \\
                    \\• Native builds use real threads (std.Thread)
                    \\• WASM builds use synchronous fallback
                    \\• TaskQueue provides cooperative multitasking
                    \\  that works on all platforms
                    \\
                    \\The Thread abstraction makes code portable
                    \\between native and web targets!
                    \\
                    \\TIP: Uncheck auto-process to see tasks accumulate!
                    ,
                    .{},
                );

                // Auto-process one task per frame if enabled
                if (STATE.auto_process_tasks) {
                    _ = STATE.thread_task_queue.processOne();
                }
            }

            // Web Worker Pool Demo Tab (WASM only)
            // NOTE: Currently disabled due to EM_JS linking issues with Zig build system
            // The worker pool implementation is complete but needs the build system
            // to properly handle EM_JS JavaScript extraction from C objects
            if (false and IS_WASM and zgui.beginTabItem("Web Worker Pool", .{}))
            {
                defer zgui.endTabItem();

                zgui.separatorText("Web Worker Pool Demo (Coming Soon)");

                zgui.textWrapped(
                    \\The Web Worker Pool implementation is complete!
                    \\
                    \\However, there's a known issue with linking EM_JS
                    \\functions when using the Zig build system. The EM_JS
                    \\macros in worker_js_interop.c generate JavaScript that
                    \\needs special handling by emcc.
                    \\
                    \\To use the Worker Pool:
                    \\• See worker_pool_full.zig for the API
                    \\• See IMPLEMENTATION_STATUS.md for details
                    \\• See WEBWORKER_PROJECT.md for the full spec
                    \\
                    \\The implementation includes:
                    \\• 4 Web Workers running in parallel
                    \\• Message passing (no SharedArrayBuffer needed)
                    \\• 30 second timeout per work item
                    \\• Automatic worker health monitoring
                    \\• Context serialization for POD types
                    ,
                    .{},
                );
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

    // Clean up threading demo resources
    if (STATE.task_queue_initialized)
    {
        STATE.thread_task_queue.deinit();
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
        },
    );
}
