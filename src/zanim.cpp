// This file was originally was licensed under the zgui license, see LICENSE.md
// All modifications and additions are copyright (c) 2025 Stephan Steinbach

#include "sokol_gfx.h"
#include "sokol_app.h"
#include "sokol_imgui.h"
#include "im_anim.h"

#ifndef ZGUI_API
#define ZGUI_API
#endif

//--------------------------------------------------------------------------------------------------
//
// ImAnim
//
//--------------------------------------------------------------------------------------------------
extern "C"
{
    ZGUI_API void zguiAnim_UpdateBeginFrame(void)
    {
        iam_update_begin_frame();
    }

    ZGUI_API void zguiAnim_ClipUpdate(float dt)
    {
        iam_clip_update(dt);
    }

    ZGUI_API void zguiAnim_GC(int max_age_frames)
    {
        iam_gc(max_age_frames);
    }

    ZGUI_API float zguiAnim_TweenFloat(
        ImGuiID id,
        int channel_id,
        float target,
        float duration,
        iam_ease_type ease,
        iam_policy policy,
        float dt)
    {
        iam_ease_desc ease_desc = iam_ease_preset(ease);
        return iam_tween_float(id, channel_id, target, duration, ease_desc, policy, dt);
    }

    ZGUI_API void zguiAnim_TweenVec2(
        ImGuiID id,
        int channel_id,
        const float target[2],
        float duration,
        iam_ease_type ease,
        iam_policy policy,
        float dt,
        float out[2])
    {
        iam_ease_desc ease_desc = iam_ease_preset(ease);
        ImVec2 result = iam_tween_vec2(id, channel_id, {target[0], target[1]}, duration, ease_desc, policy, dt);
        out[0] = result.x;
        out[1] = result.y;
    }

    ZGUI_API void zguiAnim_TweenVec4(
        ImGuiID id,
        int channel_id,
        const float target[4],
        float duration,
        iam_ease_type ease,
        iam_policy policy,
        float dt,
        float out[4])
    {
        iam_ease_desc ease_desc = iam_ease_preset(ease);
        ImVec4 result = iam_tween_vec4(id, channel_id, {target[0], target[1], target[2], target[3]}, duration, ease_desc, policy, dt);
        out[0] = result.x;
        out[1] = result.y;
        out[2] = result.z;
        out[3] = result.w;
    }

    ZGUI_API int zguiAnim_TweenInt(
        ImGuiID id,
        int channel_id,
        int target,
        float duration,
        iam_ease_type ease,
        iam_policy policy,
        float dt)
    {
        iam_ease_desc ease_desc = iam_ease_preset(ease);
        return iam_tween_int(id, channel_id, target, duration, ease_desc, policy, dt);
    }
}
