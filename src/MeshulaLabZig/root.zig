//! MeshulaLabZig — Zig-ergonomic wrappers for the MeshulaLab
//! Studio-Activity-Provider architecture.
//!
//! Provides:
//! - `Activity` — wrapper for LabActivity
//! - `Studio` — wrapper for LabStudio with ActivityConfig
//! - `Orchestrator` — Zig-native orchestrator for managing lifecycles
//! - `FundamentalApp` — full application class (port of App.h/App.cpp)
//! - `PluginLoader` — dynamic plugin discovery and loading
//! - `CspEngine` / `CspModule` / `CspProcess` — CSP event system
//! - `ViewInteraction` / `ViewDimensions` — viewport interaction types

pub const Activity = @import("activity.zig").Activity;
pub const Studio = @import("studio.zig").Studio;
pub const ActivityConfig = @import("studio.zig").ActivityConfig;
pub const Orchestrator = @import("orchestrator.zig").Orchestrator;
pub const FundamentalApp = @import("fundamental_app.zig").FundamentalApp;
pub const PluginLoader = @import("plugin_loader.zig").PluginLoader;

const csp = @import("csp.zig");
pub const CspEngine = csp.CspEngine;
pub const CspModule = csp.CspModule;
pub const CspProcess = csp.CspProcess;

const view = @import("view_interaction.zig");
pub const ViewInteraction = view.ViewInteraction;
pub const ViewDimensions = view.ViewDimensions;

pub const FileDialog = @import("file_dialog.zig");
