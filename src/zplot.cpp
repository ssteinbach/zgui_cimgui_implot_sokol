// This file was originally was licensed under the zgui license, see LICENSE.md
// All modifications and additions are copyright (c) 2025 Stephan Steinbach

#include "sokol_gfx.h"
#include "sokol_app.h"
#include "sokol_imgui.h"
#include "implot.h"

#ifndef ZGUI_API
#define ZGUI_API
#endif

static ImPlotSpec makeSpec(
    int flags,
    int offset,
    int stride,
    float fill_alpha,
    const float line_color[4],
    float line_weight,
    const float fill_color[4],
    int marker,
    float marker_size,
    const float marker_line_color[4],
    const float marker_fill_color[4],
    float size)
{
    ImPlotSpec spec;
    spec.Flags = flags;
    spec.Offset = offset;
    spec.Stride = stride;
    spec.FillAlpha = fill_alpha;
    spec.LineColor = {line_color[0], line_color[1], line_color[2], line_color[3]};
    spec.LineWeight = line_weight;
    spec.FillColor = {fill_color[0], fill_color[1], fill_color[2], fill_color[3]};
    spec.Marker = marker;
    spec.MarkerSize = marker_size;
    spec.MarkerLineColor = {marker_line_color[0], marker_line_color[1], marker_line_color[2], marker_line_color[3]};
    spec.MarkerFillColor = {marker_fill_color[0], marker_fill_color[1], marker_fill_color[2], marker_fill_color[3]};
    spec.Size = size;
    return spec;
}

//--------------------------------------------------------------------------------------------------
//
// ImPlot
//
//--------------------------------------------------------------------------------------------------
extern "C"
{
    ZGUI_API ImPlotContext *zguiPlot_CreateContext(void)
    {
        return ImPlot::CreateContext();
    }

    ZGUI_API void zguiPlot_DestroyContext(ImPlotContext *ctx)
    {
        ImPlot::DestroyContext(ctx);
    }

    ZGUI_API ImPlotContext *zguiPlot_GetCurrentContext(void)
    {
        return ImPlot::GetCurrentContext();
    }

    ZGUI_API void zguiPlotStyle_Init(ImPlotStyle *out)
    {
        *out = ImPlotStyle();
    }

    ZGUI_API ImPlotStyle *zguiPlot_GetStyle(void)
    {
        return &ImPlot::GetStyle();
    }

    ZGUI_API void zguiPlot_PushStyleColor4f(ImPlotCol idx, const float col[4])
    {
        ImPlot::PushStyleColor(idx, {col[0], col[1], col[2], col[3]});
    }

    ZGUI_API void zguiPlot_PushStyleColor1u(ImPlotCol idx, ImU32 col)
    {
        ImPlot::PushStyleColor(idx, col);
    }

    ZGUI_API void zguiPlot_PopStyleColor(int count)
    {
        ImPlot::PopStyleColor(count);
    }

    ZGUI_API void zguiPlot_PushStyleVar1i(ImPlotStyleVar idx, int var)
    {
        ImPlot::PushStyleVar(idx, var);
    }

    ZGUI_API void zguiPlot_PushStyleVar1f(ImPlotStyleVar idx, float var)
    {
        ImPlot::PushStyleVar(idx, var);
    }

    ZGUI_API void zguiPlot_PushStyleVar2f(ImPlotStyleVar idx, const float var[2])
    {
        ImPlot::PushStyleVar(idx, {var[0], var[1]});
    }

    ZGUI_API void zguiPlot_PopStyleVar(int count)
    {
        ImPlot::PopStyleVar(count);
    }

    ZGUI_API void zguiPlot_SetupLegend(ImPlotLocation location, ImPlotLegendFlags flags)
    {
        ImPlot::SetupLegend(location, flags);
    }

    ZGUI_API void zguiPlot_SetupAxis(ImAxis axis, const char *label, ImPlotAxisFlags flags)
    {
        ImPlot::SetupAxis(axis, label, flags);
    }

    ZGUI_API void zguiPlot_SetupAxisLimits(ImAxis axis, double v_min, double v_max, ImPlotCond cond)
    {
        ImPlot::SetupAxisLimits(axis, v_min, v_max, cond);
    }

    ZGUI_API void zguiPlot_SetupFinish(void)
    {
        ImPlot::SetupFinish();
    }

    ZGUI_API void zguiPlot_SetAxis(ImAxis axis)
    {
        ImPlot::SetAxis(axis);
    }

    ZGUI_API bool zguiPlot_BeginPlot(const char *title_id, float width, float height, ImPlotFlags flags)
    {
        return ImPlot::BeginPlot(title_id, {width, height}, flags);
    }

    ZGUI_API void zguiPlot_PlotLineValues(
        const char *label_id,
        ImGuiDataType data_type,
        const void *values,
        int count,
        double xscale,
        double x0,
        ImPlotLineFlags flags,
        int offset,
        int stride,
        float fill_alpha,
        const float line_color[4],
        float line_weight,
        const float fill_color[4],
        int marker,
        float marker_size,
        const float marker_line_color[4],
        const float marker_fill_color[4],
        float size)
    {
        const ImPlotSpec spec = makeSpec(flags, offset, stride, fill_alpha, line_color, line_weight, fill_color, marker, marker_size, marker_line_color, marker_fill_color, size);
        if (data_type == ImGuiDataType_S8)
            ImPlot::PlotLine(label_id, (const ImS8 *)values, count, xscale, x0, spec);
        else if (data_type == ImGuiDataType_U8)
            ImPlot::PlotLine(label_id, (const ImU8 *)values, count, xscale, x0, spec);
        else if (data_type == ImGuiDataType_S16)
            ImPlot::PlotLine(label_id, (const ImS16 *)values, count, xscale, x0, spec);
        else if (data_type == ImGuiDataType_U16)
            ImPlot::PlotLine(label_id, (const ImU16 *)values, count, xscale, x0, spec);
        else if (data_type == ImGuiDataType_S32)
            ImPlot::PlotLine(label_id, (const ImS32 *)values, count, xscale, x0, spec);
        else if (data_type == ImGuiDataType_U32)
            ImPlot::PlotLine(label_id, (const ImU32 *)values, count, xscale, x0, spec);
        else if (data_type == ImGuiDataType_Float)
            ImPlot::PlotLine(label_id, (const float *)values, count, xscale, x0, spec);
        else if (data_type == ImGuiDataType_Double)
            ImPlot::PlotLine(label_id, (const double *)values, count, xscale, x0, spec);
        else
            assert(false);
    }

    ZGUI_API void zguiPlot_PlotLine(
        const char *label_id,
        ImGuiDataType data_type,
        const void *xv,
        const void *yv,
        int count,
        ImPlotLineFlags flags,
        int offset,
        int stride,
        float fill_alpha,
        const float line_color[4],
        float line_weight,
        const float fill_color[4],
        int marker,
        float marker_size,
        const float marker_line_color[4],
        const float marker_fill_color[4],
        float size)
    {
        const ImPlotSpec spec = makeSpec(flags, offset, stride, fill_alpha, line_color, line_weight, fill_color, marker, marker_size, marker_line_color, marker_fill_color, size);
        if (data_type == ImGuiDataType_S8)
            ImPlot::PlotLine(label_id, (const ImS8 *)xv, (const ImS8 *)yv, count, spec);
        else if (data_type == ImGuiDataType_U8)
            ImPlot::PlotLine(label_id, (const ImU8 *)xv, (const ImU8 *)yv, count, spec);
        else if (data_type == ImGuiDataType_S16)
            ImPlot::PlotLine(label_id, (const ImS16 *)xv, (const ImS16 *)yv, count, spec);
        else if (data_type == ImGuiDataType_U16)
            ImPlot::PlotLine(label_id, (const ImU16 *)xv, (const ImU16 *)yv, count, spec);
        else if (data_type == ImGuiDataType_S32)
            ImPlot::PlotLine(label_id, (const ImS32 *)xv, (const ImS32 *)yv, count, spec);
        else if (data_type == ImGuiDataType_U32)
            ImPlot::PlotLine(label_id, (const ImU32 *)xv, (const ImU32 *)yv, count, spec);
        else if (data_type == ImGuiDataType_Float)
            ImPlot::PlotLine(label_id, (const float *)xv, (const float *)yv, count, spec);
        else if (data_type == ImGuiDataType_Double)
            ImPlot::PlotLine(label_id, (const double *)xv, (const double *)yv, count, spec);
        else
            assert(false);
    }

    ZGUI_API void zguiPlot_PlotScatter(
        const char *label_id,
        ImGuiDataType data_type,
        const void *xv,
        const void *yv,
        int count,
        ImPlotScatterFlags flags,
        int offset,
        int stride,
        float fill_alpha,
        const float line_color[4],
        float line_weight,
        const float fill_color[4],
        int marker,
        float marker_size,
        const float marker_line_color[4],
        const float marker_fill_color[4],
        float size)
    {
        const ImPlotSpec spec = makeSpec(flags, offset, stride, fill_alpha, line_color, line_weight, fill_color, marker, marker_size, marker_line_color, marker_fill_color, size);
        if (data_type == ImGuiDataType_S8)
            ImPlot::PlotScatter(label_id, (const ImS8 *)xv, (const ImS8 *)yv, count, spec);
        else if (data_type == ImGuiDataType_U8)
            ImPlot::PlotScatter(label_id, (const ImU8 *)xv, (const ImU8 *)yv, count, spec);
        else if (data_type == ImGuiDataType_S16)
            ImPlot::PlotScatter(label_id, (const ImS16 *)xv, (const ImS16 *)yv, count, spec);
        else if (data_type == ImGuiDataType_U16)
            ImPlot::PlotScatter(label_id, (const ImU16 *)xv, (const ImU16 *)yv, count, spec);
        else if (data_type == ImGuiDataType_S32)
            ImPlot::PlotScatter(label_id, (const ImS32 *)xv, (const ImS32 *)yv, count, spec);
        else if (data_type == ImGuiDataType_U32)
            ImPlot::PlotScatter(label_id, (const ImU32 *)xv, (const ImU32 *)yv, count, spec);
        else if (data_type == ImGuiDataType_Float)
            ImPlot::PlotScatter(label_id, (const float *)xv, (const float *)yv, count, spec);
        else if (data_type == ImGuiDataType_Double)
            ImPlot::PlotScatter(label_id, (const double *)xv, (const double *)yv, count, spec);
        else
            assert(false);
    }

    ZGUI_API void zguiPlot_PlotScatterValues(
        const char *label_id,
        ImGuiDataType data_type,
        const void *values,
        int count,
        double xscale,
        double x0,
        ImPlotScatterFlags flags,
        int offset,
        int stride,
        float fill_alpha,
        const float line_color[4],
        float line_weight,
        const float fill_color[4],
        int marker,
        float marker_size,
        const float marker_line_color[4],
        const float marker_fill_color[4],
        float size)
    {
        const ImPlotSpec spec = makeSpec(flags, offset, stride, fill_alpha, line_color, line_weight, fill_color, marker, marker_size, marker_line_color, marker_fill_color, size);
        if (data_type == ImGuiDataType_S8)
            ImPlot::PlotScatter(label_id, (const ImS8 *)values, count, xscale, x0, spec);
        else if (data_type == ImGuiDataType_U8)
            ImPlot::PlotScatter(label_id, (const ImU8 *)values, count, xscale, x0, spec);
        else if (data_type == ImGuiDataType_S16)
            ImPlot::PlotScatter(label_id, (const ImS16 *)values, count, xscale, x0, spec);
        else if (data_type == ImGuiDataType_U16)
            ImPlot::PlotScatter(label_id, (const ImU16 *)values, count, xscale, x0, spec);
        else if (data_type == ImGuiDataType_S32)
            ImPlot::PlotScatter(label_id, (const ImS32 *)values, count, xscale, x0, spec);
        else if (data_type == ImGuiDataType_U32)
            ImPlot::PlotScatter(label_id, (const ImU32 *)values, count, xscale, x0, spec);
        else if (data_type == ImGuiDataType_Float)
            ImPlot::PlotScatter(label_id, (const float *)values, count, xscale, x0, spec);
        else if (data_type == ImGuiDataType_Double)
            ImPlot::PlotScatter(label_id, (const double *)values, count, xscale, x0, spec);
        else
            assert(false);
    }

    ZGUI_API void zguiPlot_PlotStairsValues(
        const char *label_id,
        ImGuiDataType data_type,
        const void *values,
        int count,
        double xscale,
        double x0,
        ImPlotStairsFlags flags,
        int offset,
        int stride,
        float fill_alpha,
        const float line_color[4],
        float line_weight,
        const float fill_color[4],
        int marker,
        float marker_size,
        const float marker_line_color[4],
        const float marker_fill_color[4],
        float size)
    {
        const ImPlotSpec spec = makeSpec(flags, offset, stride, fill_alpha, line_color, line_weight, fill_color, marker, marker_size, marker_line_color, marker_fill_color, size);
        if (data_type == ImGuiDataType_S8)
            ImPlot::PlotStairs(label_id, (const ImS8 *)values, count, xscale, x0, spec);
        else if (data_type == ImGuiDataType_U8)
            ImPlot::PlotStairs(label_id, (const ImU8 *)values, count, xscale, x0, spec);
        else if (data_type == ImGuiDataType_S16)
            ImPlot::PlotStairs(label_id, (const ImS16 *)values, count, xscale, x0, spec);
        else if (data_type == ImGuiDataType_U16)
            ImPlot::PlotStairs(label_id, (const ImU16 *)values, count, xscale, x0, spec);
        else if (data_type == ImGuiDataType_S32)
            ImPlot::PlotStairs(label_id, (const ImS32 *)values, count, xscale, x0, spec);
        else if (data_type == ImGuiDataType_U32)
            ImPlot::PlotStairs(label_id, (const ImU32 *)values, count, xscale, x0, spec);
        else if (data_type == ImGuiDataType_Float)
            ImPlot::PlotStairs(label_id, (const float *)values, count, xscale, x0, spec);
        else if (data_type == ImGuiDataType_Double)
            ImPlot::PlotStairs(label_id, (const double *)values, count, xscale, x0, spec);
        else
            assert(false);
    }

    ZGUI_API void zguiPlot_PlotStairs(
        const char *label_id,
        ImGuiDataType data_type,
        const void *xv,
        const void *yv,
        int count,
        ImPlotStairsFlags flags,
        int offset,
        int stride,
        float fill_alpha,
        const float line_color[4],
        float line_weight,
        const float fill_color[4],
        int marker,
        float marker_size,
        const float marker_line_color[4],
        const float marker_fill_color[4],
        float size)
    {
        const ImPlotSpec spec = makeSpec(flags, offset, stride, fill_alpha, line_color, line_weight, fill_color, marker, marker_size, marker_line_color, marker_fill_color, size);
        if (data_type == ImGuiDataType_S8)
            ImPlot::PlotStairs(label_id, (const ImS8 *)xv, (const ImS8 *)yv, count, spec);
        else if (data_type == ImGuiDataType_U8)
            ImPlot::PlotStairs(label_id, (const ImU8 *)xv, (const ImU8 *)yv, count, spec);
        else if (data_type == ImGuiDataType_S16)
            ImPlot::PlotStairs(label_id, (const ImS16 *)xv, (const ImS16 *)yv, count, spec);
        else if (data_type == ImGuiDataType_U16)
            ImPlot::PlotStairs(label_id, (const ImU16 *)xv, (const ImU16 *)yv, count, spec);
        else if (data_type == ImGuiDataType_S32)
            ImPlot::PlotStairs(label_id, (const ImS32 *)xv, (const ImS32 *)yv, count, spec);
        else if (data_type == ImGuiDataType_U32)
            ImPlot::PlotStairs(label_id, (const ImU32 *)xv, (const ImU32 *)yv, count, spec);
        else if (data_type == ImGuiDataType_Float)
            ImPlot::PlotStairs(label_id, (const float *)xv, (const float *)yv, count, spec);
        else if (data_type == ImGuiDataType_Double)
            ImPlot::PlotStairs(label_id, (const double *)xv, (const double *)yv, count, spec);
        else
            assert(false);
    }

    ZGUI_API void zguiPlot_PlotShaded(
        const char *label_id,
        ImGuiDataType data_type,
        const void *xv,
        const void *yv,
        int count,
        double yref,
        ImPlotShadedFlags flags,
        int offset,
        int stride,
        float fill_alpha,
        const float line_color[4],
        float line_weight,
        const float fill_color[4],
        int marker,
        float marker_size,
        const float marker_line_color[4],
        const float marker_fill_color[4],
        float size)
    {
        const ImPlotSpec spec = makeSpec(flags, offset, stride, fill_alpha, line_color, line_weight, fill_color, marker, marker_size, marker_line_color, marker_fill_color, size);
        if (data_type == ImGuiDataType_S8)
            ImPlot::PlotShaded(label_id, (const ImS8 *)xv, (const ImS8 *)yv, count, yref, spec);
        else if (data_type == ImGuiDataType_U8)
            ImPlot::PlotShaded(label_id, (const ImU8 *)xv, (const ImU8 *)yv, count, yref, spec);
        else if (data_type == ImGuiDataType_S16)
            ImPlot::PlotShaded(label_id, (const ImS16 *)xv, (const ImS16 *)yv, count, yref, spec);
        else if (data_type == ImGuiDataType_U16)
            ImPlot::PlotShaded(label_id, (const ImU16 *)xv, (const ImU16 *)yv, count, yref, spec);
        else if (data_type == ImGuiDataType_S32)
            ImPlot::PlotShaded(label_id, (const ImS32 *)xv, (const ImS32 *)yv, count, yref, spec);
        else if (data_type == ImGuiDataType_U32)
            ImPlot::PlotShaded(label_id, (const ImU32 *)xv, (const ImU32 *)yv, count, yref, spec);
        else if (data_type == ImGuiDataType_Float)
            ImPlot::PlotShaded(label_id, (const float *)xv, (const float *)yv, count, yref, spec);
        else if (data_type == ImGuiDataType_Double)
            ImPlot::PlotShaded(label_id, (const double *)xv, (const double *)yv, count, yref, spec);
        else
            assert(false);
    }
    ZGUI_API void zguiPlot_PlotBars(
        const char *label_id,
        ImGuiDataType data_type,
        const void *xv,
        const void *yv,
        int count,
        double bar_size,
        ImPlotBarsFlags flags,
        int offset,
        int stride,
        float fill_alpha,
        const float line_color[4],
        float line_weight,
        const float fill_color[4],
        int marker,
        float marker_size,
        const float marker_line_color[4],
        const float marker_fill_color[4],
        float size)
    {
        const ImPlotSpec spec = makeSpec(flags, offset, stride, fill_alpha, line_color, line_weight, fill_color, marker, marker_size, marker_line_color, marker_fill_color, size);
        if (data_type == ImGuiDataType_S8)
            ImPlot::PlotBars(label_id, (const ImS8 *)xv, (const ImS8 *)yv, count, bar_size, spec);
        else if (data_type == ImGuiDataType_U8)
            ImPlot::PlotBars(label_id, (const ImU8 *)xv, (const ImU8 *)yv, count, bar_size, spec);
        else if (data_type == ImGuiDataType_S16)
            ImPlot::PlotBars(label_id, (const ImS16 *)xv, (const ImS16 *)yv, count, bar_size, spec);
        else if (data_type == ImGuiDataType_U16)
            ImPlot::PlotBars(label_id, (const ImU16 *)xv, (const ImU16 *)yv, count, bar_size, spec);
        else if (data_type == ImGuiDataType_S32)
            ImPlot::PlotBars(label_id, (const ImS32 *)xv, (const ImS32 *)yv, count, bar_size, spec);
        else if (data_type == ImGuiDataType_U32)
            ImPlot::PlotBars(label_id, (const ImU32 *)xv, (const ImU32 *)yv, count, bar_size, spec);
        else if (data_type == ImGuiDataType_Float)
            ImPlot::PlotBars(label_id, (const float *)xv, (const float *)yv, count, bar_size, spec);
        else if (data_type == ImGuiDataType_Double)
            ImPlot::PlotBars(label_id, (const double *)xv, (const double *)yv, count, bar_size, spec);
        else
            assert(false);
    }

    ZGUI_API void zguiPlot_PlotBarsValues(
        const char *label_id,
        ImGuiDataType data_type,
        const void *values,
        int count,
        double bar_size,
        double shift,
        ImPlotBarsFlags flags,
        int offset,
        int stride,
        float fill_alpha,
        const float line_color[4],
        float line_weight,
        const float fill_color[4],
        int marker,
        float marker_size,
        const float marker_line_color[4],
        const float marker_fill_color[4],
        float size)
    {
        const ImPlotSpec spec = makeSpec(flags, offset, stride, fill_alpha, line_color, line_weight, fill_color, marker, marker_size, marker_line_color, marker_fill_color, size);
        if (data_type == ImGuiDataType_S8)
            ImPlot::PlotBars(label_id, (const ImS8 *)values, count, bar_size, shift, spec);
        else if (data_type == ImGuiDataType_U8)
            ImPlot::PlotBars(label_id, (const ImU8 *)values, count, bar_size, shift, spec);
        else if (data_type == ImGuiDataType_S16)
            ImPlot::PlotBars(label_id, (const ImS16 *)values, count, bar_size, shift, spec);
        else if (data_type == ImGuiDataType_U16)
            ImPlot::PlotBars(label_id, (const ImU16 *)values, count, bar_size, shift, spec);
        else if (data_type == ImGuiDataType_S32)
            ImPlot::PlotBars(label_id, (const ImS32 *)values, count, bar_size, shift, spec);
        else if (data_type == ImGuiDataType_U32)
            ImPlot::PlotBars(label_id, (const ImU32 *)values, count, bar_size, shift, spec);
        else if (data_type == ImGuiDataType_Float)
            ImPlot::PlotBars(label_id, (const float *)values, count, bar_size, shift, spec);
        else if (data_type == ImGuiDataType_Double)
            ImPlot::PlotBars(label_id, (const double *)values, count, bar_size, shift, spec);
        else
            assert(false);
    }

    ZGUI_API bool zguiPlot_IsPlotHovered()
    {
        return ImPlot::IsPlotHovered();
    }
    ZGUI_API void zguiPlot_GetLastItemColor(float color[4])
    {
        const ImVec4 col = ImPlot::GetLastItemColor();
        color[0] = col.x;
        color[1] = col.y;
        color[2] = col.z;
        color[3] = col.w;
    }

    ZGUI_API void zguiPlot_ShowDemoWindow(bool *p_open)
    {
        ImPlot::ShowDemoWindow(p_open);
    }

    ZGUI_API void zguiPlot_EndPlot(void)
    {
        ImPlot::EndPlot();
    }

    ZGUI_API bool zguiPlot_DragPoint(
        int id,
        double *x,
        double *y,
        float col[4],
        float size,
        ImPlotDragToolFlags flags)
    {
        return ImPlot::DragPoint(
            id,
            x,
            y,
            (*(const ImVec4 *)&(col[0])),
            size,
            flags);
    }

    ZGUI_API void zguiPlot_TagX(double x, float col[4], bool round)
    {
        ImPlot::TagX(x, (*(const ImVec4 *)&(col[0])), round);
    }

    ZGUI_API void zguiPlot_TagXText(double x, float col[4], const char *fmt, ...)
    {
        va_list args;
        va_start(args, fmt);
        ImPlot::TagXV(x, (*(const ImVec4 *)&(col[0])), fmt, args);
        va_end(args);
    }

    ZGUI_API void zguiPlot_TagY(double y, float col[4], bool round)
    {
        ImPlot::TagY(y, (*(const ImVec4 *)&(col[0])), round);
    }

    ZGUI_API void zguiPlot_TagYText(double y, float col[4], const char *fmt, ...)
    {
        va_list args;
        va_start(args, fmt);
        ImPlot::TagYV(y, (*(const ImVec4 *)&(col[0])), fmt, args);
        va_end(args);
    }

    ZGUI_API void zguiPlot_PlotText(
        const char *text,
        double x, double y,
        const float pix_offset[2],
        ImPlotTextFlags flags = 0)
    {
        const ImVec2 p(pix_offset[0], pix_offset[1]);
        ImPlotSpec spec;
        spec.Flags = flags;
        ImPlot::PlotText(text, x, y, p, spec);
    }

    ZGUI_API void zguiPlot_GetPlotLimits(
            ImAxis x_Idx,
            ImAxis y_Idx,
            double* retval)
    {
        const ImPlotRect result = ImPlot::GetPlotLimits(x_Idx, y_Idx);
        retval[0] = result.X.Min;
        retval[1] = result.X.Max;
        retval[2] = result.Y.Min;
        retval[3] = result.Y.Max;
    }

    ZGUI_API void zguiPlot_PlotInfLines(
        const char *label_id,
        ImGuiDataType data_type,
        const void *values,
        int count,
        ImPlotInfLinesFlags flags,
        int offset,
        int stride,
        float fill_alpha,
        const float line_color[4],
        float line_weight,
        const float fill_color[4],
        int marker,
        float marker_size,
        const float marker_line_color[4],
        const float marker_fill_color[4],
        float size)
    {
        const ImPlotSpec spec = makeSpec(flags, offset, stride, fill_alpha, line_color, line_weight, fill_color, marker, marker_size, marker_line_color, marker_fill_color, size);
        if (data_type == ImGuiDataType_S8)
            ImPlot::PlotInfLines(label_id, (const ImS8 *)values, count, spec);
        else if (data_type == ImGuiDataType_U8)
            ImPlot::PlotInfLines(label_id, (const ImU8 *)values, count, spec);
        else if (data_type == ImGuiDataType_S16)
            ImPlot::PlotInfLines(label_id, (const ImS16 *)values, count, spec);
        else if (data_type == ImGuiDataType_U16)
            ImPlot::PlotInfLines(label_id, (const ImU16 *)values, count, spec);
        else if (data_type == ImGuiDataType_S32)
            ImPlot::PlotInfLines(label_id, (const ImS32 *)values, count, spec);
        else if (data_type == ImGuiDataType_U32)
            ImPlot::PlotInfLines(label_id, (const ImU32 *)values, count, spec);
        else if (data_type == ImGuiDataType_Float)
            ImPlot::PlotInfLines(label_id, (const float *)values, count, spec);
        else if (data_type == ImGuiDataType_Double)
            ImPlot::PlotInfLines(label_id, (const double *)values, count, spec);
        else
            assert(false);
    }

    ZGUI_API void zguiPlot_PlotPieChart(
        const char **label_ids,
        ImGuiDataType data_type,
        const void *values,
        int count,
        double x,
        double y,
        double radius,
        const char *label_fmt,
        double angle0,
        ImPlotPieChartFlags flags)
    {
        ImPlotSpec spec;
        spec.Flags = flags;
        if (data_type == ImGuiDataType_S8)
            ImPlot::PlotPieChart(label_ids, (const ImS8 *)values, count, x, y, radius, label_fmt, angle0, spec);
        else if (data_type == ImGuiDataType_U8)
            ImPlot::PlotPieChart(label_ids, (const ImU8 *)values, count, x, y, radius, label_fmt, angle0, spec);
        else if (data_type == ImGuiDataType_S16)
            ImPlot::PlotPieChart(label_ids, (const ImS16 *)values, count, x, y, radius, label_fmt, angle0, spec);
        else if (data_type == ImGuiDataType_U16)
            ImPlot::PlotPieChart(label_ids, (const ImU16 *)values, count, x, y, radius, label_fmt, angle0, spec);
        else if (data_type == ImGuiDataType_S32)
            ImPlot::PlotPieChart(label_ids, (const ImS32 *)values, count, x, y, radius, label_fmt, angle0, spec);
        else if (data_type == ImGuiDataType_U32)
            ImPlot::PlotPieChart(label_ids, (const ImU32 *)values, count, x, y, radius, label_fmt, angle0, spec);
        else if (data_type == ImGuiDataType_Float)
            ImPlot::PlotPieChart(label_ids, (const float *)values, count, x, y, radius, label_fmt, angle0, spec);
        else if (data_type == ImGuiDataType_Double)
            ImPlot::PlotPieChart(label_ids, (const double *)values, count, x, y, radius, label_fmt, angle0, spec);
        else
            assert(false);
    }

    ZGUI_API bool zguiPlot_BeginLegendPopup(const char *label_id, int mouse_button)
    {
        return ImPlot::BeginLegendPopup(label_id, mouse_button);
    }

    ZGUI_API void zguiPlot_EndLegendPopup()
    {
        ImPlot::EndLegendPopup();
    }

    ZGUI_API void zguiPlot_GetPlotMousePos(double *x, double *y, int x_axis, int y_axis)
    {
        ImPlotPoint pos = ImPlot::GetPlotMousePos(x_axis, y_axis);
        *x = pos.x;
        *y = pos.y;
    }

    ZGUI_API void zguiPlot_PlotToPixels(double x, double y, float *out_x, float *out_y, int x_axis, int y_axis)
    {
        ImVec2 pixel = ImPlot::PlotToPixels(x, y, x_axis, y_axis);
        *out_x = pixel.x;
        *out_y = pixel.y;
    }

    ZGUI_API void zguiPlot_PixelsToPlot(float x, float y, double *out_x, double *out_y, int x_axis, int y_axis)
    {
        ImPlotPoint plot = ImPlot::PixelsToPlot(x, y, x_axis, y_axis);
        *out_x = plot.x;
        *out_y = plot.y;
    }

    ZGUI_API void zguiPlot_PlotPolygon(
        const char *label_id,
        ImGuiDataType data_type,
        const void *xv,
        const void *yv,
        int count,
        ImPlotPolygonFlags flags,
        int offset,
        int stride,
        float fill_alpha,
        const float line_color[4],
        float line_weight,
        const float fill_color[4],
        int marker,
        float marker_size,
        const float marker_line_color[4],
        const float marker_fill_color[4],
        float size)
    {
        const ImPlotSpec spec = makeSpec(flags, offset, stride, fill_alpha, line_color, line_weight, fill_color, marker, marker_size, marker_line_color, marker_fill_color, size);
        if (data_type == ImGuiDataType_S8)
            ImPlot::PlotPolygon(label_id, (const ImS8 *)xv, (const ImS8 *)yv, count, spec);
        else if (data_type == ImGuiDataType_U8)
            ImPlot::PlotPolygon(label_id, (const ImU8 *)xv, (const ImU8 *)yv, count, spec);
        else if (data_type == ImGuiDataType_S16)
            ImPlot::PlotPolygon(label_id, (const ImS16 *)xv, (const ImS16 *)yv, count, spec);
        else if (data_type == ImGuiDataType_U16)
            ImPlot::PlotPolygon(label_id, (const ImU16 *)xv, (const ImU16 *)yv, count, spec);
        else if (data_type == ImGuiDataType_S32)
            ImPlot::PlotPolygon(label_id, (const ImS32 *)xv, (const ImS32 *)yv, count, spec);
        else if (data_type == ImGuiDataType_U32)
            ImPlot::PlotPolygon(label_id, (const ImU32 *)xv, (const ImU32 *)yv, count, spec);
        else if (data_type == ImGuiDataType_Float)
            ImPlot::PlotPolygon(label_id, (const float *)xv, (const float *)yv, count, spec);
        else if (data_type == ImGuiDataType_Double)
            ImPlot::PlotPolygon(label_id, (const double *)xv, (const double *)yv, count, spec);
        else
            assert(false);
    }
} /* extern "C" */
