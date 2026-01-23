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
const sfetch = ziis.sokol.fetch;

/// building with wasm?
const IS_WASM = builtin.target.cpu.arch.isWasm();

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
            // max out the vertex buffer... might be overkill
            .max_vertices = STATE.app.max_vertices,
            .logger = .{ .func = sokol.log.func }, 
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

    zgui.init(STATE.allocator);
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
        }
    );

    simgui.render();
    sg.endPass();
    sg.commit();
}

//@{ fetch code

/// State of the fetch operation, loading, failed, etc.
pub const FetchState = enum
{
    loading,
    loaded,
    failed,
};

/// Details about a fetch error
pub const FetchError = struct
{
    /// Error code from sokol-fetch
    error_code: sfetch.Error,
    /// Path that was requested (up to 256 chars)
    path: [256]u8,
    /// Length of valid path bytes
    path_len: usize,
};

/// Encapsulates a query for a resource, can work remotely or locally
pub const FetchQuery = struct {
    // @TODO: use a dynamic buffer allocation rather than a fixed size
    /// Buffer used for internal query stuff.
    buffer: [10 * 1024 * 1024]u8,

    /// Handle to sokol.fetch query.
    handle: sfetch.Handle,

    /// State of the query.
    state: FetchState,

    /// Optional callback to call when fetch is complete.
    maybe_callback: ?CallbackFn,

    /// Data read from the target.
    data: []const u8,

    /// Error details when state == .failed (null if no error or still loading)
    maybe_error: ?FetchError,

    /// Alias for query callback functions
    pub const CallbackFn = (
        *const fn (*FetchQuery) error{CallbackError}!void
    );

    /// Get error code as string
    pub fn getErrorCode(
        self: *const FetchQuery,
    ) []const u8
    {
        if (self.maybe_error)
            |err|
        {
            return @tagName(err.error_code);
        }
        return "";
    }

    /// Get human-readable error message
    pub fn getErrorMessage(
        self: *const FetchQuery,
    ) []const u8
    {
        if (self.maybe_error)
            |err|
        {
            return switch (err.error_code)
            {
                .NO_ERROR => "No error",
                .FILE_NOT_FOUND => "File not found or could not be opened",
                .NO_BUFFER => "No buffer provided for fetch",
                .BUFFER_TOO_SMALL => "Buffer too small for file content",
                .UNEXPECTED_EOF => "Unexpected end of file",
                .INVALID_HTTP_STATUS => "Invalid HTTP status (non-2xx response)",
                .CANCELLED => "Fetch was cancelled",
                .JS_OTHER => "JavaScript error (check browser console)",
            };
        }
        return "";
    }

    /// Get the path that failed
    pub fn getErrorPath(
        self: *const FetchQuery,
    ) []const u8
    {
        if (self.maybe_error)
            |*err|
        {
            return err.path[0..err.path_len];
        }
        return "";
    }

    /// Default configuration for when data is to be loaded.
    pub const loading = FetchQuery{
        .buffer = undefined,
        .handle = .{},
        .state = .loading,
        .maybe_callback = null,
        .data = undefined,
        .maybe_error = null,
    };
};

/// Extract a FetchQuery from a Sokol fetch response (useful in callbacks and
/// so on)
fn query_from_response(
    response: [*c]const sfetch.Response,
) *FetchQuery
{
    return @as(
        *const *FetchQuery,
        @alignCast(@ptrCast(response.*.user_data.?))
    ).*;
}

/// Wraps the user callback for a more ergonomic zig-interface.
fn unpack_callback(
    /// fetch response
    response: [*c]const sfetch.Response,
) callconv(.c) void
{
    const resp = response.*;
    var fetch_query = query_from_response(response);
    fetch_query.data = (
        @as([*]const u8, @ptrCast(resp.data.ptr))[0..resp.data.size]
     );

    if (resp.failed == true or resp.fetched != true)
    {
        fetch_query.state = .failed;

        // Capture error details
        var error_info = FetchError{
            .error_code = resp.error_code,
            .path = undefined,
            .path_len = 0,
        };

        // Copy path if available
        if (resp.path != null)
        {
            const path_slice = std.mem.span(resp.path);
            const copy_len = @min(path_slice.len, error_info.path.len);
            @memcpy(error_info.path[0..copy_len], path_slice[0..copy_len]);
            error_info.path_len = copy_len;
        }

        fetch_query.maybe_error = error_info;

        std.log.err("Fetch failed for '{s}': {s}", .{
            fetch_query.getErrorPath(),
            fetch_query.getErrorCode(),
        });
        return;
    }

    if (fetch_query.maybe_callback)
        |callback|
    {
        callback(fetch_query) catch {
            fetch_query.state = .failed;
            return;
        };
    }

    fetch_query.state = .loaded;
}

/// Fetch resources from the webserver or from elsewhere.  returns a pointer to
/// a FetchQuery object, which has the state and data read from the file (if
/// the read was succesful)..
///
/// Caller owns the memory of the FetchQuery
pub fn fetch_resource_from_path(
    allocator: std.mem.Allocator,
    /// Path to the resource to load.
    path: []const u8,
    /// optional callback that is called when fetch is done
    maybe_callback: ?FetchQuery.CallbackFn,
) !*FetchQuery
{
    const new_query = try allocator.create(FetchQuery);
    new_query.* = .loading;
    new_query.maybe_callback = maybe_callback;

    // Send fetch request for example.json
    // Note: user_data will copy the pointer value itself (8 bytes), not the whole FetchQuery struct
    new_query.*.handle = sfetch.send(
        .{
            .path = @ptrCast(path),
            .callback = unpack_callback,
            .buffer = .{
                .ptr = &new_query.buffer,
                .size = new_query.buffer.len,
            },
            .user_data = .{
                .ptr = @ptrCast(&new_query),
                .size = @sizeOf(*FetchQuery),
            },
        }
    );

    return new_query;
}
//@}

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

    max_vertices: i32 =  if (IS_WASM) 64 * 1024 else 1024 * 1024,
};

pub fn sokol_main(
    comptime app_in: SokolApp,
) void 
{
    STATE.app = app_in;

    // Setup sokol-fetch
    sfetch.setup(
        .{
            // @TODO: experiment with these settings
            .max_requests = 4,
            .num_channels = 1,
            .num_lanes = 2,
        }
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
            .logger = .{ .func = sokol.log.func },
            .win32_console_attach = true,
        },
    );
}
