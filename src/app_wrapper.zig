//! Wrapper for an app using ZIIS - see app_wrapper_demo for an example

const std = @import("std");
const builtin= @import("builtin");

const ziis = @import("root.zig");
const zgui = ziis.zgui;
const zplot = ziis.zgui.plot;
const sokol = ziis.sokol;
const sg = sokol.gfx;
const sapp = sokol.app;
const sglue = sokol.glue;
const simgui = sokol.imgui;
const fetch = @import("fetch.zig");
const sfetch = ziis.sokol.fetch;

/// building with wasm?
const IS_WASM = builtin.target.cpu.arch.isWasm();

/// Maximum number of vertices you can configure the app to support.  Get more
/// vertices than this and the UI drops out.
pub const MAX_VERTICES = std.math.maxInt(i32)/7;

var debug_allocator = (
    if (IS_WASM) null 
    else std.heap.DebugAllocator(.{}){}
);
const backing_allocator = (
    // @TODO: try the smp_allocator
    if (IS_WASM) std.heap.c_allocator 
    else debug_allocator.allocator()
);

/// State container
const STATE = struct {
    var pass_action: sg.PassAction = .{};

    /// gets configured by sokol_main
    var app: SokolApp = undefined;

    /// default font
    const font_data = @embedFile("content/Roboto-Medium.ttf");

    /// allocator for configuring imgui/sokol/etc.
    const allocator = backing_allocator;
};

/// Wrapper around sokol window update function
pub fn set_window_title(
    title: [:0]const u8,
) void
{
    sapp.setWindowTitle(title);
}

/// Set the background clear color (RGBA, 0.0–1.0).
pub fn set_clear_color(r: f32, g: f32, b: f32, a: f32) void {
    STATE.pass_action.colors[0].clear_value = .{ .r = r, .g = g, .b = b, .a = a };
}

export fn init(
) void 
{
    // initialize sokol-gfx
    sg.setup(
        .{
            .environment = sglue.environment(),
            .logger = .{ .func = STATE.app.logger },
        },
    );

    // initialize sokol-imgui
    simgui.setup(
        .{
            // max out the vertex buffer... might be overkill
            .max_vertices = STATE.app.max_vertices,
            .logger = .{ .func = STATE.app.logger },
        },
    );

    // initial clear color
    STATE.pass_action.colors[0] = .{
        .load_action = .CLEAR,
        .clear_value = .{
            .r = 0.0,
            .g = 0.5,
            .b = 1.0,
            .a = 1.0,
        },
    };

    STATE.pass_action.depth = .{
        .load_action = .CLEAR,
        .clear_value = 1.0,
    };

    zgui.init(STATE.allocator);

    // Enable docking if built with -Denable_docking=true.
    // Must be set before the first NewFrame() call.
    if (@import("zgui_options").enable_docking)
    {
        zgui.io.setConfigFlags(.{ .dock_enable = true });
    }

    zgui.plot.init();

    // set up style and load the font
    {
        const font_normal = zgui.io.addFontFromMemory(
            STATE.font_data,
            16,
        );
        zgui.io.setDefaultFont(font_normal);

        // You can directly manipulate zgui.Style *before* `newFrame()` call.
        // Once frame is started (after `newFrame()` call) you have to use
        // zgui.pushStyleColor*()/zgui.pushStyleVar*() functions.

        const style = zgui.getStyle();

        style.window_min_size = .{ 320.0, 240.0 };

        // example of setting the scrollbar parameters
        // style.window_border_size = 8.0;
        // style.scrollbar_size = 6.0;
        // {
        //     var color = style.getColor(.scrollbar_grab);
        //     color[1] = 0.8;
        //     style.setColor(.scrollbar_grab, color);
        // }

        // style.scaleAllSizes(scale_factor);

        // {
        //     zgui.plot.getStyle().line_weight = 3.0;
        //     const plot_style = zgui.plot.getStyle();
        //     plot_style.marker = .circle;
        //     plot_style.marker_size = 5.0;
        // }
    }

    if (STATE.app.maybe_post_zgui_init)
        |init_fn|
    {
        init_fn();
    }
}

export fn frame(
) void 
{
    // Pump sokol-fetch message queues
    sfetch.dowork();

    // call simgui.newFrame() before any ImGui calls
    simgui.newFrame(
        .{
            .width = sapp.width(),
            .height = sapp.height(),
            .delta_time = sapp.frameDuration(),
            .dpi_scale = sapp.dpiScale(),
        },
    );

    STATE.app.draw() catch |err| {
        std.log.err(">>> ERROR: {any}\n", .{err});
        std.process.exit(1);
    };

    sg.beginPass(
        .{
            .action = STATE.pass_action,
            .swapchain = sglue.swapchain(),
        },
    );

    if (STATE.app.maybe_pre_imgui_render)
        |pre_render|
    {
        pre_render();
    }

    simgui.render();
    sg.endPass();
    sg.commit();
}

/// Fetch resources from the webserver or from elsewhere.  returns a pointer to
/// a Query object, which has the state and data read from the file (if the
/// read was succesful).
///
/// Caller owns the memory of the FetchQuery
pub const fetch_resource = fetch.Query.init;
pub const FetchQuery = fetch.Query;

export fn cleanup(
) void 
{
    if (STATE.app.maybe_pre_zgui_shutdown_cleanup)
        |clean_fn|
    {
        clean_fn();
    }

    // Shutdown sokol-fetch
    sfetch.shutdown();

    simgui.shutdown();
    zgui.deinit();
    zplot.deinit();
    sg.shutdown();
}

/// handle keypresses
export fn event(
    ev: [*c]const sapp.Event,
) void 
{
    _ = simgui.handleEvent(ev.*);

    // Check if the key event is a key press, and if it is the Escape key 
    if (
        ev.*.type == .KEY_DOWN
        and ev.*.key_code == .ESCAPE
    ) 
    { 
        // Quit the application 
        sapp.quit();
    }
}

/// Logger function pointer type matching sokol's Logger.func signature.
pub const LogFn = *const fn (
    tag: [*c]const u8,
    log_level: u32,
    log_id: u32,
    message: [*c]const u8,
    line_nr: u32,
    filename: [*c]const u8,
    _: ?*anyopaque,
) callconv(.c) void;

const SokolApp = struct {
    /// where all your ui code should go (required)
    draw: *const fn () anyerror!void,

    // optional fields

    /// initial window title
    title: [:0]const u8 = "ZIIS Demo App",

    /// initial window dimensions
    dimensions: [2]i32 = .{ 800, 800 },

    // optional function pointers

    /// a function that gets called during cleanup (free a GPA, etc) before
    /// shutting down the graphics system
    maybe_pre_zgui_shutdown_cleanup: ?*const fn() void = null,

    /// optional function that is called once after zgui setup
    maybe_post_zgui_init: ?*const fn() void = null,

    /// optional callback invoked inside the render pass, before ImGui
    /// rendering.  Use this to inject custom sokol_gl/sokol_gfx drawing.
    maybe_pre_imgui_render: ?*const fn() void = null,

    /// event handler - for keyboard shortcuts.  Default only catches the
    /// escape key which quits the app
    event: *const fn (ev: [*c]const sapp.Event) callconv(.c) void = &event,

    max_vertices: i32 =  if (IS_WASM) 64 * 1024 else 256*1024*1024,

    /// Optional logging callback for sokol subsystems.  Off by default.
    /// Pass `ziis.std_log_scoped` to route sokol output through std.log.
    logger: ?LogFn = null,

    /// Enable drag-and-drop file handling.
    enable_dragndrop: bool = false,

    /// Maximum number of files accepted in a single drop.
    max_dropped_files: i32 = 1,

    /// Maximum path length (bytes) for each dropped file.
    max_dropped_file_path_length: i32 = 2048,
};

pub fn sokol_main(
    comptime app_in: SokolApp,
) void 
{
    STATE.app = app_in;

    // Setup sokol-fetch
    sfetch.setup(
        .{
            .max_requests = 8,
            .num_channels = 1,
            .num_lanes = 4,
            .logger = .{ .func = STATE.app.logger },
        },
    );

    sapp.run(
        .{
            .init_cb = init,
            .frame_cb = frame,
            .cleanup_cb = cleanup,
            .event_cb = STATE.app.event,
            .width = STATE.app.dimensions[0],
            .height = STATE.app.dimensions[1],
            .icon = .{ .sokol_default = true },
            .window_title = STATE.app.title,
            .enable_clipboard = true,
            .enable_dragndrop = STATE.app.enable_dragndrop,
            .max_dropped_files = STATE.app.max_dropped_files,
            .max_dropped_file_path_length = STATE.app.max_dropped_file_path_length,
            .html5 = .{
                .update_document_title = true,
            },
            .logger = .{ .func = STATE.app.logger },
        },
    );
}
