//! Small convienence layer around sokol.fetch
//!
//! See `Query` for more information.

const std = @import("std");

const sokol_fetch = @import("sokol").fetch;

/// Compression format for automatic decompression
pub const Compression = enum {
    /// No decompression (raw data)
    none,
    /// Gzip format (.gz files)
    gzip,
    /// Detect compression from file extension or magic bytes
    auto_detect,
};

/// Encapsulates a query for a resource, can work remotely or locally.
///
/// use .init() to initialize.
pub const Query = struct {
    /// Chunk size for streaming fetches (1MB)
    /// Note: This must be small enough to fit on the stack since init()
    /// returns Query by value. Default stack is typically 8MB.
    pub const CHUNK_SIZE: usize = 1 * 1024 * 1024;

    /// State of the fetch operation, loading, failed, etc.
    pub const State = enum {
        loading,
        loaded,
        failed,
    };

    // inputs
    ///////////////////////////////////////////////////////////////////////////

    /// Allocator for decompression buffer (needed for cleanup).  This uses a
    /// "managed" pattern because of the callback nature.
    allocator: std.mem.Allocator,

    /// Path that is being fetched
    target_path: [:0]const u8,

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
    handle: sokol_fetch.Handle,

    /// State of the query.
    state: State,

    /// Error details when state == .failed (null if no error or still
    /// loading)
    maybe_error: ?sokol_fetch.Error,

    ////////////////////////////////////////////////////////////////////////

    /// Alias for query callback functions
    pub const CallbackFn = (
        *const fn (*Query) error{CallbackError}!void
    );

    /// Get error code as string
    pub fn error_name(
        self: *const Query,
    ) []const u8
    {
        if (self.maybe_error)
            |err|
        {
            return @tagName(err);
        }
        return "";
    }

    /// Get human-readable error message
    pub fn error_message(
        self: *const Query,
    ) []const u8
    {
        if (self.maybe_error)
            |err|
        {
            return switch (err) {
                .NO_ERROR => "No error",
                .FILE_NOT_FOUND => "File not found or could not be opened",
                .NO_BUFFER => "No buffer provided for fetch",
                .BUFFER_TOO_SMALL => "Buffer too small for file content",
                .UNEXPECTED_EOF => "Unexpected end of file",
                .INVALID_HTTP_STATUS => (
                    "Invalid HTTP status (non-2xx "
                    ++ "response)"
                ),
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
        self: *Query,
        compressed_data: []const u8,
    ) ![]const u8
    {
        // Create a fixed reader from the compressed data
        var input_reader: std.Io.Reader = .fixed(compressed_data);

        // Create an allocating writer for the output
        var output_writer: std.Io.Writer.Allocating = .init(self.allocator);
        errdefer output_writer.deinit();

        // Initialize gzip decompressor
        var decomp: std.compress.flate.Decompress = .init(
            &input_reader,
            .gzip,
            &.{},
        );

        // Stream all decompressed data to the writer
        _ = decomp.reader.streamRemaining(&output_writer.writer)
            catch |err|
        {
            std.log.err("Gzip decompression error: {any}", .{err});
            if (decomp.err)
                |decomp_err|
            {
                std.log.err("Decompressor error: {any}", .{decomp_err});
            }
            return err;
        };

        const owned = try output_writer.toOwnedSlice();
        self.result_data_buffer = owned;
        return owned;
    }

    /// Initialize a new Query with the given allocator.  Memory of the
    /// query is owned by the caller.
    pub fn init(
        allocator: std.mem.Allocator,
        target_path: []const u8,
        options: struct{
            /// Optional callback that is called when fetch is done
            maybe_callback: ?Query.CallbackFn = null,
            /// Compression handling mode (default: none for backward
            /// compatibility)
            compression: Compression = .none,
        },
    ) !*Query
    {
        const new_query = try allocator.create(Query);
        new_query.* = .{
            // options
            .allocator = allocator,
            .target_path = try std.fmt.allocPrintSentinel(
                allocator,
                "{s}",
                .{target_path},
                '\x00',
            ),
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

        // Send streaming fetch request (chunk_size enables multi-callback
        // mode) 
        // Note: user_data will copies pointer value (8 bytes), not the whole
        // Query struct
        new_query.*.handle = sokol_fetch.send(
            .{
                .path = @ptrCast(new_query.target_path),
                .callback = streaming_callback,
                .buffer = .{
                    .ptr = &new_query.chunk_buffer,
                    .size = new_query.chunk_buffer.len,
                },
                .chunk_size = Query.CHUNK_SIZE,
                .user_data = .{
                    .ptr = @ptrCast(&new_query),
                    .size = @sizeOf(*Query),
                },
            },
        );

        return new_query;
    }

    /// Clean up allocated resources.
    pub fn deinit(
        self: *Query,
    ) void
    {
        self.allocator.free(self.target_path);
        self.allocator.free(self.result_data_buffer);
        self.raw_data_read_buffer.deinit(self.allocator);
    }
};

/// Extract a Query from a Sokol fetch response (useful in callbacks and
/// so on)
fn query_from_response(
    response: [*c]const sokol_fetch.Response,
) *Query
{
    return @as(
        *const *Query,
        @alignCast(@ptrCast(response.*.user_data.?))
    ).*;
}

/// Streaming callback - gets called multiple times as chunks arrive.
/// Accumulates data into the Query's raw_data_read_buffer
fn streaming_callback(
    response_ptr: [*c]const sokol_fetch.Response,
) callconv(.c) void
{
    const resp = response_ptr.*;
    var fetch_query = query_from_response(response_ptr);
    const allocator = fetch_query.allocator;

    // Handle errors
    if (resp.failed)
    {
        fetch_query.state = .failed;
        fetch_query.maybe_error = resp.error_code;

        std.log.err(
            "Fetch failed for '{s}': {s}",
            .{
                fetch_query.target_path,
                fetch_query.error_name(),
            },
        );

        // Call user callback on failure so completion trackers don't hang
        if (fetch_query.maybe_callback)
            |callback|
        {
            callback(fetch_query) catch {};
        }
        return;
    }

    // Append this chunk to accumulated data
    if (resp.data.size > 0)
    {
        const chunk_ptr: [*]const u8 = @ptrCast(resp.data.ptr);
        const chunk_data = chunk_ptr[0..resp.data.size];

        fetch_query.raw_data_read_buffer.appendSlice(
            allocator,
            chunk_data,
        ) catch
            |err|
        {
            std.log.err(
                "Failed to accumulate chunk data: {any}",
                .{err},
            );
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
        const should_decompress = switch (fetch_query.compression) {
            .none => false,
            .gzip => true,
            .auto_detect => blk: {
                if (Query.has_gzip_magic(raw_data))
                {
                    break :blk true;
                }
                if (resp.path != null)
                {
                    const path_slice = std.mem.span(resp.path);
                    break :blk Query.has_gzip_extension(path_slice);
                }
                break :blk false;
            },
        };

        if (should_decompress)
        {
            fetch_query.result_data_buffer = fetch_query.decompress_gzip(
                raw_data,
            ) catch
                |err|
            {
                std.log.err("Decompression failed: {any}", .{err});
                fetch_query.state = .failed;
                fetch_query.maybe_error = .JS_OTHER;
                return;
            };
        }
        else
        {
            // bring the raw data buffer into the result buffer
            fetch_query.result_data_buffer = (
                fetch_query.raw_data_read_buffer.toOwnedSlice(allocator)
                catch {
                    fetch_query.state = .failed;
                    return;
                }
            );
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
