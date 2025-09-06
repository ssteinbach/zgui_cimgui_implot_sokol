//! Wrapper for an app using ZIIS - see app_wrapper_demo for an example

const std = @import("std");

const ziis = @import("root.zig");
const zgui = ziis.zgui;
const zplot = ziis.zgui.plot;
const sokol = ziis.sokol;
const sg = sokol.gfx;
const sapp = sokol.app;
const sglue = sokol.glue;
const simgui = sokol.imgui;

/// State container
const STATE = struct {
    var pass_action: sg.PassAction = .{};

    /// gets configured by sokol_main
    // SAFETY: gets configured by the main, which requires it as an argument
    var app: SokolApp = undefined;

    /// default font
    const font_data = @embedFile("content/Roboto-Medium.ttf");

    /// allocator for configuring imgui/sokol/etc.
    const allocator = std.heap.c_allocator;
};

export fn init(
) void 
{
    // initialize sokol-gfx
    sg.setup(
        .{
            .environment = sglue.environment(),
            .logger = .{ .func = sokol.log.func },
        },
    );

    // initialize sokol-imgui
    simgui.setup(
        .{
            .logger = .{ .func = sokol.log.func }, 
        },
    );

    // initial clear color
    STATE.pass_action.colors[0] = .{
        .load_action = .CLEAR,
        .clear_value = .{ .r = 0.0, .g = 0.5, .b = 1.0, .a = 1.0 },
    };

    zgui.init(STATE.allocator);
    zgui.plot.init();

    // set up style and load the font
    {
        // const scale_factor = sokol.app.dpiScale();
        //
        // const font_size = 16.0 * scale_factor;

        const font_normal = zgui.io.addFontFromMemory(
            STATE.font_data,
            16,
        );
        // std.debug.assert(zgui.io.getFont(1) == font_normal);
        zgui.io.setDefaultFont(font_normal);

        // You can directly manipulate zgui.Style *before* `newFrame()` call.
        // Once frame is started (after `newFrame()` call) you have to use
        // zgui.pushStyleColor*()/zgui.pushStyleVar*() functions.

        const style = zgui.getStyle();
        // style.child_border_size = 0;
        // style.docking_separator_size = 0;
        // style.child_rounding = 0;
        // style.popup_rounding = 0;
        // style.tab_rounding = 0;
        // style.window_rounding = 0;
        // style.grab_rounding = 0;
        // style.frame_rounding = 0;
        // style.scrollbar_rounding = 0;

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

        // To reset zgui.Style with default values:
        //zgui.getStyle().* = zgui.Style.init();

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
            .swapchain = sglue.swapchain()
        }
    );
    simgui.render();
    sg.endPass();
    sg.commit();
}

export fn cleanup(
) void 
{
    if (STATE.app.maybe_pre_zgui_shutdown_cleanup)
        |clean_fn|
    {
        clean_fn();
    }

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
    if (ev.*.type == .KEY_DOWN and ev.*.key_code == .ESCAPE) 
    { 
        // Quit the application 
        sapp.quit();
    }
}

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

    /// event handler - for keyboard shortcuts.  Default only catches the
    /// escape key which quits the app
    event: *const fn (ev: [*c]const sapp.Event) callconv(.c) void = &event,

};

pub fn sokol_main(
    comptime app_in: SokolApp,
) void 
{
    STATE.app = app_in;

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
            .logger = .{ .func = sokol.log.func },
            .win32_console_attach = true,
        },
    );
}
