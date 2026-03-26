//! Zig-native Orchestrator
//!
//! Manages the lifecycle of Studios and Activities, mirroring the
//! patterns of the C++ LabRaven Orchestrator but operating directly
//! on the Zig wrapper types.

const std = @import("std");
const MeshulaLab = @import("MeshulaLab");
const Activity = @import("activity.zig").Activity;
const Studio = @import("studio.zig").Studio;
const ActivityConfig = @import("studio.zig").ActivityConfig;

pub const Orchestrator = struct
{
    activities: ActivityMap,
    studios: StudioMap,
    maybe_current_studio: ?*Studio = null,
    allocator: std.mem.Allocator,

    // Deferred activation
    maybe_pending_studio: ?[*:0]const u8 = null,

    const ActivityMap = std.StringHashMapUnmanaged(*Activity);
    const StudioMap = std.StringHashMapUnmanaged(*Studio);

    pub fn init(
        allocator: std.mem.Allocator,
    ) Orchestrator
    {
        return .{
            .activities = ActivityMap{},
            .studios = StudioMap{},
            .allocator = allocator,
        };
    }

    pub fn deinit(
        self: *Orchestrator,
    ) void
    {
        self.activities.deinit(self.allocator);
        self.studios.deinit(self.allocator);
    }

    /// Register an Activity. The Activity pointer must remain valid
    /// for the lifetime of the Orchestrator.
    pub fn registerActivity(
        self: *Orchestrator,
        activity: *Activity,
    ) void
    {
        const key = std.mem.span(activity.lab.name);
        self.activities.put(
            self.allocator,
            key,
            activity,
        ) catch return;
    }

    /// Register a Studio. The Studio pointer must remain valid
    /// for the lifetime of the Orchestrator.
    pub fn registerStudio(
        self: *Orchestrator,
        studio: *Studio,
    ) void
    {
        // Set the instance pointer so C callbacks can find the Studio
        studio.lab.instance = @ptrCast(&studio.lab);
        const key = std.mem.span(studio.lab.name);
        self.studios.put(
            self.allocator,
            key,
            studio,
        ) catch return;
    }

    /// Request activation of a Studio by name.
    /// Activation is deferred until the next `service()` call.
    pub fn activateStudio(
        self: *Orchestrator,
        studio_name: [*:0]const u8,
    ) void
    {
        self.maybe_pending_studio = studio_name;
    }

    /// Service pending activations and update all active Activities.
    /// Call once per frame.
    pub fn service(
        self: *Orchestrator,
        dt: f32,
    ) void
    {
        // Handle deferred studio activation
        if (self.maybe_pending_studio)
            |pending_name|
        {
            self.doActivateStudio(pending_name);
            self.maybe_pending_studio = null;
        }

        // Update all active Activities
        var it = self.activities.iterator();
        while (it.next())
            |entry|
        {
            const activity = entry.value_ptr.*;
            if (activity.lab.active)
            {
                if (activity.lab.Update)
                    |update_fn|
                {
                    update_fn(activity.lab.instance, dt);
                }
            }
        }
    }

    /// Run the UI for all active, UI-visible Activities.
    /// Caller is responsible for providing the tab/window context.
    /// Returns an iterator-like interface — typically called from
    /// a tab bar loop.
    pub fn activeUIActivities(
        self: *Orchestrator,
    ) ActivityIterator
    {
        return .{
            .inner = self.activities.iterator(),
        };
    }

    pub const ActivityIterator = struct
    {
        inner: ActivityMap.Iterator,

        /// Returns the next active, UI-visible Activity, or null.
        pub fn next(
            self: *ActivityIterator,
        ) ?*Activity
        {
            while (self.inner.next())
                |entry|
            {
                const activity = entry.value_ptr.*;
                if (activity.lab.active and activity.lab.uiVisible)
                {
                    return activity;
                }
            }
            return null;
        }
    };

    /// Run the main menu contributions from all active Activities.
    pub fn runMainMenu(
        self: *Orchestrator,
    ) void
    {
        var it = self.activities.iterator();
        while (it.next())
            |entry|
        {
            const activity = entry.value_ptr.*;
            if (activity.lab.active)
            {
                if (activity.lab.Menu)
                    |menu_fn|
                {
                    menu_fn(activity.lab.instance);
                }
            }
        }
    }

    /// Activate a specific Activity by name.
    pub fn activateActivity(
        self: *Orchestrator,
        activity_name: [*:0]const u8,
    ) void
    {
        const key = std.mem.span(activity_name);
        if (self.activities.get(key))
            |activity|
        {
            activity.lab.active = true;
            activity.lab.uiVisible = true;
            if (activity.lab.Activate)
                |activate_fn|
            {
                activate_fn(activity.lab.instance);
            }
        }
    }

    /// Deactivate a specific Activity by name.
    pub fn deactivateActivity(
        self: *Orchestrator,
        activity_name: [*:0]const u8,
    ) void
    {
        const key = std.mem.span(activity_name);
        if (self.activities.get(key))
            |activity|
        {
            activity.lab.active = false;
            activity.lab.uiVisible = false;
            if (activity.lab.Deactivate)
                |deactivate_fn|
            {
                deactivate_fn(activity.lab.instance);
            }
        }
    }

    /// Toggle an Activity's active/visible state.
    pub fn toggleActivity(
        self: *Orchestrator,
        activity_name: [*:0]const u8,
    ) void
    {
        const key = std.mem.span(activity_name);
        if (self.activities.get(key))
            |activity|
        {
            if (activity.lab.active)
            {
                self.deactivateActivity(activity_name);
            }
            else
            {
                self.activateActivity(activity_name);
            }
        }
    }

    // ---------------------------------------------------------------
    // Internal
    // ---------------------------------------------------------------

    fn doActivateStudio(
        self: *Orchestrator,
        studio_name: [*:0]const u8,
    ) void
    {
        const key = std.mem.span(studio_name);
        const studio = self.studios.get(key) orelse return;

        // Deactivate current studio's Activities
        if (self.maybe_current_studio)
            |current|
        {
            self.deactivateStudioActivities(current);
            current.lab.active = false;
        }

        // Activate the new Studio's Activities
        for (studio.configs)
            |cfg|
        {
            const act_key = std.mem.span(cfg.name);
            if (self.activities.get(act_key))
                |activity|
            {
                activity.lab.active = true;
                activity.lab.uiVisible = cfg.ui_initially_visible;
                if (activity.lab.Activate)
                    |activate_fn|
                {
                    activate_fn(activity.lab.instance);
                }
            }
        }

        studio.lab.active = true;
        self.maybe_current_studio = studio;
    }

    fn deactivateStudioActivities(
        self: *Orchestrator,
        studio: *Studio,
    ) void
    {
        for (studio.configs)
            |cfg|
        {
            const act_key = std.mem.span(cfg.name);
            if (self.activities.get(act_key))
                |activity|
            {
                activity.lab.active = false;
                activity.lab.uiVisible = false;
                if (activity.lab.Deactivate)
                    |deactivate_fn|
                {
                    deactivate_fn(activity.lab.instance);
                }
            }
        }
    }
};
