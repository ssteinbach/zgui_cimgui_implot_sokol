const std = @import("std");
const MeshulaLab = @import("MeshulaLab");
const ziis = @import("zgui_cimgui_implot_sokol");
const zgui = ziis.zgui;
const undo_journal = @import("undo_journal.zig");

// ---------------------------------------------------------------
// Activity-local state
// ---------------------------------------------------------------

pub const TEX_DIM: [2]i32 = .{ 256, 256 };
pub const COLOR_CHANNELS: usize = 4;
pub var tex: ziis.sokol.gfx.Image = .{};
pub var view: ziis.sokol.gfx.View = .{};
pub var texid: u64 = 0;
pub var frame_number: usize = 0;
pub var buffer = std.mem.zeroes(
    [TEX_DIM[0]][TEX_DIM[1]][COLOR_CHANNELS]u8,
);
pub var image_data = ziis.sokol.gfx.ImageData{};

pub fn initState() void
{
    tex = ziis.sokol.gfx.makeImage(
        .{
            .width = TEX_DIM[0],
            .height = TEX_DIM[1],
            .usage = .{ .stream_update = true },
            .pixel_format = .RGBA8,
        },
    );

    view = ziis.sokol.gfx.makeView(
        .{
            .texture = .{
                .image = tex,
            },
        },
    );

    texid = ziis.sokol.imgui.imtextureid(view);
}

/// Plugin lifecycle callback — wraps initState for the generic plugin template.
pub fn activate(
    _: ?*anyopaque,
) callconv(.c) void
{
    initState();
}

/// Per-frame texture buffer update — called by the orchestrator as
/// the Activity's Update callback.
pub fn update(
    _: ?*anyopaque,
    _: f32,
) callconv(.c) void
{
    frame_number = @intFromFloat(@abs(undo_journal.f));

    ziis.sokol.gfx.updateImage(
        tex,
        compute_image: {
            var x: usize = 0;
            const iw_m_one: f64 = @floatFromInt(TEX_DIM[0] - 1);
            const ih_m_one: f64 = @floatFromInt(TEX_DIM[1] - 1);
            while (x < TEX_DIM[0]) : (x += 1)
            {
                const fx: f64 = @floatFromInt(
                    @mod(x + frame_number, TEX_DIM[0]),
                );
                var y: usize = 0;
                while (y < TEX_DIM[1]) : (y += 1)
                {
                    const fy: f64 = @floatFromInt(
                        @mod(y + frame_number, TEX_DIM[1]),
                    );

                    const r = fx / iw_m_one;
                    const g = fy / ih_m_one;
                    const b: f64 = 0.0;

                    buffer[x][y][0] = @intFromFloat(
                        255.999 * r,
                    );
                    buffer[x][y][1] = @intFromFloat(
                        255.999 * g,
                    );
                    buffer[x][y][2] = @intFromFloat(
                        255.999 * b,
                    );
                    buffer[x][y][3] = 255;
                }
            }

            image_data.mip_levels[0] = ziis.sokol.gfx.asRange(
                &buffer,
            );

            break :compute_image image_data;
        },
    );
}

// ---------------------------------------------------------------
// RunUI
// ---------------------------------------------------------------

pub fn runUI(
    _: ?*anyopaque,
    _: ?*const MeshulaLab.ViewInteraction,
) callconv(.c) void
{
    const wsize = zgui.getWindowSize();

    ziis.cimgui.igImage(
        .{ ._TexID = texid },
        .{ .x = wsize[0], .y = wsize[1] },
    );
}
