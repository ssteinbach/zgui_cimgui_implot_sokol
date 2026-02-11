//! Sokol logging callback that routes output to std.log.
//!
//! Usage: pass `slog.func` as the logger in your SokolApp config:
//!
//!     app_wrapper.sokol_main(
//!         .{
//!             .draw = draw,
//!             .logger = slog.func,
//!         },
//!     );
//!
//! See app_wrapper_demo.zig for an example.

const std = @import("std");

const scoped_log = std.log.scoped(.sokol);

/// Logger callback compatible with sokol's Logger.func signature.
///
/// Routes sokol log messages to std.log at the appropriate level. Safe to call
/// from multiple threads.  Treats all string pointers as potentially null, per
/// sokol convention.
pub fn std_log_scoped(
    tag: [*c]const u8,
    log_level: u32,
    log_id: u32,
    message: [*c]const u8,
    line_nr: u32,
    filename: [*c]const u8,
    _: ?*anyopaque,
) callconv(.c) void
{
    const fmt_str =     "[{s}] {s}#{d} {s}:{d}: {s}";
    const values = .{
        if (tag) |t| std.mem.span(t) else "???",
        if (log_level == 0) "PANIC " else "",
        log_id,
        if (filename) |f| std.mem.span(f) else "???",
        line_nr,
        if (message) |m| std.mem.span(m) else "",
    };

    switch (log_level) {
        0,1 => scoped_log.err(fmt_str, values),
        2 => scoped_log.warn(fmt_str, values),
        3 => scoped_log.info(fmt_str, values),
        else => scoped_log.debug(fmt_str, values),
    }
}
