//! Dynamic plugin discovery and loading
//!
//! Discovers and loads LabRaven-compatible plugin shared libraries
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

/// Metadata about a discovered plugin.
pub const PluginInfo = struct
{
    name: []const u8 = "",
    version: []const u8 = "",
    path: []const u8 = "",
    provenance: []const u8 = "",
    abi_version: c_int = 0,
    compatible: bool = false,

    activity_names: std.ArrayListUnmanaged([]const u8) = .{},
    provider_names: std.ArrayListUnmanaged([]const u8) = .{},
    studio_names: std.ArrayListUnmanaged([]const u8) = .{},

    /// The raw descriptor pointer, valid as long as the library is loaded.
    maybe_descriptor: ?*const MeshulaLab.PluginDescriptor = null,

    pub fn deinit(
        self: *PluginInfo,
        allocator: std.mem.Allocator,
    ) void
    {
        self.activity_names.deinit(allocator);
        self.provider_names.deinit(allocator);
        self.studio_names.deinit(allocator);
    }
};

/// Plugin loader — discovers and loads .dylib/.so/.dll plugins at runtime.
pub const PluginLoader = struct
{
    plugins: std.ArrayListUnmanaged(PluginInfo) = .{},
    loaded_libs: std.ArrayListUnmanaged(
        if (IS_WASM) void else std.DynLib,
    ) = .{},
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
            info.deinit(self.allocator);
        }
        self.plugins.deinit(self.allocator);

        if (!IS_WASM)
        {
            for (self.loaded_libs.items)
                |*lib|
            {
                lib.close();
            }
        }
        self.loaded_libs.deinit(self.allocator);
    }

    /// Scan the default platform-specific plugin directory.
    pub fn discoverPlugins(
        self: *PluginLoader,
    ) void
    {
        if (IS_WASM) return;

        const dir = getPluginDirectory();
        self.discoverPluginsInDirectory(dir);
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

    /// Load all discovered plugins (called after discoverPlugins).
    /// Currently discovery and loading happen together in
    /// discoverPluginsInDirectory, so this is provided for API
    /// compatibility with the C++ PluginLoader.
    pub fn loadAllPlugins(
        _: *PluginLoader,
    ) void
    {
        // Loading happens during discovery in this implementation.
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
            if (!info.compatible) continue;
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
            if (!info.compatible) continue;
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
            if (!info.compatible) continue;
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
            if (!info.compatible) continue;
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

    /// Get the default plugin directory relative to the executable.
    ///
    /// Layout matches `zig build` output:
    ///   zig-out/bin/fundamental-demo
    ///   zig-out/lib/plugins/*.dylib
    ///
    /// So the directory is `<exe_dir>/../lib/plugins`.
    pub fn getPluginDirectory() []const u8
    {
        if (IS_WASM) return "";

        const self_exe_dir = std.fs.selfExeDirPath(
            &exe_dir_buf,
        ) catch return "plugins";

        // Build "<exe_dir>/../lib/plugins"
        const result = std.fmt.bufPrint(
            &plugin_dir_buf,
            "{s}/../lib/plugins",
            .{self_exe_dir},
        ) catch return "plugins";

        return result;
    }

    var exe_dir_buf: [std.fs.max_path_bytes]u8 = undefined;
    var plugin_dir_buf: [std.fs.max_path_bytes]u8 = undefined;

    // ---------------------------------------------------------------
    // Internal
    // ---------------------------------------------------------------

    fn loadPlugin(
        self: *PluginLoader,
        path: []const u8,
    ) void
    {
        if (IS_WASM) return;

        // Need a sentinel-terminated path for DynLib
        var path_buf: [std.fs.max_path_bytes:0]u8 = undefined;
        if (path.len >= path_buf.len) return;
        @memcpy(path_buf[0..path.len], path);
        path_buf[path.len] = 0;
        const path_z: [:0]const u8 = path_buf[0..path.len :0];

        var lib = std.DynLib.open(path_z) catch |err| {
            log.warn("failed to load plugin {s}: {any}", .{ path, err });
            return;
        };

        // Look up the entry point symbol
        const get_descriptor = lib.lookup(
            MeshulaLab.GetPluginDescriptor,
            "LabGetPluginDescriptor",
        ) orelse {
            log.warn(
                "plugin {s} missing LabGetPluginDescriptor symbol",
                .{path},
            );
            lib.close();
            return;
        };

        const maybe_desc = get_descriptor();
        const desc = maybe_desc orelse {
            log.warn(
                "plugin {s} returned null descriptor",
                .{path},
            );
            lib.close();
            return;
        };

        // Build PluginInfo
        var info = PluginInfo{
            .path = path,
            .maybe_descriptor = desc,
        };

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

        self.plugins.append(self.allocator, info) catch return;
        self.loaded_libs.append(self.allocator, lib) catch return;
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
