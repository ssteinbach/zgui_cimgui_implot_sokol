//! Lifecycle tests for plugin load/unload/activate/deactivate.
//!
//! Uses a mock plugin (no real dylib) to exercise the orchestrator
//! and activity wrapper lifecycle transitions that the plugin
//! manager UI triggers.

const std = @import("std");
const MeshulaLab = @import("MeshulaLab");
const Activity = @import("activity.zig").Activity;
const Orchestrator = @import("orchestrator.zig").Orchestrator;

// ---------------------------------------------------------------
// Mock plugin state — simulates a stateful plugin like big_text
// or big_plot.
// ---------------------------------------------------------------

const MockState = struct {
    var init_count: u32 = 0;
    var deinit_count: u32 = 0;

    fn reset(
    ) void
    {
        init_count = 0;
        deinit_count = 0;
    }
};

fn mock_activate(
    _: ?*anyopaque,
) callconv(.c) void
{
    MockState.init_count += 1;
}

fn mock_deactivate(
    _: ?*anyopaque,
) callconv(.c) void
{
    MockState.deinit_count += 1;
}

fn mock_run_ui(
    _: ?*anyopaque,
    _: ?*const MeshulaLab.ViewInteraction,
) callconv(.c) void
{}

const MOCK_NAME: [*:0]const u8 = "MockActivity";

/// Create a mock MeshulaLab.Activity as a plugin would.
fn create_mock_c_activity(
    allocator: std.mem.Allocator,
) !*MeshulaLab.Activity
{
    const act = try allocator.create(MeshulaLab.Activity);
    act.* = std.mem.zeroes(MeshulaLab.Activity);
    act.name = MOCK_NAME;
    act.Activate = &mock_activate;
    act.Deactivate = &mock_deactivate;
    act.RunUI = &mock_run_ui;
    return act;
}

/// Destroy a mock activity as a plugin's DestroyActivity would.
fn destroy_mock_c_activity(
    allocator: std.mem.Allocator,
    act: *MeshulaLab.Activity,
) void
{
    allocator.destroy(act);
}

/// Wrap a C activity into a Zig Activity + register, mimicking
/// FundamentalApp.load_activities_for_plugin.
fn wrap_and_register(
    allocator: std.mem.Allocator,
    orchestrator: *Orchestrator,
    c_activity: *MeshulaLab.Activity,
) !*Activity
{
    const wrapper = try allocator.create(Activity);
    wrapper.* = .{
        .lab = c_activity.*,
        .maybe_plugin_activity = c_activity,
    };
    orchestrator.register_activity(wrapper);
    return wrapper;
}

/// Teardown a wrapper, mimicking
/// FundamentalApp.teardown_plugin_activities.
fn teardown_wrapper(
    allocator: std.mem.Allocator,
    orchestrator: *Orchestrator,
    wrapper: *Activity,
    c_activity: *MeshulaLab.Activity,
) void
{
    const name_slice = std.mem.span(wrapper.lab.name);

    // Deactivate only if active
    if (wrapper.lab.active)
    {
        var name_buf: [256:0]u8 = undefined;
        const nlen = @min(name_slice.len, name_buf.len - 1);
        @memcpy(name_buf[0..nlen], name_slice[0..nlen]);
        name_buf[nlen] = 0;
        orchestrator.deactivate_activity(@ptrCast(&name_buf));
    }

    // Unregister
    _ = orchestrator.unregister_activity(name_slice);

    // Destroy C activity
    destroy_mock_c_activity(allocator, c_activity);

    // Free wrapper
    allocator.destroy(wrapper);
}

// ---------------------------------------------------------------
// Tests
// ---------------------------------------------------------------

test "Orchestrator: activate then deactivate"
{
    const allocator = std.testing.allocator;
    MockState.reset();

    var orch = Orchestrator.init(allocator);
    defer orch.deinit();

    const c_act = try create_mock_c_activity(allocator);
    const wrapper = try wrap_and_register(
        allocator,
        &orch,
        c_act,
    );

    // Activate
    orch.activate_activity(MOCK_NAME);
    try std.testing.expectEqual(@as(u32, 1), MockState.init_count);
    try std.testing.expect(wrapper.lab.active);

    // Deactivate
    orch.deactivate_activity(MOCK_NAME);
    try std.testing.expectEqual(@as(u32, 1), MockState.deinit_count);
    try std.testing.expect(!wrapper.lab.active);

    // Cleanup
    teardown_wrapper(allocator, &orch, wrapper, c_act);
}

test "Orchestrator: double activate is no-op"
{
    const allocator = std.testing.allocator;
    MockState.reset();

    var orch = Orchestrator.init(allocator);
    defer orch.deinit();

    const c_act = try create_mock_c_activity(allocator);
    const wrapper = try wrap_and_register(
        allocator,
        &orch,
        c_act,
    );

    orch.activate_activity(MOCK_NAME);
    orch.activate_activity(MOCK_NAME);
    try std.testing.expectEqual(@as(u32, 1), MockState.init_count);

    teardown_wrapper(allocator, &orch, wrapper, c_act);
}

test "Orchestrator: double deactivate is no-op"
{
    const allocator = std.testing.allocator;
    MockState.reset();

    var orch = Orchestrator.init(allocator);
    defer orch.deinit();

    const c_act = try create_mock_c_activity(allocator);
    const wrapper = try wrap_and_register(
        allocator,
        &orch,
        c_act,
    );

    orch.activate_activity(MOCK_NAME);
    orch.deactivate_activity(MOCK_NAME);
    orch.deactivate_activity(MOCK_NAME);
    try std.testing.expectEqual(@as(u32, 1), MockState.deinit_count);

    teardown_wrapper(allocator, &orch, wrapper, c_act);
}

test "Orchestrator: deactivate without activate is no-op"
{
    const allocator = std.testing.allocator;
    MockState.reset();

    var orch = Orchestrator.init(allocator);
    defer orch.deinit();

    const c_act = try create_mock_c_activity(allocator);
    const wrapper = try wrap_and_register(
        allocator,
        &orch,
        c_act,
    );

    // Activity starts inactive — deactivate should be a no-op
    orch.deactivate_activity(MOCK_NAME);
    try std.testing.expectEqual(@as(u32, 0), MockState.deinit_count);

    teardown_wrapper(allocator, &orch, wrapper, c_act);
}

test "Orchestrator: activate-deactivate-activate cycle"
{
    const allocator = std.testing.allocator;
    MockState.reset();

    var orch = Orchestrator.init(allocator);
    defer orch.deinit();

    const c_act = try create_mock_c_activity(allocator);
    const wrapper = try wrap_and_register(
        allocator,
        &orch,
        c_act,
    );

    // Simulate: Load → Disable → Enable
    orch.activate_activity(MOCK_NAME);
    try std.testing.expectEqual(@as(u32, 1), MockState.init_count);

    orch.deactivate_activity(MOCK_NAME);
    try std.testing.expectEqual(@as(u32, 1), MockState.deinit_count);

    orch.activate_activity(MOCK_NAME);
    try std.testing.expectEqual(@as(u32, 2), MockState.init_count);

    teardown_wrapper(allocator, &orch, wrapper, c_act);
}

test "Orchestrator: unregister then re-register (simulate reload)"
{
    const allocator = std.testing.allocator;
    MockState.reset();

    var orch = Orchestrator.init(allocator);
    defer orch.deinit();

    // First load
    const c_act1 = try create_mock_c_activity(allocator);
    const wrapper1 = try wrap_and_register(
        allocator,
        &orch,
        c_act1,
    );
    orch.activate_activity(MOCK_NAME);
    try std.testing.expectEqual(@as(u32, 1), MockState.init_count);

    // Teardown (simulate unload)
    teardown_wrapper(allocator, &orch, wrapper1, c_act1);
    try std.testing.expectEqual(@as(u32, 1), MockState.deinit_count);
    try std.testing.expect(orch.find_activity("MockActivity") == null);

    // Second load (simulate reload)
    const c_act2 = try create_mock_c_activity(allocator);
    const wrapper2 = try wrap_and_register(
        allocator,
        &orch,
        c_act2,
    );
    orch.activate_activity(MOCK_NAME);
    try std.testing.expectEqual(@as(u32, 2), MockState.init_count);

    // Disable then enable after reload
    orch.deactivate_activity(MOCK_NAME);
    try std.testing.expectEqual(@as(u32, 2), MockState.deinit_count);

    orch.activate_activity(MOCK_NAME);
    try std.testing.expectEqual(@as(u32, 3), MockState.init_count);

    teardown_wrapper(allocator, &orch, wrapper2, c_act2);
}

test "Orchestrator: teardown inactive activity skips deactivate"
{
    const allocator = std.testing.allocator;
    MockState.reset();

    var orch = Orchestrator.init(allocator);
    defer orch.deinit();

    const c_act = try create_mock_c_activity(allocator);
    const wrapper = try wrap_and_register(
        allocator,
        &orch,
        c_act,
    );

    // Activate then disable (deactivate)
    orch.activate_activity(MOCK_NAME);
    orch.deactivate_activity(MOCK_NAME);
    try std.testing.expectEqual(@as(u32, 1), MockState.deinit_count);

    // Teardown should NOT call deactivate again
    teardown_wrapper(allocator, &orch, wrapper, c_act);
    try std.testing.expectEqual(@as(u32, 1), MockState.deinit_count);
}

// ---------------------------------------------------------------
// Per-activity lifecycle tests
//
// Each real plugin in the repo falls into one of three categories:
//   1. Stateless — RunUI only, no Activate/Deactivate
//   2. Stateful  — Activate + Deactivate manage resources
//   3. Stateful  — Activate + Update (no Deactivate)
//
// The tests below exercise every activity name through a
// parameterized helper that mirrors what FundamentalApp does:
//   register → activate → service → deactivate → toggle →
//   unregister → re-register → teardown
// ---------------------------------------------------------------

/// Per-activity call counters (one set per concurrent mock).
const CallCounters = struct {
    activate_count: u32 = 0,
    deactivate_count: u32 = 0,
    update_count: u32 = 0,
    run_ui_count: u32 = 0,
};

/// Describes the callback shape of a plugin activity.
const ActivityVariant = enum {
    /// RunUI only — no Activate/Deactivate (e.g. PlotDemoActivity)
    stateless,
    /// Activate + Deactivate + RunUI (e.g. BigPlotDemoActivity)
    stateful,
    /// Activate + Update + RunUI, no Deactivate (e.g. TextureDemoActivity)
    stateful_update,
};

/// All plugin activities in the repo, with their callback variant.
const ActivitySpec = struct {
    name: [*:0]const u8,
    variant: ActivityVariant,
};

const ALL_ACTIVITY_SPECS = [_]ActivitySpec{
    // Stateless activities
    .{ .name = "PlotDemoActivity", .variant = .stateless },
    .{ .name = "StairsPlotDemoActivity", .variant = .stateless },
    .{ .name = "PolygonPlotDemoActivity", .variant = .stateless },
    .{ .name = "CanvasDrawingDemoActivity", .variant = .stateless },
    .{ .name = "ListClipperDemoActivity", .variant = .stateless },
    .{ .name = "SortableTableDemoActivity", .variant = .stateless },
    .{ .name = "InfLinesPieChartDemoActivity", .variant = .stateless },

    // Stateful activities (Activate + Deactivate)
    .{ .name = "BigPlotDemoActivity", .variant = .stateful },
    .{ .name = "BigTextDemoActivity", .variant = .stateful },
    .{ .name = "JSONPieChartDemoActivity", .variant = .stateful },
    .{ .name = "UndoJournalDemoActivity", .variant = .stateful },

    // Stateful with Update (Activate + Update, no Deactivate)
    .{ .name = "TextureDemoActivity", .variant = .stateful_update },
};

fn mock_counting_activate(
    instance: ?*anyopaque,
) callconv(.c) void
{
    const counters: *CallCounters = @ptrCast(@alignCast(instance));
    counters.activate_count += 1;
}

fn mock_counting_deactivate(
    instance: ?*anyopaque,
) callconv(.c) void
{
    const counters: *CallCounters = @ptrCast(@alignCast(instance));
    counters.deactivate_count += 1;
}

fn mock_counting_update(
    instance: ?*anyopaque,
    _: f32,
) callconv(.c) void
{
    const counters: *CallCounters = @ptrCast(@alignCast(instance));
    counters.update_count += 1;
}

fn mock_counting_run_ui(
    instance: ?*anyopaque,
    _: ?*const MeshulaLab.ViewInteraction,
) callconv(.c) void
{
    const counters: *CallCounters = @ptrCast(@alignCast(instance));
    counters.run_ui_count += 1;
}

/// Create a C activity with callbacks matching the given variant,
/// wired to write into the supplied counters.
fn create_variant_c_activity(
    allocator: std.mem.Allocator,
    activity_name: [*:0]const u8,
    variant: ActivityVariant,
    counters: *CallCounters,
) !*MeshulaLab.Activity
{
    const act = try allocator.create(MeshulaLab.Activity);
    act.* = std.mem.zeroes(MeshulaLab.Activity);
    act.name = activity_name;
    act.instance = @ptrCast(counters);
    act.RunUI = &mock_counting_run_ui;

    switch (variant) {
        .stateless => {},
        .stateful =>
        {
            act.Activate = &mock_counting_activate;
            act.Deactivate = &mock_counting_deactivate;
        },
        .stateful_update =>
        {
            act.Activate = &mock_counting_activate;
            act.Update = &mock_counting_update;
        },
    }
    return act;
}

/// Run the full lifecycle gauntlet for a single activity spec.
fn run_lifecycle_for_spec(
    allocator: std.mem.Allocator,
    spec: ActivitySpec,
) !void
{
    var counters = CallCounters{};
    var orch = Orchestrator.init(allocator);
    defer orch.deinit();

    // --- Create and register ---
    const c_act = try create_variant_c_activity(
        allocator,
        spec.name,
        spec.variant,
        &counters,
    );
    const wrapper = try wrap_and_register(allocator, &orch, c_act);
    try std.testing.expect(!wrapper.lab.active);

    // --- Activate ---
    orch.activate_activity(spec.name);
    try std.testing.expect(wrapper.lab.active);
    try std.testing.expect(wrapper.lab.uiVisible);

    switch (spec.variant) {
        .stateless =>
        {
            try std.testing.expectEqual(@as(u32, 0), counters.activate_count);
        },
        .stateful, .stateful_update =>
        {
            try std.testing.expectEqual(@as(u32, 1), counters.activate_count);
        },
    }

    // --- Double activate is idempotent ---
    orch.activate_activity(spec.name);
    switch (spec.variant) {
        .stateless => {},
        .stateful, .stateful_update =>
        {
            try std.testing.expectEqual(@as(u32, 1), counters.activate_count);
        },
    }

    // --- Service tick (exercises Update for stateful_update) ---
    orch.service(0.016);
    if (spec.variant == .stateful_update)
    {
        try std.testing.expectEqual(@as(u32, 1), counters.update_count);
    }
    else
    {
        try std.testing.expectEqual(@as(u32, 0), counters.update_count);
    }

    // --- Deactivate ---
    orch.deactivate_activity(spec.name);
    try std.testing.expect(!wrapper.lab.active);
    try std.testing.expect(!wrapper.lab.uiVisible);

    if (spec.variant == .stateful)
    {
        try std.testing.expectEqual(@as(u32, 1), counters.deactivate_count);
    }
    else
    {
        try std.testing.expectEqual(@as(u32, 0), counters.deactivate_count);
    }

    // --- Double deactivate is idempotent ---
    orch.deactivate_activity(spec.name);
    if (spec.variant == .stateful)
    {
        try std.testing.expectEqual(@as(u32, 1), counters.deactivate_count);
    }

    // --- Toggle on (re-activate) ---
    orch.toggle_activity(spec.name);
    try std.testing.expect(wrapper.lab.active);

    // --- Toggle off (deactivate again) ---
    orch.toggle_activity(spec.name);
    try std.testing.expect(!wrapper.lab.active);

    // --- Unregister then re-register (simulate plugin reload) ---
    _ = orch.unregister_activity(std.mem.span(spec.name));
    try std.testing.expect(
        orch.find_activity(std.mem.span(spec.name)) == null,
    );

    orch.register_activity(wrapper);
    try std.testing.expect(
        orch.find_activity(std.mem.span(spec.name)) != null,
    );

    // Activate after reload
    orch.activate_activity(spec.name);
    try std.testing.expect(wrapper.lab.active);

    // --- Teardown ---
    teardown_wrapper(allocator, &orch, wrapper, c_act);
}

test "Orchestrator: lifecycle for each stateless activity"
{
    const allocator = std.testing.allocator;
    for (ALL_ACTIVITY_SPECS)
        |spec|
    {
        if (spec.variant == .stateless)
        {
            try run_lifecycle_for_spec(allocator, spec);
        }
    }
}

test "Orchestrator: lifecycle for each stateful activity"
{
    const allocator = std.testing.allocator;
    for (ALL_ACTIVITY_SPECS)
        |spec|
    {
        if (spec.variant == .stateful)
        {
            try run_lifecycle_for_spec(allocator, spec);
        }
    }
}

test "Orchestrator: lifecycle for each stateful+update activity"
{
    const allocator = std.testing.allocator;
    for (ALL_ACTIVITY_SPECS)
        |spec|
    {
        if (spec.variant == .stateful_update)
        {
            try run_lifecycle_for_spec(allocator, spec);
        }
    }
}

test "Orchestrator: activate-deactivate-reactivate for every activity"
{
    const allocator = std.testing.allocator;

    for (ALL_ACTIVITY_SPECS)
        |spec|
    {
        var counters = CallCounters{};
        var orch = Orchestrator.init(allocator);
        defer orch.deinit();

        const c_act = try create_variant_c_activity(
            allocator,
            spec.name,
            spec.variant,
            &counters,
        );
        const wrapper = try wrap_and_register(
            allocator,
            &orch,
            c_act,
        );

        // --- Activate ---
        orch.activate_activity(spec.name);
        try std.testing.expect(wrapper.lab.active);
        try std.testing.expect(wrapper.lab.uiVisible);

        const expect_activate: u32 = switch (spec.variant) {
            .stateless => 0,
            .stateful, .stateful_update => 1,
        };
        try std.testing.expectEqual(expect_activate, counters.activate_count);

        // --- Deactivate ---
        orch.deactivate_activity(spec.name);
        try std.testing.expect(!wrapper.lab.active);
        try std.testing.expect(!wrapper.lab.uiVisible);

        const expect_deactivate: u32 = switch (spec.variant) {
            .stateful => 1,
            .stateless, .stateful_update => 0,
        };
        try std.testing.expectEqual(
            expect_deactivate,
            counters.deactivate_count,
        );

        // --- Re-activate ---
        orch.activate_activity(spec.name);
        try std.testing.expect(wrapper.lab.active);
        try std.testing.expect(wrapper.lab.uiVisible);

        try std.testing.expectEqual(
            expect_activate * 2,
            counters.activate_count,
        );

        // --- Service tick (verifies Update fires when active) ---
        orch.service(0.016);
        if (spec.variant == .stateful_update)
        {
            try std.testing.expectEqual(@as(u32, 1), counters.update_count);
        }
        else
        {
            try std.testing.expectEqual(@as(u32, 0), counters.update_count);
        }

        // --- Final deactivate ---
        orch.deactivate_activity(spec.name);
        try std.testing.expect(!wrapper.lab.active);
        try std.testing.expectEqual(
            expect_deactivate * 2,
            counters.deactivate_count,
        );

        // --- Teardown (already inactive, should not fire deactivate) ---
        teardown_wrapper(allocator, &orch, wrapper, c_act);
        try std.testing.expectEqual(
            expect_deactivate * 2,
            counters.deactivate_count,
        );
    }
}

test "Orchestrator: all activities coexist in one orchestrator"
{
    const allocator = std.testing.allocator;
    var orch = Orchestrator.init(allocator);
    defer orch.deinit();

    // Track counters and wrappers for each activity
    var counters: [ALL_ACTIVITY_SPECS.len]CallCounters = undefined;
    var wrappers: [ALL_ACTIVITY_SPECS.len]*Activity = undefined;
    var c_activities: [ALL_ACTIVITY_SPECS.len]*MeshulaLab.Activity = (
        undefined
    );

    // Register all
    for (ALL_ACTIVITY_SPECS, 0..)
        |spec, i|
    {
        counters[i] = .{};
        c_activities[i] = try create_variant_c_activity(
            allocator,
            spec.name,
            spec.variant,
            &counters[i],
        );
        wrappers[i] = try wrap_and_register(
            allocator,
            &orch,
            c_activities[i],
        );
    }

    // Activate all
    for (ALL_ACTIVITY_SPECS)
        |spec|
    {
        orch.activate_activity(spec.name);
    }

    // Service one tick
    orch.service(0.016);

    // Verify each got its expected callbacks
    for (ALL_ACTIVITY_SPECS, 0..)
        |spec, i|
    {
        switch (spec.variant) {
            .stateless =>
            {
                try std.testing.expectEqual(
                    @as(u32, 0),
                    counters[i].activate_count,
                );
            },
            .stateful, .stateful_update =>
            {
                try std.testing.expectEqual(
                    @as(u32, 1),
                    counters[i].activate_count,
                );
            },
        }
        if (spec.variant == .stateful_update)
        {
            try std.testing.expectEqual(
                @as(u32, 1),
                counters[i].update_count,
            );
        }
    }

    // Deactivate all
    for (ALL_ACTIVITY_SPECS)
        |spec|
    {
        orch.deactivate_activity(spec.name);
    }

    // Teardown all
    for (ALL_ACTIVITY_SPECS, 0..)
        |_, i|
    {
        const idx = ALL_ACTIVITY_SPECS.len - 1 - i;
        teardown_wrapper(
            allocator,
            &orch,
            wrappers[idx],
            c_activities[idx],
        );
    }
}
