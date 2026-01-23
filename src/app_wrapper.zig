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

/// Compression format for automatic decompression
pub const Compression = enum
{
    /// No decompression (raw data)
    none,
    /// Gzip format (.gz files)
    gzip,
    /// Detect compression from file extension or magic bytes
    auto_detect,
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
pub const FetchQuery = struct
{
    // @TODO: use a dynamic buffer allocation rather than a fixed size
    /// Buffer used for internal query stuff.
    buffer: [15 * 1024 * 1024]u8,

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

    /// Compression mode for automatic decompression
    compression: Compression,

    /// Allocator for decompression buffer (needed for cleanup)
    allocator: std.mem.Allocator,

    /// Buffer for decompressed data (null if no decompression occurred)
    decompressed_buffer: ?[]u8,

    /// Alias for query callback functions
    pub const CallbackFn = (
        *const fn (*FetchQuery) error{CallbackError}!void
    );

    /// Get error code as string
    pub fn get_error_name(
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
    pub fn get_error_path(
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

    /// Check if data has gzip magic bytes (0x1f 0x8b)
    pub fn has_gzip_magic(
        data: []const u8,
    ) bool
    {
        return data.len >= 2 and data[0] == 0x1f and data[1] == 0x8b;
    }

    /// Check if path ends with .gz extension
    pub fn has_gzip_extension(
        path: []const u8,
    ) bool
    {
        return std.mem.endsWith(u8, path, ".gz");
    }

    /// Decompress gzip data using std.compress.flate
    pub fn decompress_gzip(
        self: *FetchQuery,
        compressed_data: []const u8,
    ) ![]const u8
    {
        // Create an input reader from the compressed data
        var input_reader = std.Io.Reader.fixed(compressed_data);

        // Allocate window buffer for decompression (required by flate)
        const window_buffer = self.allocator.alloc(
            u8,
            std.compress.flate.max_window_len,
        ) catch
            |err|
        {
            std.log.err("Failed to allocate decompression window: {any}", .{err});
            return err;
        };
        defer self.allocator.free(window_buffer);

        // Initialize the decompressor
        var decomp = std.compress.flate.Decompress.init(
            &input_reader,
            .gzip,
            window_buffer,
        );

        // Allocate output buffer - start with 4x compressed size as estimate
        const initial_size = @max(compressed_data.len * 4, 4096);
        var output = std.ArrayList(u8).initCapacity(
            self.allocator,
            initial_size,
        ) catch
            |err|
        {
            std.log.err("Failed to allocate output buffer: {any}", .{err});
            return err;
        };
        errdefer output.deinit(self.allocator);

        // Read decompressed data in chunks
        var chunk_buf: [4096]u8 = undefined;
        while (true)
        {
            // Use the reader's buffered method to get data
            const buffered = decomp.reader.buffered();
            if (buffered.len > 0)
            {
                output.appendSlice(self.allocator, buffered) catch
                    |err|
                {
                    std.log.err("Failed to append decompressed data: {any}", .{err});
                    return err;
                };
                decomp.reader.toss(buffered.len);
            }
            else
            {
                // Try to fill buffer
                var writer = std.Io.Writer.fixed(&chunk_buf);
                const n = decomp.reader.stream(
                    &writer,
                    .limited(chunk_buf.len),
                ) catch
                    |err|
                {
                    // EndOfStream means we're done
                    if (err == error.EndOfStream)
                    {
                        break;
                    }
                    std.log.err("Decompression stream error: {any}", .{err});
                    return err;
                };

                if (n == 0)
                {
                    break;
                }

                output.appendSlice(self.allocator, chunk_buf[0..n]) catch
                    |err|
                {
                    std.log.err("Failed to append chunk: {any}", .{err});
                    return err;
                };
            }
        }

        const owned = output.toOwnedSlice(self.allocator) catch
            |err|
        {
            std.log.err("Failed to finalize output: {any}", .{err});
            return err;
        };
        self.decompressed_buffer = owned;
        return owned;
    }

    /// Free decompressed buffer if allocated
    pub fn free_decompressed_buffer(
        self: *FetchQuery,
    ) void
    {
        if (self.decompressed_buffer)
            |buf|
        {
            self.allocator.free(buf);
            self.decompressed_buffer = null;
        }
    }

    /// Default configuration for when data is to be loaded.
    pub const loading = FetchQuery{
        .buffer = undefined,
        .handle = .{},
        .state = .loading,
        .maybe_callback = null,
        .data = undefined,
        .maybe_error = null,
        .compression = .none,
        .allocator = undefined,
        .decompressed_buffer = null,
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
    const raw_data = @as([*]const u8, @ptrCast(resp.data.ptr))[0..resp.data.size];

    std.debug.print("unpacking callback...\n", .{});

    if (resp.failed == true or resp.fetched != true)
    {
        fetch_query.state = .failed;

        // Capture error details
        var error_info = FetchError{
            .error_code = resp.error_code,
            .path = undefined,
            .path_len = 0,
        };

        std.debug.print("buffer size: {d}\n", .{fetch_query.buffer.len});

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
            fetch_query.get_error_path(),
            fetch_query.get_error_name(),
        });
        return;
    }


    // Handle decompression based on compression mode
    const should_decompress = switch (fetch_query.compression)
    {
        .none => blk: {
            std.debug.print("Not decompressing in sokol fetch\n", .{});
            break :blk false;
        },
        .gzip => true,
        .auto_detect => blk: {
            // Check magic bytes first, then fall back to extension
            if (FetchQuery.has_gzip_magic(raw_data))
            {
                break :blk true;
            }
            if (resp.path != null)
            {
                const path_slice = std.mem.span(resp.path);
                break :blk FetchQuery.has_gzip_extension(path_slice);
            }
            break :blk false;
        },
    };

    if (should_decompress)
    {
        fetch_query.data = fetch_query.decompress_gzip(raw_data) catch
            |err|
        {
            std.log.err("Decompression failed: {any}", .{err});
            fetch_query.state = .failed;

            // Set up error info for decompression failure
            var error_info = FetchError{
                .error_code = .JS_OTHER, // Reuse as generic error
                .path = undefined,
                .path_len = 0,
            };
            if (resp.path != null)
            {
                const path_slice = std.mem.span(resp.path);
                const copy_len = @min(path_slice.len, error_info.path.len);
                @memcpy(error_info.path[0..copy_len], path_slice[0..copy_len]);
                error_info.path_len = copy_len;
            }
            fetch_query.maybe_error = error_info;
            return;
        };
    }
    else
    {
        fetch_query.data = raw_data;
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

/// Options for fetching resources
pub const FetchOptions = struct
{
    /// Path to the resource to load
    path: [:0]const u8,
    /// Optional callback that is called when fetch is done
    maybe_callback: ?FetchQuery.CallbackFn = null,
    /// Compression handling mode (default: none for backward compatibility)
    compression: Compression = .none,
};

/// Fetch resources from the webserver or from elsewhere.  returns a pointer to
/// a FetchQuery object, which has the state and data read from the file (if
/// the read was succesful).
///
/// Caller owns the memory of the FetchQuery
pub fn fetch_resource(
    allocator: std.mem.Allocator,
    options: FetchOptions,
) !*FetchQuery
{
    const new_query = try allocator.create(FetchQuery);
    new_query.* = .loading;
    new_query.maybe_callback = options.maybe_callback;
    new_query.compression = options.compression;
    new_query.allocator = allocator;
    new_query.decompressed_buffer = null;

    // Send fetch request
    // Note: user_data will copy the pointer value itself (8 bytes), not the
    // whole FetchQuery struct
    new_query.*.handle = sfetch.send(
        .{
            .path = options.path,
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

/// Fetch resources from the webserver or from elsewhere.  returns a pointer to
/// a FetchQuery object, which has the state and data read from the file (if
/// the read was succesful).
///
/// Caller owns the memory of the FetchQuery
///
/// Note: For gzip support, use `fetch_resource` with `FetchOptions` instead.
pub fn fetch_resource_from_path(
    allocator: std.mem.Allocator,
    /// Path to the resource to load.
    path: [:0]const u8,
    /// optional callback that is called when fetch is done
    maybe_callback: ?FetchQuery.CallbackFn,
    /// whether or not to handle the gzipping on the sokol side
    compression: Compression,
) !*FetchQuery
{
    return fetch_resource(
        allocator,
        .{
            .path = path,
            .maybe_callback = maybe_callback,
            .compression = compression,
        },
    );
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
