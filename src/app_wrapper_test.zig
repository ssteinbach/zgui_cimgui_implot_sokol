//! Unit tests for app_wrapper fetch error handling
//!
//! These tests verify that:
//! 1. FetchQuery initializes with no error
//! 2. Error messages are correctly formatted for each error code
//! 3. Error paths are stored and retrieved correctly
//! 4. Helper methods handle null errors gracefully
//!
//! NOTE: This test file duplicates the error handling types and functions
//! from app_wrapper.zig to avoid pulling in GUI dependencies.

const std = @import("std");
const app_wrapper = @import("src/app_wrapper.zig");
const sfetch = @import("sokol").fetch;

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

/// Minimal FetchQuery for testing (mirrors app_wrapper.FetchQuery)
pub const FetchQuery = struct
{
    /// State of the query.
    state: FetchState,

    /// Error details when state == .failed (null if no error or still loading)
    maybe_error: ?FetchError,

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
        .state = .loading,
        .maybe_error = null,
    };
};

test "FetchQuery initializes without error"
{
    const query = FetchQuery.loading;
    try std.testing.expectEqual(FetchState.loading, query.state);
    try std.testing.expect(query.maybe_error == null);
}

test "getErrorCode returns tag name"
{
    var query = FetchQuery.loading;
    query.state = .failed;
    query.maybe_error = .{
        .error_code = .FILE_NOT_FOUND,
        .path = undefined,
        .path_len = 0,
    };

    try std.testing.expectEqualStrings(
        "FILE_NOT_FOUND",
        query.getErrorCode(),
    );
}

test "getErrorMessage returns correct strings for FILE_NOT_FOUND"
{
    var query = FetchQuery.loading;
    query.state = .failed;
    query.maybe_error = .{
        .error_code = .FILE_NOT_FOUND,
        .path = undefined,
        .path_len = 0,
    };

    try std.testing.expectEqualStrings(
        "File not found or could not be opened",
        query.getErrorMessage(),
    );
}

test "getErrorMessage returns correct strings for BUFFER_TOO_SMALL"
{
    var query = FetchQuery.loading;
    query.state = .failed;
    query.maybe_error = .{
        .error_code = .BUFFER_TOO_SMALL,
        .path = undefined,
        .path_len = 0,
    };

    try std.testing.expectEqualStrings(
        "Buffer too small for file content",
        query.getErrorMessage(),
    );
}

test "getErrorMessage returns correct strings for INVALID_HTTP_STATUS"
{
    var query = FetchQuery.loading;
    query.state = .failed;
    query.maybe_error = .{
        .error_code = .INVALID_HTTP_STATUS,
        .path = undefined,
        .path_len = 0,
    };

    try std.testing.expectEqualStrings(
        "Invalid HTTP status (non-2xx response)",
        query.getErrorMessage(),
    );
}

test "getErrorMessage returns correct strings for JS_OTHER"
{
    var query = FetchQuery.loading;
    query.state = .failed;
    query.maybe_error = .{
        .error_code = .JS_OTHER,
        .path = undefined,
        .path_len = 0,
    };

    try std.testing.expectEqualStrings(
        "JavaScript error (check browser console)",
        query.getErrorMessage(),
    );
}

test "getErrorPath returns stored path"
{
    var query = FetchQuery.loading;
    query.state = .failed;

    var error_info = FetchError{
        .error_code = .FILE_NOT_FOUND,
        .path = undefined,
        .path_len = 0,
    };
    const test_path = "example.json";
    @memcpy(error_info.path[0..test_path.len], test_path);
    error_info.path_len = test_path.len;
    query.maybe_error = error_info;

    try std.testing.expectEqualStrings(
        "example.json",
        query.getErrorPath(),
    );
}

test "getErrorPath handles longer paths"
{
    var query = FetchQuery.loading;
    query.state = .failed;

    var error_info = FetchError{
        .error_code = .FILE_NOT_FOUND,
        .path = undefined,
        .path_len = 0,
    };
    const test_path = "path/to/some/deeply/nested/directory/example.json";
    @memcpy(error_info.path[0..test_path.len], test_path);
    error_info.path_len = test_path.len;
    query.maybe_error = error_info;

    try std.testing.expectEqualStrings(
        test_path,
        query.getErrorPath(),
    );
}

test "helper methods handle null error gracefully"
{
    const query = FetchQuery.loading;

    try std.testing.expectEqualStrings("", query.getErrorCode());
    try std.testing.expectEqualStrings("", query.getErrorMessage());
    try std.testing.expectEqualStrings("", query.getErrorPath());
}

test "all error codes have non-empty messages"
{
    var query = FetchQuery.loading;
    query.state = .failed;

    const error_codes = [_]sfetch.Error{
        .NO_ERROR,
        .FILE_NOT_FOUND,
        .NO_BUFFER,
        .BUFFER_TOO_SMALL,
        .UNEXPECTED_EOF,
        .INVALID_HTTP_STATUS,
        .CANCELLED,
        .JS_OTHER,
    };

    for (error_codes)
        |code|
    {
        query.maybe_error = .{
            .error_code = code,
            .path = undefined,
            .path_len = 0,
        };
        const msg = query.getErrorMessage();
        try std.testing.expect(msg.len > 0);
    }
}

test "error codes return distinct messages"
{
    var query = FetchQuery.loading;
    query.state = .failed;

    query.maybe_error = .{
        .error_code = .FILE_NOT_FOUND,
        .path = undefined,
        .path_len = 0,
    };
    const file_not_found_msg = query.getErrorMessage();

    query.maybe_error = .{
        .error_code = .BUFFER_TOO_SMALL,
        .path = undefined,
        .path_len = 0,
    };
    const buffer_too_small_msg = query.getErrorMessage();

    // Messages should be different
    try std.testing.expect(
        !std.mem.eql(u8, file_not_found_msg, buffer_too_small_msg),
    );
}

test "empty path returns empty string"
{
    var query = FetchQuery.loading;
    query.state = .failed;

    query.maybe_error = .{
        .error_code = .FILE_NOT_FOUND,
        .path = undefined,
        .path_len = 0,
    };

    try std.testing.expectEqualStrings("", query.getErrorPath());
}

// ============================================================================
// Streaming/Accumulation Tests
// ============================================================================
// These tests verify the chunk accumulation logic used by the streaming fetch.

/// Simulates the streaming accumulation behavior from app_wrapper.zig
const StreamingAccumulator = struct
{
    accumulated_data: std.ArrayList(u8),
    allocator: std.mem.Allocator,

    pub fn init(
        alloc: std.mem.Allocator,
    ) StreamingAccumulator
    {
        return .{
            .accumulated_data = .empty,
            .allocator = alloc,
        };
    }

    pub fn deinit(
        self: *StreamingAccumulator,
    ) void
    {
        self.accumulated_data.deinit(self.allocator);
    }

    /// Append a chunk of data (simulates streaming callback)
    pub fn appendChunk(
        self: *StreamingAccumulator,
        chunk: []const u8,
    ) !void
    {
        try self.accumulated_data.appendSlice(self.allocator, chunk);
    }

    /// Get the accumulated data
    pub fn getData(
        self: *const StreamingAccumulator,
    ) []const u8
    {
        return self.accumulated_data.items;
    }
};

test "StreamingAccumulator initializes empty"
{
    var acc = StreamingAccumulator.init(std.testing.allocator);
    defer acc.deinit();

    try std.testing.expectEqual(@as(usize, 0), acc.getData().len);
}

test "StreamingAccumulator accumulates single chunk"
{
    var acc = StreamingAccumulator.init(std.testing.allocator);
    defer acc.deinit();

    const chunk = "Hello, World!";
    try acc.appendChunk(chunk);

    try std.testing.expectEqualStrings(chunk, acc.getData());
}

test "StreamingAccumulator accumulates multiple chunks"
{
    var acc = StreamingAccumulator.init(std.testing.allocator);
    defer acc.deinit();

    try acc.appendChunk("Hello, ");
    try acc.appendChunk("World");
    try acc.appendChunk("!");

    try std.testing.expectEqualStrings("Hello, World!", acc.getData());
}

test "StreamingAccumulator handles empty chunks"
{
    var acc = StreamingAccumulator.init(std.testing.allocator);
    defer acc.deinit();

    try acc.appendChunk("Start");
    try acc.appendChunk(""); // empty chunk
    try acc.appendChunk("End");

    try std.testing.expectEqualStrings("StartEnd", acc.getData());
}

test "StreamingAccumulator handles binary data"
{
    var acc = StreamingAccumulator.init(std.testing.allocator);
    defer acc.deinit();

    // Binary data with null bytes and high bytes
    const chunk1 = &[_]u8{ 0x00, 0x01, 0x02, 0xFF };
    const chunk2 = &[_]u8{ 0xFE, 0xFD, 0x00, 0x00 };

    try acc.appendChunk(chunk1);
    try acc.appendChunk(chunk2);

    const expected = &[_]u8{ 0x00, 0x01, 0x02, 0xFF, 0xFE, 0xFD, 0x00, 0x00 };
    try std.testing.expectEqualSlices(u8, expected, acc.getData());
}

test "StreamingAccumulator handles large accumulation"
{
    var acc = StreamingAccumulator.init(std.testing.allocator);
    defer acc.deinit();

    // Simulate many small chunks (like streaming a large file)
    const chunk = "0123456789ABCDEF"; // 16 bytes
    const num_chunks = 1000;

    for (0..num_chunks)
        |_|
    {
        try acc.appendChunk(chunk);
    }

    try std.testing.expectEqual(
        @as(usize, chunk.len * num_chunks),
        acc.getData().len,
    );

    // Verify first and last chunks are correct
    try std.testing.expectEqualStrings(
        chunk,
        acc.getData()[0..chunk.len],
    );
    try std.testing.expectEqualStrings(
        chunk,
        acc.getData()[acc.getData().len - chunk.len ..],
    );
}

test "StreamingAccumulator simulates realistic chunked fetch"
{
    var acc = StreamingAccumulator.init(std.testing.allocator);
    defer acc.deinit();

    // Simulate fetching a JSON file in chunks (like beans.json)
    const json_start = "{\"data\":[";
    const json_middle = "{\"value\":123},";
    const json_end = "{\"value\":456}]}";

    // First chunk: start of JSON
    try acc.appendChunk(json_start);
    try std.testing.expectEqual(@as(usize, json_start.len), acc.getData().len);

    // Middle chunks: array elements
    for (0..5)
        |_|
    {
        try acc.appendChunk(json_middle);
    }

    // Final chunk: end of JSON
    try acc.appendChunk(json_end);

    // Verify we have valid-looking JSON structure
    const data = acc.getData();
    try std.testing.expect(data[0] == '{');
    try std.testing.expect(data[data.len - 1] == '}');
    try std.testing.expect(std.mem.startsWith(u8, data, json_start));
    try std.testing.expect(std.mem.endsWith(u8, data, json_end));
}
