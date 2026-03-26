//! MeshulaLabZig — Zig-ergonomic wrappers for the MeshulaLab
//! Studio-Activity-Provider architecture.
//!
//! Provides:
//! - `Activity` — wrapper for LabActivity
//! - `Studio` — wrapper for LabStudio with ActivityConfig
//! - `Orchestrator` — Zig-native orchestrator for managing lifecycles

pub const Activity = @import("activity.zig").Activity;
pub const Studio = @import("studio.zig").Studio;
pub const ActivityConfig = @import("studio.zig").ActivityConfig;
pub const Orchestrator = @import("orchestrator.zig").Orchestrator;
