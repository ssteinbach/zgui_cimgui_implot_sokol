// This file was originally was licensed under the zgui license, see LICENSE.md
// All modifications and additions are copyright (c) 2025 Stephan Steinbach

//--------------------------------------------------------------------------------------------------
const gui = @import("gui.zig");
//--------------------------------------------------------------------------------------------------
// Core frame update functions
//--------------------------------------------------------------------------------------------------
/// Must be called once per frame after ImGui::NewFrame()
pub const updateBeginFrame = zguiAnim_UpdateBeginFrame;
extern fn zguiAnim_UpdateBeginFrame() void;

/// Updates clip-based animations each frame
pub const clipUpdate = zguiAnim_ClipUpdate;
extern fn zguiAnim_ClipUpdate(dt: f32) void;

/// Garbage collection for stale animation entries
pub const gc = zguiAnim_GC;
extern fn zguiAnim_GC(max_age_frames: i32) void;

//--------------------------------------------------------------------------------------------------
// Enums
//--------------------------------------------------------------------------------------------------
pub const EaseType = enum(i32) {
    linear = 0,
    in_quad = 1,
    out_quad = 2,
    in_out_quad = 3,
    in_cubic = 4,
    out_cubic = 5,
    in_out_cubic = 6,
    in_sine = 7,
    out_sine = 8,
    in_out_sine = 9,
};

pub const Policy = enum(i32) {
    crossfade = 0,
    cut = 1,
    queue = 2,
};

//--------------------------------------------------------------------------------------------------
// Tween functions
//--------------------------------------------------------------------------------------------------
pub const TweenFloat = struct {
    id: gui.Ident,
    channel_id: i32 = 0,
    target: f32,
    duration: f32 = 0.3,
    ease: EaseType = .out_cubic,
    policy: Policy = .crossfade,
    dt: f32,
};

pub fn tweenFloat(args: TweenFloat) f32 {
    return zguiAnim_TweenFloat(
        args.id,
        args.channel_id,
        args.target,
        args.duration,
        args.ease,
        args.policy,
        args.dt,
    );
}
extern fn zguiAnim_TweenFloat(
    id: gui.Ident,
    channel_id: i32,
    target: f32,
    duration: f32,
    ease: EaseType,
    policy: Policy,
    dt: f32,
) f32;

pub const TweenVec2 = struct {
    id: gui.Ident,
    channel_id: i32 = 0,
    target: [2]f32,
    duration: f32 = 0.3,
    ease: EaseType = .out_cubic,
    policy: Policy = .crossfade,
    dt: f32,
};

pub fn tweenVec2(args: TweenVec2) [2]f32 {
    var result: [2]f32 = undefined;
    zguiAnim_TweenVec2(
        args.id,
        args.channel_id,
        &args.target,
        args.duration,
        args.ease,
        args.policy,
        args.dt,
        &result,
    );
    return result;
}
extern fn zguiAnim_TweenVec2(
    id: gui.Ident,
    channel_id: i32,
    target: *const [2]f32,
    duration: f32,
    ease: EaseType,
    policy: Policy,
    dt: f32,
    out: *[2]f32,
) void;

pub const TweenVec4 = struct {
    id: gui.Ident,
    channel_id: i32 = 0,
    target: [4]f32,
    duration: f32 = 0.3,
    ease: EaseType = .out_cubic,
    policy: Policy = .crossfade,
    dt: f32,
};

pub fn tweenVec4(args: TweenVec4) [4]f32 {
    var result: [4]f32 = undefined;
    zguiAnim_TweenVec4(
        args.id,
        args.channel_id,
        &args.target,
        args.duration,
        args.ease,
        args.policy,
        args.dt,
        &result,
    );
    return result;
}
extern fn zguiAnim_TweenVec4(
    id: gui.Ident,
    channel_id: i32,
    target: *const [4]f32,
    duration: f32,
    ease: EaseType,
    policy: Policy,
    dt: f32,
    out: *[4]f32,
) void;

pub const TweenInt = struct {
    id: gui.Ident,
    channel_id: i32 = 0,
    target: i32,
    duration: f32 = 0.3,
    ease: EaseType = .out_cubic,
    policy: Policy = .crossfade,
    dt: f32,
};

pub fn tweenInt(args: TweenInt) i32 {
    return zguiAnim_TweenInt(
        args.id,
        args.channel_id,
        args.target,
        args.duration,
        args.ease,
        args.policy,
        args.dt,
    );
}
extern fn zguiAnim_TweenInt(
    id: gui.Ident,
    channel_id: i32,
    target: i32,
    duration: f32,
    ease: EaseType,
    policy: Policy,
    dt: f32,
) i32;

//--------------------------------------------------------------------------------------------------
// Demo and Inspector Windows
//--------------------------------------------------------------------------------------------------
/// Show comprehensive demo window with all ImAnim features
pub const showDemoWindow = zguiAnim_ShowDemoWindow;
extern fn zguiAnim_ShowDemoWindow() void;

/// Show unified inspector (debug window + animation inspector)
pub const showUnifiedInspector = zguiAnim_ShowUnifiedInspector;
extern fn zguiAnim_ShowUnifiedInspector(p_open: ?*bool) void;
