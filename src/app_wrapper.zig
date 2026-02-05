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
pub const FetchQuery = struct {
    /// Chunk size for streaming fetches (1MB)
    /// Note: This must be small enough to fit on the stack since init()
    /// returns FetchQuery by value. Default stack is typically 8MB.
    pub const CHUNK_SIZE: usize = 1 * 1024 * 1024;

    // inputs
    ///////////////////////////////////////////////////////////////////////////

    /// Allocator for decompression buffer (needed for cleanup).  This uses a
    /// "managed" pattern because of the callback nature.
    allocator: std.mem.Allocator,

    /// Path that is being fetched
    target_path: []const u8,

    /// Optional callback to call when fetch is complete.
    maybe_callback: ?CallbackFn,

    /// Compression mode for automatic decompression
    compression: Compression,

    /// Whether or not to log anything about this query.
    log: bool = false,

    // Buffers
    ///////////////////////////////////////////////////////////////////////////

    // The chunk buffer is used to read chunks of the target resource
    // The read chunks are moved from the chunk buffer to the accumulated_data
    // buffer.  When the accumulated_data buffer is full, then the data pointer
    // points at accumulated_data.items.  If there is compression, the data
    // is decompressed and stored in decompressed_buffer.

    /// Fixed buffer for sokol-fetch to write chunks into.
    chunk_buffer: [CHUNK_SIZE]u8,

    /// Dynamic buffer that accumulates all fetched data.
    raw_data_read_buffer: std.ArrayList(u8),

    /// Resulting data.  If no compression, will point at the raw_data_buffer.
    /// Otherwise, will contain the decompressed data.
    result_data_buffer: []const u8 = &.{},

    // Internal State
    ///////////////////////////////////////////////////////////////////////////

    /// Handle to sokol.fetch query.
    handle: sfetch.Handle,

    /// State of the query.
    state: FetchState,

    /// Error details when state == .failed (null if no error or still loading)
    maybe_error: ?FetchError,

    ////////////////////////////////////////////////////////////////////////

    /// Alias for query callback functions
    pub const CallbackFn = (
        *const fn (*FetchQuery) error{CallbackError}!void
    );

    /// Get error code as string
    pub fn error_name(
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
    pub fn error_message(
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

    /// Check if data has gzip magic bytes (0x1f 0x8b)
    fn has_gzip_magic(
        data: []const u8,
    ) bool
    {
        return data.len >= 2 and data[0] == 0x1f and data[1] == 0x8b;
    }

    /// Check if path ends with .gz extension
    fn has_gzip_extension(
        path: []const u8,
    ) bool
    {
        return std.mem.endsWith(u8, path, ".gz");
    }

    /// Decompress gzip data using std.compress.flate
    fn decompress_gzip(
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
        self.result_data_buffer = owned;
        return owned;
    }

    pub const InitOptions = struct{
        /// Optional callback that is called when fetch is done
        maybe_callback: ?FetchQuery.CallbackFn = null,
        /// Compression handling mode (default: none for backward compatibility)
        compression: Compression = .none,
    };

    /// Initialize a new FetchQuery with the given allocator.  Memory of the
    /// query is owned by the caller.
    pub fn init(
        allocator: std.mem.Allocator,
        target_path: [:0]const u8,
        options: InitOptions,
    ) !*FetchQuery
    {
        const new_query = try allocator.create(FetchQuery);
        new_query.* = .{
            // options
            .allocator = allocator,
            .target_path = target_path,
            .maybe_callback = options.maybe_callback,
            .compression = options.compression,

            // buffers
            .chunk_buffer = undefined,
            .raw_data_read_buffer = .empty,
            .result_data_buffer = &.{},

            // state
            .state = .loading,
            .maybe_error = null,
            .handle = .{},
        };

        // Send fetch request with streaming (chunk_size enables multi-callback mode)
        // Note: user_data will copy the pointer value itself (8 bytes), not the
        // whole FetchQuery struct
        new_query.*.handle = sfetch.send(
            .{
                .path = target_path,
                .callback = streaming_callback,
                .buffer = .{
                    .ptr = &new_query.chunk_buffer,
                    .size = new_query.chunk_buffer.len,
                },
                .chunk_size = FetchQuery.CHUNK_SIZE,
                .user_data = .{
                    .ptr = @ptrCast(&new_query),
                    .size = @sizeOf(*FetchQuery),
                },
            }
        );

        return new_query;
    }

    /// Clean up allocated resources.
    pub fn deinit(
        self: *FetchQuery,
    ) void
    {
        // if the result data buffer does not point at the raw data buffer
        if (self.result_data_buffer.ptr != self.raw_data_read_buffer.items.ptr)
        {
            self.allocator.free(self.result_data_buffer);

        }
        self.raw_data_read_buffer.deinit(self.allocator);
    }
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

/// Streaming callback - gets called multiple times as chunks arrive.
/// Accumulates data into the FetchQuery's raw_data_read_buffer
fn streaming_callback(
    response_ptr: [*c]const sfetch.Response,
) callconv(.c) void
{
    const resp = response_ptr.*;
    var fetch_query = query_from_response(response_ptr);
    const allocator = fetch_query.allocator;

    // Handle errors
    if (resp.failed)
    {
        fetch_query.state = .failed;

        var error_info = FetchError{
            .error_code = resp.error_code,
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
        if (fetch_query.log)
        {
            std.log.err(
                "Fetch failed for '{s}': {s}",
                .{
                    fetch_query.target_path,
                    fetch_query.error_name(),
                }
            );
        }
        return;
    }

    // Append this chunk to accumulated data
    if (resp.data.size > 0)
    {
        const chunk_data = @as([*]const u8, @ptrCast(resp.data.ptr))[0..resp.data.size];
        fetch_query.raw_data_read_buffer.appendSlice(
            allocator,
            chunk_data
        ) catch
            |err|
        {
            std.log.err("Failed to accumulate chunk data: {any}", .{err});
            fetch_query.state = .failed;
            return;
        };
    }

    // Check if this is the final chunk
    if (resp.finished)
    {
        const raw_data = fetch_query.raw_data_read_buffer.items;
        if (fetch_query.log)
        {
            std.log.info(
                "Fetch complete: {d} bytes total",
                .{raw_data.len},
            );
        }

        // Handle decompression based on compression mode
        const should_decompress = switch (fetch_query.compression)
        {
            .none => false,
            .gzip => true,
            .auto_detect => blk: {
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
            fetch_query.result_data_buffer = fetch_query.decompress_gzip(raw_data) catch
                |err|
            {
                std.log.err("Decompression failed: {any}", .{err});
                fetch_query.state = .failed;

                var error_info = FetchError{
                    .error_code = .JS_OTHER,
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
            fetch_query.result_data_buffer = raw_data;
        }

        // Call user callback if provided
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
/// Uses streaming with a fixed chunk buffer (1MB) and dynamically grows an
/// accumulation buffer as data arrives. This allows fetching files of any size
/// without pre-allocating a huge buffer.
///
/// Caller owns the memory of the FetchQuery
pub fn fetch_resource(
    allocator: std.mem.Allocator,
    options: FetchOptions,
) !*FetchQuery
{
    return try FetchQuery.init(
        allocator,
        options.path,
        .{
            .compression = options.compression,
            .maybe_callback = options.maybe_callback,
        },
    );
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
            .html5_update_document_title = true,
            .logger = .{ .func = sokol.log.func },
            .win32_console_attach = true,
        },
    );
}
