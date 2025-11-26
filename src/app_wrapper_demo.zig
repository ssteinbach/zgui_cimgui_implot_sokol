//! example app using the app wrapper

const std = @import("std");
const builtin = @import("builtin");

const ziis = @import("zgui_cimgui_implot_sokol");
const zgui = ziis.zgui;
const zplot = zgui.plot;
const sg = ziis.sokol.gfx;
const app_wrapper = ziis.app_wrapper;

const cimgui = ziis.cimgui;

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
};

const IS_WASM = builtin.target.cpu.arch.isWasm();

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

/// detect clicks on pie chart slices
fn detectPieChartClick(
    comptime T: type,
    labels: []const [*:0]const u8,
    values: []const T,
) ?[*:0]const u8
{
    if (
        !zplot.isPlotHovered()
        or !zgui.isMouseClicked(.left)
    )
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
            return label;
        }
        cumulative_angle += slice_angle;
    }

    return null;
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

                        const pie_labels = [_][*:0]const u8{
                            "Tacos",
                            "Pizza",
                            "Pasta",
                            "Sushi"
                        };
                        const pie_values = (
                            [_]f64{ 30.0, 25.0, 20.0, 15.0 }
                        );

                        zplot.plotPieChart(
                            f64,
                            .{
                                .label_ids = &pie_labels,
                                .values = &pie_values,
                                .flags = .{ .normalize = true },
                            }
                        );

                        // detect clicks on pie slices
                        if (
                            detectPieChartClick(
                                f64,
                                &pie_labels,
                                &pie_values
                            )
                        ) |clicked_label|
                        {
                            std.debug.print(
                                "Clicked on {s} slice!\n",
                                .{std.mem.span(clicked_label)}
                            );
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
        }
    }
}

fn cleanup (
) void
{
    STATE.point_buffers.deinit(allocator);

    if (STATE.maybe_journal)
        |*definitely_journal|
    {
        definitely_journal.deinit();
    }

    if (IS_WASM == false)
    {
        const result = debug_allocator.deinit();
        if (result == .leak) 
        {
            std.log.debug("leak!", .{});
        }
    }

}

pub fn init(
) void
{ 
    // right around the minimum number of points to make the plot disapear
    const BIGCOUNT = 7750;
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
        },
    );
}
