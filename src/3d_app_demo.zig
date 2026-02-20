//! 3D demo app — renders a grid of cubes via sokol_gl with an ImGui control
//! panel on the right side of the window.

const std = @import("std");
const builtin = @import("builtin");

const ziis = @import("zgui_cimgui_implot_sokol");
const zgui = ziis.zgui;

// ─── Constants ──────────────────────────────────────────────────────────────

const GRID_SIZE_DEFAULT: i32 = 10;
const CUBE_SIZE_DEFAULT: f32 = 1.0;
const SPACING_DEFAULT: f32 = 0.5;
const PANEL_WIDTH_FRACTION: f32 = 0.3;

const CAM_DISTANCE_DEFAULT: f32 = 25.0;
const CAM_DISTANCE_MIN: f32 = 5.0;
const CAM_DISTANCE_MAX: f32 = 80.0;
const CAM_ELEVATION_DEFAULT: f32 = 0.6;
const CAM_ELEVATION_MIN: f32 = -1.4;
const CAM_ELEVATION_MAX: f32 = 1.4;
const ROTATION_SPEED_DEFAULT: f32 = 30.0;

// ─── State ──────────────────────────────────────────────────────────────────

const STATE = struct
{
    var depth_pip: ziis.sokol.gl.Pipeline = .{};

    // grid parameters
    var grid_size: i32 = GRID_SIZE_DEFAULT;
    var cube_size: f32 = CUBE_SIZE_DEFAULT;
    var spacing: f32 = SPACING_DEFAULT;

    // camera
    var cam_orbit_angle: f32 = 0.4;
    var cam_elevation: f32 = CAM_ELEVATION_DEFAULT;
    var cam_distance: f32 = CAM_DISTANCE_DEFAULT;

    // mouse interaction
    var mouse_dragging: bool = false;
    var last_mouse_x: f32 = 0.0;
    var last_mouse_y: f32 = 0.0;

    // rotation
    var auto_rotate: bool = true;
    var rotation_speed: f32 = ROTATION_SPEED_DEFAULT;
    var rotation_angle: f32 = 0.0;
};

// ─── Cube Drawing ───────────────────────────────────────────────────────────

fn draw_cube(
    x: f32,
    y: f32,
    z: f32,
    size: f32,
) void
{
    const hs = size * 0.5;

    ziis.sokol.gl.beginQuads();

    // Top face (light gray-blue)
    ziis.sokol.gl.v3fC3f(x - hs, y + hs, z + hs, 0.7, 0.75, 0.85);
    ziis.sokol.gl.v3fC3f(x + hs, y + hs, z + hs, 0.7, 0.75, 0.85);
    ziis.sokol.gl.v3fC3f(x + hs, y + hs, z - hs, 0.7, 0.75, 0.85);
    ziis.sokol.gl.v3fC3f(x - hs, y + hs, z - hs, 0.7, 0.75, 0.85);

    // Bottom face (dark gray)
    ziis.sokol.gl.v3fC3f(x - hs, y - hs, z - hs, 0.3, 0.3, 0.35);
    ziis.sokol.gl.v3fC3f(x + hs, y - hs, z - hs, 0.3, 0.3, 0.35);
    ziis.sokol.gl.v3fC3f(x + hs, y - hs, z + hs, 0.3, 0.3, 0.35);
    ziis.sokol.gl.v3fC3f(x - hs, y - hs, z + hs, 0.3, 0.3, 0.35);

    // Front face (+Z, medium blue-gray)
    ziis.sokol.gl.v3fC3f(x - hs, y + hs, z + hs, 0.5, 0.55, 0.65);
    ziis.sokol.gl.v3fC3f(x - hs, y - hs, z + hs, 0.5, 0.55, 0.65);
    ziis.sokol.gl.v3fC3f(x + hs, y - hs, z + hs, 0.5, 0.55, 0.65);
    ziis.sokol.gl.v3fC3f(x + hs, y + hs, z + hs, 0.5, 0.55, 0.65);

    // Back face (-Z, medium gray)
    ziis.sokol.gl.v3fC3f(x + hs, y + hs, z - hs, 0.45, 0.48, 0.55);
    ziis.sokol.gl.v3fC3f(x + hs, y - hs, z - hs, 0.45, 0.48, 0.55);
    ziis.sokol.gl.v3fC3f(x - hs, y - hs, z - hs, 0.45, 0.48, 0.55);
    ziis.sokol.gl.v3fC3f(x - hs, y + hs, z - hs, 0.45, 0.48, 0.55);

    // Right face (+X, medium warm gray)
    ziis.sokol.gl.v3fC3f(x + hs, y + hs, z + hs, 0.55, 0.5, 0.55);
    ziis.sokol.gl.v3fC3f(x + hs, y - hs, z + hs, 0.55, 0.5, 0.55);
    ziis.sokol.gl.v3fC3f(x + hs, y - hs, z - hs, 0.55, 0.5, 0.55);
    ziis.sokol.gl.v3fC3f(x + hs, y + hs, z - hs, 0.55, 0.5, 0.55);

    // Left face (-X, medium cool gray)
    ziis.sokol.gl.v3fC3f(x - hs, y + hs, z - hs, 0.48, 0.52, 0.6);
    ziis.sokol.gl.v3fC3f(x - hs, y - hs, z - hs, 0.48, 0.52, 0.6);
    ziis.sokol.gl.v3fC3f(x - hs, y - hs, z + hs, 0.48, 0.52, 0.6);
    ziis.sokol.gl.v3fC3f(x - hs, y + hs, z + hs, 0.48, 0.52, 0.6);

    ziis.sokol.gl.end();
}

// ─── Grid Drawing ───────────────────────────────────────────────────────────

fn draw_grid() void
{
    const stride = STATE.cube_size + STATE.spacing;
    const gs: f32 = @floatFromInt(STATE.grid_size);
    const offset = (gs - 1.0) * stride * 0.5;

    var row: i32 = 0;
    while (row < STATE.grid_size)
        : (row += 1)
    {
        var col: i32 = 0;
        while (col < STATE.grid_size)
            : (col += 1)
        {
            const fx: f32 = @floatFromInt(col);
            const fz: f32 = @floatFromInt(row);
            draw_cube(
                fx * stride - offset,
                0.0,
                fz * stride - offset,
                STATE.cube_size,
            );
        }
    }
}

// ─── ImGui Control Panel ────────────────────────────────────────────────────

fn draw_imgui_panel() void
{
    const ww = ziis.sokol.app.widthf();
    const wh = ziis.sokol.app.heightf();
    const panel_width = ww * PANEL_WIDTH_FRACTION;
    const viewport_width = ww - panel_width;

    zgui.setNextWindowPos(.{ .x = viewport_width, .y = 0 });
    zgui.setNextWindowSize(.{ .w = panel_width, .h = wh });

    if (
        zgui.begin(
            "###3DControlPanel",
            .{
                .flags = .{
                    .no_resize = true,
                    .no_move = true,
                    .no_collapse = true,
                    .no_title_bar = true,
                },
            },
        )
    )
    {
        defer zgui.end();

        zgui.separatorText("Grid");
        _ = zgui.sliderInt(
            "Grid Size",
            .{ .v = &STATE.grid_size, .min = 1, .max = 20 },
        );
        _ = zgui.sliderFloat(
            "Cube Size",
            .{ .v = &STATE.cube_size, .min = 0.1, .max = 3.0 },
        );
        _ = zgui.sliderFloat(
            "Spacing",
            .{ .v = &STATE.spacing, .min = 0.0, .max = 2.0 },
        );

        zgui.separatorText("Camera");
        zgui.text(
            "Orbit: {d:.1} deg",
            .{std.math.radiansToDegrees(STATE.cam_orbit_angle)},
        );
        zgui.text(
            "Elevation: {d:.1} deg",
            .{std.math.radiansToDegrees(STATE.cam_elevation)},
        );
        _ = zgui.sliderFloat(
            "Distance",
            .{
                .v = &STATE.cam_distance,
                .min = CAM_DISTANCE_MIN,
                .max = CAM_DISTANCE_MAX,
            },
        );

        zgui.separatorText("Animation");
        _ = zgui.checkbox("Auto Rotate", .{ .v = &STATE.auto_rotate });
        _ = zgui.sliderFloat(
            "Speed (deg/s)",
            .{ .v = &STATE.rotation_speed, .min = 0.0, .max = 180.0 },
        );

        zgui.separatorText("Info");
        const dt = ziis.sokol.app.frameDuration();
        const fps: f32 = if (dt > 0.0)
            @floatCast(1.0 / dt)
        else
            0.0;
        zgui.text("FPS: {d:.0}", .{fps});

        const gs: i32 = STATE.grid_size;
        const total_cubes = gs * gs;
        const verts_per_cube: i32 = 24;
        zgui.text(
            "Cubes: {d}  Vertices: {d}",
            .{ total_cubes, total_cubes * verts_per_cube },
        );
    }
}

// ─── Main Draw Callback ─────────────────────────────────────────────────────

fn draw() !void
{
    const ww = ziis.sokol.app.widthf();
    const wh = ziis.sokol.app.heightf();
    const panel_width = ww * PANEL_WIDTH_FRACTION;
    const viewport_width = ww - panel_width;

    // Record sokol_gl commands for the 3D scene
    ziis.sokol.gl.defaults();
    ziis.sokol.gl.loadPipeline(STATE.depth_pip);

    ziis.sokol.gl.viewportf(0, 0, viewport_width, wh, true);
    ziis.sokol.gl.scissorRectf(0, 0, viewport_width, wh, true);

    // Projection
    const aspect = viewport_width / wh;
    ziis.sokol.gl.matrixModeProjection();
    ziis.sokol.gl.perspective(
        ziis.sokol.gl.asRadians(60.0),
        aspect,
        0.1,
        200.0,
    );

    // Camera (orbit)
    ziis.sokol.gl.matrixModeModelview();

    const cos_elev = @cos(STATE.cam_elevation);
    const sin_elev = @sin(STATE.cam_elevation);
    const cos_orbit = @cos(STATE.cam_orbit_angle);
    const sin_orbit = @sin(STATE.cam_orbit_angle);

    const eye_x = STATE.cam_distance * cos_elev * sin_orbit;
    const eye_y = STATE.cam_distance * sin_elev;
    const eye_z = STATE.cam_distance * cos_elev * cos_orbit;

    ziis.sokol.gl.lookat(
        eye_x, eye_y, eye_z,
        0.0, 0.0, 0.0,
        0.0, 1.0, 0.0,
    );

    // Apply auto-rotation around Y
    ziis.sokol.gl.rotate(
        ziis.sokol.gl.asRadians(STATE.rotation_angle),
        0.0,
        1.0,
        0.0,
    );

    draw_grid();

    // Update rotation
    if (STATE.auto_rotate)
    {
        const dt: f32 = @floatCast(ziis.sokol.app.frameDuration());
        STATE.rotation_angle += STATE.rotation_speed * dt;
        if (STATE.rotation_angle > 360.0)
        {
            STATE.rotation_angle -= 360.0;
        }
    }

    // Draw ImGui panel
    draw_imgui_panel();
}

// ─── Pre-render (inside render pass) ────────────────────────────────────────

fn pre_render() void
{
    ziis.sokol.gl.draw();
}

// ─── Init / Cleanup ─────────────────────────────────────────────────────────

fn init() void
{
    ziis.sokol.gl.setup(.{});

    STATE.depth_pip = ziis.sokol.gl.makePipeline(
        .{
            .depth = .{
                .write_enabled = true,
                .compare = .LESS,
            },
            .cull_mode = .BACK,
        },
    );
}

fn cleanup() void
{
    ziis.sokol.gl.destroyPipeline(STATE.depth_pip);
    ziis.sokol.gl.shutdown();
}

// ─── Event Handler ──────────────────────────────────────────────────────────

fn app_event(
    ev: [*c]const ziis.sokol.app.Event,
) callconv(.c) void
{
    // Always forward to ImGui
    _ = ziis.sokol.imgui.handleEvent(ev.*);

    // If ImGui wants the mouse, skip orbit/zoom handling
    if (zgui.io.getWantCaptureMouse())
    {
        return;
    }

    const event = ev.*;

    switch (event.type)
    {
        .MOUSE_DOWN =>
        {
            if (event.mouse_button == .LEFT)
            {
                STATE.mouse_dragging = true;
                STATE.last_mouse_x = event.mouse_x;
                STATE.last_mouse_y = event.mouse_y;
            }
        },
        .MOUSE_UP =>
        {
            if (event.mouse_button == .LEFT)
            {
                STATE.mouse_dragging = false;
            }
        },
        .MOUSE_MOVE =>
        {
            if (STATE.mouse_dragging)
            {
                const dx = event.mouse_x - STATE.last_mouse_x;
                const dy = event.mouse_y - STATE.last_mouse_y;
                STATE.last_mouse_x = event.mouse_x;
                STATE.last_mouse_y = event.mouse_y;

                STATE.cam_orbit_angle -= dx * 0.005;
                STATE.cam_elevation += dy * 0.005;
                STATE.cam_elevation = std.math.clamp(
                    STATE.cam_elevation,
                    CAM_ELEVATION_MIN,
                    CAM_ELEVATION_MAX,
                );
            }
        },
        .MOUSE_SCROLL =>
        {
            STATE.cam_distance -= event.scroll_y * 1.5;
            STATE.cam_distance = std.math.clamp(
                STATE.cam_distance,
                CAM_DISTANCE_MIN,
                CAM_DISTANCE_MAX,
            );
        },
        .KEY_DOWN =>
        {
            if (event.key_code == .ESCAPE)
            {
                ziis.sokol.app.quit();
            }
        },
        else => {},
    }
}

// ─── Entry Point ────────────────────────────────────────────────────────────

pub fn main() void
{
    ziis.app_wrapper.sokol_main(
        .{
            .draw = draw,
            .title = "ZIIS 3D Demo",
            .dimensions = .{ 1200, 800 },
            .maybe_post_zgui_init = init,
            .maybe_pre_zgui_shutdown_cleanup = cleanup,
            .maybe_pre_imgui_render = pre_render,
            .event = app_event,
        },
    );
}
