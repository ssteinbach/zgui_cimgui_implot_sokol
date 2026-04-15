//! Demo Studio app
//!
//! Activities and the studio configuration are discovered at runtime
//! from plugin shared libraries. This file just boots the
//! FundamentalApp and activates the "DemoStudio" studio by name.

const std = @import("std");

const ziis = @import("zgui_cimgui_implot_sokol");
const MeshulaLab = @import("MeshulaLabZig");

// =========================================================================
// FundamentalApp instance
// =========================================================================

var APP: MeshulaLab.FundamentalApp = undefined;

// =========================================================================
// Lifecycle callbacks
// =========================================================================

/// Called after zgui/sokol are initialised and plugin activities/studios
/// have been created+registered. Activate the DemoStudio.
fn post_init(
) void
{
    APP.activate_studio("DemoStudio");
}

// =========================================================================
// Entry point
// =========================================================================

pub fn main(
    init: std.process.Init,
) !void
{
    const allocator = init.gpa;
    const io = init.io;

    APP = MeshulaLab.FundamentalApp.init(
        allocator,
        io,
    );

    APP.run(
        .{
            .title = "ZIIS Demo Studio",
            .logger = ziis.std_log_scoped,
            .maybe_post_zgui_init = &post_init,
        },
    );
}
