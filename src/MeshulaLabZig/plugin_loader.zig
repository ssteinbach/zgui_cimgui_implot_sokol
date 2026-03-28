//! Dynamic plugin discovery and loading
//!
//! Discovers and loads MeshulaLab-compatible plugin shared libraries
//! at runtime using std.DynLib on native platforms. On WASM this
//! module is a no-op stub.
//!
//! Each plugin exports a `LabGetPluginDescriptor` symbol that
//! returns a LabPluginDescriptor with factory functions for
//! Activities, Providers, and Studios.

const std = @import("std");
const builtin = @import("builtin");
const MeshulaLab = @import("MeshulaLab");

const IS_WASM = builtin.target.cpu.arch.isWasm();

const log = std.log.scoped(.plugin_loader);

/// Handle type for loaded shared libraries (void on WASM).
const LibHandle = if (IS_WASM) void else *anyopaque;

/// Metadata about a discovered plugin.
pub const PluginInfo = struct
{
    name: []const u8 = "",
    version: []const u8 = "",
    path: []const u8 = "",
    provenance: []const u8 = "",
    abi_version: c_int = 0,
    compatible: bool = false,
    enabled: bool = true,
    loaded: bool = false,

    activity_names: std.ArrayListUnmanaged([]const u8) = .{},
    provider_names: std.ArrayListUnmanaged([]const u8) = .{},
    studio_names: std.ArrayListUnmanaged([]const u8) = .{},

    /// The raw descriptor pointer, valid as long as the library is loaded.
    maybe_descriptor: ?*const MeshulaLab.PluginDescriptor = null,

    /// The dlopen handle, valid while the library is loaded.
    maybe_handle: if (IS_WASM) void else ?LibHandle =
        if (IS_WASM) {} else null,

    /// Strings that we heap-duplicated and must free ourselves.
    /// Strings obtained from the plugin descriptor point into the
    /// dylib and become invalid after dlclose, so on unload we
    /// copy them to the heap and track them here.
    owned_strings: std.ArrayListUnmanaged([]const u8) = .{},

    pub fn totalExports(
        self: *const PluginInfo,
    ) usize
    {
        return self.activity_names.items.len +
            self.provider_names.items.len +
            self.studio_names.items.len;
    }

    /// Free all resources. Called during full teardown.
    pub fn deinit(
        self: *PluginInfo,
        allocator: std.mem.Allocator,
    ) void
    {
        self.freeOwnedStrings(allocator);
        if (self.path.len > 0)
        {
            allocator.free(self.path);
        }
        self.activity_names.deinit(allocator);
        self.provider_names.deinit(allocator);
        self.studio_names.deinit(allocator);
        self.owned_strings.deinit(allocator);
    }

    /// Free heap-duplicated strings tracked in owned_strings.
    fn freeOwnedStrings(
        self: *PluginInfo,
        allocator: std.mem.Allocator,
    ) void
    {
        for (self.owned_strings.items)
            |s|
        {
            allocator.free(s);
        }
        self.owned_strings.clearRetainingCapacity();
    }

    /// Duplicate a string to the heap and track it so it gets freed.
    fn dupeAndOwn(
        self: *PluginInfo,
        allocator: std.mem.Allocator,
        s: []const u8,
    ) []const u8
    {
        const copy = allocator.dupe(u8, s) catch return "";
        self.owned_strings.append(allocator, copy) catch
        {
            allocator.free(copy);
            return "";
        };
        return copy;
    }
};

/// Plugin loader — discovers and loads .dylib/.so/.dll plugins at runtime.
pub const PluginLoader = struct
{
    plugins: std.ArrayListUnmanaged(PluginInfo) = .{},
    allocator: std.mem.Allocator,

    pub fn init(
        allocator: std.mem.Allocator,
    ) PluginLoader
    {
        return .{ .allocator = allocator };
    }

    pub fn deinit(
        self: *PluginLoader,
    ) void
    {
        for (self.plugins.items)
            |*info|
        {
            if (!IS_WASM)
            {
                if (info.maybe_handle)
                    |handle|
                {
                    _ = std.c.dlclose(handle);
                }
            }
            info.deinit(self.allocator);
        }
        self.plugins.deinit(self.allocator);
    }

    /// Scan a specific directory for plugin shared libraries.
    pub fn discoverPluginsInDirectory(
        self: *PluginLoader,
        dir_path: []const u8,
    ) void
    {
        if (IS_WASM) return;

        var dir = std.fs.cwd().openDir(
            dir_path,
            .{ .iterate = true },
        ) catch |err| {
            log.info(
                "plugin directory not found: {s} ({any})",
                .{ dir_path, err },
            );
            return;
        };
        defer dir.close();

        var iter = dir.iterate();
        while (iter.next() catch null)
            |entry|
        {
            if (entry.kind != .file) continue;
            if (!isPluginExtension(entry.name)) continue;

            // Build full path
            var path_buf: [std.fs.max_path_bytes]u8 = undefined;
            const full_path = std.fmt.bufPrint(
                &path_buf,
                "{s}/{s}",
                .{ dir_path, entry.name },
            ) catch continue;

            self.loadPlugin(full_path);
        }
    }

    /// Create an Activity instance by name via the owning plugin.
    pub fn createActivity(
        self: *PluginLoader,
        activity_name: [*:0]const u8,
    ) ?*MeshulaLab.Activity
    {
        if (IS_WASM) return null;
        const name_slice = std.mem.span(activity_name);

        for (self.plugins.items)
            |info|
        {
            if (!info.compatible or !info.enabled) continue;
            const desc = info.maybe_descriptor orelse continue;
            const create_fn = desc.CreateActivity orelse continue;

            for (info.activity_names.items)
                |act_name|
            {
                if (std.mem.eql(u8, act_name, name_slice))
                {
                    return create_fn(activity_name);
                }
            }
        }
        return null;
    }

    /// Destroy an Activity instance via the owning plugin.
    pub fn destroyActivity(
        self: *PluginLoader,
        activity: *MeshulaLab.Activity,
    ) void
    {
        if (IS_WASM) return;
        const name_slice = std.mem.span(activity.name);

        for (self.plugins.items)
            |info|
        {
            if (!info.compatible or !info.enabled) continue;
            const desc = info.maybe_descriptor orelse continue;
            const destroy_fn = desc.DestroyActivity orelse continue;

            for (info.activity_names.items)
                |act_name|
            {
                if (std.mem.eql(u8, act_name, name_slice))
                {
                    destroy_fn(activity);
                    return;
                }
            }
        }
    }

    /// Create a Provider instance by name via the owning plugin.
    pub fn createProvider(
        self: *PluginLoader,
        provider_name: [*:0]const u8,
    ) ?*MeshulaLab.Provider
    {
        if (IS_WASM) return null;
        const name_slice = std.mem.span(provider_name);

        for (self.plugins.items)
            |info|
        {
            if (!info.compatible or !info.enabled) continue;
            const desc = info.maybe_descriptor orelse continue;
            const create_fn = desc.CreateProvider orelse continue;

            for (info.provider_names.items)
                |prov_name|
            {
                if (std.mem.eql(u8, prov_name, name_slice))
                {
                    return create_fn(provider_name);
                }
            }
        }
        return null;
    }

    /// Disable a plugin by index. Does not dlclose — just marks it
    /// so createActivity/createProvider skip it.
    pub fn disablePlugin(
        self: *PluginLoader,
        index: usize,
    ) void
    {
        if (index < self.plugins.items.len)
        {
            self.plugins.items[index].enabled = false;
            log.info(
                "disabled plugin: {s}",
                .{self.plugins.items[index].name},
            );
        }
    }

    /// Fully unload a plugin: dlclose the library and clear its
    /// live metadata. The PluginInfo stays in the list with
    /// loaded=false so the UI can still display it and offer a
    /// Load button. The caller must first unregister/destroy any
    /// Activity or Provider instances that were created from this
    /// plugin, since their function pointers become invalid after
    /// dlclose.
    pub fn unloadPlugin(
        self: *PluginLoader,
        index: usize,
    ) void
    {
        if (IS_WASM) return;
        if (index >= self.plugins.items.len) return;

        var info = &self.plugins.items[index];
        if (!info.loaded) return;

        log.info(
            "unloading plugin: {s}",
            .{info.name},
        );

        // Copy name/version/provenance to the heap before dlclose
        // invalidates the dylib-owned strings.
        if (info.name.len > 0)
        {
            info.name = info.dupeAndOwn(
                self.allocator,
                info.name,
            );
        }
        if (info.version.len > 0)
        {
            info.version = info.dupeAndOwn(
                self.allocator,
                info.version,
            );
        }
        if (info.provenance.len > 0)
        {
            info.provenance = info.dupeAndOwn(
                self.allocator,
                info.provenance,
            );
        }

        // dlclose the library
        if (info.maybe_handle)
            |handle|
        {
            _ = std.c.dlclose(handle);
        }

        // Clear live state but keep path, name, version, provenance
        info.maybe_handle = null;
        info.maybe_descriptor = null;
        info.loaded = false;
        info.enabled = false;
        info.compatible = false;
        info.activity_names.clearRetainingCapacity();
        info.provider_names.clearRetainingCapacity();
        info.studio_names.clearRetainingCapacity();
    }

    /// Load (or reload) a plugin at the given index. The entry
    /// must already exist in the plugins list with a valid path.
    /// Returns true on success.
    pub fn loadPluginAt(
        self: *PluginLoader,
        index: usize,
    ) bool
    {
        if (IS_WASM) return false;
        if (index >= self.plugins.items.len) return false;

        var info = &self.plugins.items[index];

        // If already loaded, unload first (caller is responsible
        // for tearing down activities before calling this).
        if (info.loaded)
        {
            self.unloadPlugin(index);
            info = &self.plugins.items[index];
        }

        // Free any heap-owned strings from the previous load
        info.freeOwnedStrings(self.allocator);

        return self.doLoad(info);
    }

    /// Re-enable a previously disabled plugin by index.
    pub fn enablePlugin(
        self: *PluginLoader,
        index: usize,
    ) void
    {
        if (index < self.plugins.items.len)
        {
            self.plugins.items[index].enabled = true;
            log.info(
                "enabled plugin: {s}",
                .{self.plugins.items[index].name},
            );
        }
    }

    /// Re-scan the plugin directory. New plugins are added to the
    /// list (unloaded). Already-known paths are left as-is.
    pub fn rescan(
        self: *PluginLoader,
        dir_path: []const u8,
    ) void
    {
        if (IS_WASM) return;

        var dir = std.fs.cwd().openDir(
            dir_path,
            .{ .iterate = true },
        ) catch |err| {
            log.info(
                "plugin directory not found: {s} ({any})",
                .{ dir_path, err },
            );
            return;
        };
        defer dir.close();

        var iter = dir.iterate();
        while (iter.next() catch null)
            |entry|
        {
            if (entry.kind != .file) continue;
            if (!isPluginExtension(entry.name)) continue;

            // Build full path
            var path_buf: [std.fs.max_path_bytes]u8 = undefined;
            const full_path = std.fmt.bufPrint(
                &path_buf,
                "{s}/{s}",
                .{ dir_path, entry.name },
            ) catch continue;

            // Skip if already known (loaded or unloaded)
            if (self.isPathKnown(full_path)) continue;

            // Add as a new unloaded entry so it shows in the UI.
            const owned_path = self.allocator.dupe(
                u8,
                full_path,
            ) catch continue;

            self.plugins.append(self.allocator, .{
                .path = owned_path,
            }) catch {
                self.allocator.free(owned_path);
            };
        }
    }

    /// Check if an activity name belongs to a disabled or unloaded
    /// plugin.
    pub fn isActivityDisabled(
        self: *const PluginLoader,
        activity_name: []const u8,
    ) bool
    {
        for (self.plugins.items)
            |info|
        {
            if (!info.loaded) continue;
            for (info.activity_names.items)
                |act_name|
            {
                if (std.mem.eql(u8, act_name, activity_name))
                {
                    return !info.enabled;
                }
            }
        }
        return false;
    }

    /// Check if a plugin at the given path is already known
    /// (loaded or unloaded).
    fn isPathKnown(
        self: *PluginLoader,
        path: []const u8,
    ) bool
    {
        for (self.plugins.items)
            |info|
        {
            if (std.mem.eql(u8, info.path, path)) return true;
        }
        return false;
    }

    /// Destroy a Provider instance via the owning plugin.
    pub fn destroyProvider(
        self: *PluginLoader,
        provider: *MeshulaLab.Provider,
    ) void
    {
        if (IS_WASM) return;
        const name_slice = std.mem.span(provider.name);

        for (self.plugins.items)
            |info|
        {
            if (!info.compatible or !info.enabled) continue;
            const desc = info.maybe_descriptor orelse continue;
            const destroy_fn = desc.DestroyProvider orelse continue;

            for (info.provider_names.items)
                |prov_name|
            {
                if (std.mem.eql(u8, prov_name, name_slice))
                {
                    destroy_fn(provider);
                    return;
                }
            }
        }
    }

    // ---------------------------------------------------------------
    // Internal
    // ---------------------------------------------------------------

    /// Add a new plugin entry and attempt to load it.
    fn loadPlugin(
        self: *PluginLoader,
        path: []const u8,
    ) void
    {
        if (IS_WASM) return;

        const owned_path = self.allocator.dupe(
            u8,
            path,
        ) catch return;

        var info = PluginInfo{ .path = owned_path };

        _ = self.doLoad(&info);

        self.plugins.append(self.allocator, info) catch
        {
            info.deinit(self.allocator);
        };
    }

    /// dlopen a plugin, extract its descriptor, and populate the
    /// info's live fields. The info must already have a valid path.
    /// Returns true on success.
    fn doLoad(
        self: *PluginLoader,
        info: *PluginInfo,
    ) bool
    {
        // Need a sentinel-terminated path for dlopen
        var path_buf: [std.fs.max_path_bytes:0]u8 = undefined;
        if (info.path.len >= path_buf.len) return false;
        @memcpy(path_buf[0..info.path.len], info.path);
        path_buf[info.path.len] = 0;

        const handle = std.c.dlopen(
            @ptrCast(&path_buf),
            .{ .LAZY = true, .GLOBAL = true },
        ) orelse {
            const err_msg = std.c.dlerror();
            if (err_msg)
                |msg|
            {
                log.warn(
                    "failed to load plugin {s}: {s}",
                    .{ info.path, msg },
                );
            }
            else
            {
                log.warn(
                    "failed to load plugin {s}: unknown error",
                    .{info.path},
                );
            }
            return false;
        };

        // Look up the entry point symbol
        const raw_sym = std.c.dlsym(handle, "LabGetPluginDescriptor");
        const get_descriptor: MeshulaLab.GetPluginDescriptor = if (raw_sym)
            |sym|
            @ptrCast(@alignCast(sym))
        else
        {
            log.warn(
                "plugin {s} missing LabGetPluginDescriptor symbol",
                .{info.path},
            );
            _ = std.c.dlclose(handle);
            return false;
        };

        const maybe_desc = get_descriptor();
        const desc = maybe_desc orelse {
            log.warn(
                "plugin {s} returned null descriptor",
                .{info.path},
            );
            _ = std.c.dlclose(handle);
            return false;
        };

        info.maybe_handle = handle;
        info.maybe_descriptor = desc;
        info.loaded = true;
        info.enabled = true;

        if (desc.GetPluginName)
            |name_fn|
        {
            info.name = std.mem.span(name_fn());
        }
        if (desc.GetPluginVersion)
            |ver_fn|
        {
            info.version = std.mem.span(ver_fn());
        }
        if (desc.GetProvenance)
            |prov_fn|
        {
            info.provenance = std.mem.span(prov_fn());
        }
        if (desc.GetABIVersion)
            |abi_fn|
        {
            info.abi_version = abi_fn();
            // TODO: compare against LABRAVEN_ABI_VERSION
            info.compatible = true;
        }
        else
        {
            info.compatible = false;
        }

        // Extract activity names
        if (desc.GetActivityCount)
            |count_fn|
        {
            const count = count_fn();
            if (desc.GetActivityName)
                |name_fn|
            {
                var i: c_int = 0;
                while (i < count) : (i += 1)
                {
                    const n = name_fn(i);
                    if (n != null)
                    {
                        info.activity_names.append(
                            self.allocator,
                            std.mem.span(n),
                        ) catch continue;
                    }
                }
            }
        }

        // Extract provider names
        if (desc.GetProviderCount)
            |count_fn|
        {
            const count = count_fn();
            if (desc.GetProviderName)
                |name_fn|
            {
                var i: c_int = 0;
                while (i < count) : (i += 1)
                {
                    const n = name_fn(i);
                    if (n != null)
                    {
                        info.provider_names.append(
                            self.allocator,
                            std.mem.span(n),
                        ) catch continue;
                    }
                }
            }
        }

        // Extract studio names
        if (desc.GetStudioCount)
            |count_fn|
        {
            const count = count_fn();
            if (desc.GetStudioName)
                |name_fn|
            {
                var i: c_int = 0;
                while (i < count) : (i += 1)
                {
                    const n = name_fn(i);
                    if (n != null)
                    {
                        info.studio_names.append(
                            self.allocator,
                            std.mem.span(n),
                        ) catch continue;
                    }
                }
            }
        }

        if (info.compatible)
        {
            log.info(
                "loaded plugin: {s} v{s}",
                .{ info.name, info.version },
            );
        }
        else
        {
            log.warn(
                "incompatible plugin: {s} (ABI {d})",
                .{ info.name, info.abi_version },
            );
        }

        return true;
    }

    fn isPluginExtension(
        name: []const u8,
    ) bool
    {
        return switch (builtin.os.tag)
        {
            .macos => std.mem.endsWith(u8, name, ".dylib"),
            .linux => std.mem.endsWith(u8, name, ".so"),
            .windows => std.mem.endsWith(u8, name, ".dll"),
            else => false,
        };
    }
};
