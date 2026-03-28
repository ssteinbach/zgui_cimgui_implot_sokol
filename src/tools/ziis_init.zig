//! ziis-init — scaffold new ZIIS components.
//!
//! Usage:
//!     ziis-init --activity <name>
//!
//! Creates activity and plugin source files under src/activities/<name>/
//! and prints the build.zig lines needed to wire them up.

const std = @import("std");

pub fn main() !void
{
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var stdout_buf: [4096]u8 = undefined;
    var stdout_w = std.fs.File.stdout().writer(&stdout_buf);
    const stdout = &stdout_w.interface;

    var stderr_buf: [4096]u8 = undefined;
    var stderr_w = std.fs.File.stderr().writer(&stderr_buf);
    const stderr = &stderr_w.interface;

    // Parse --activity <name>
    var maybe_activity_name: ?[]const u8 = null;
    var i: usize = 1;
    while (i < args.len) : (i += 1)
    {
        if (std.mem.eql(u8, args[i], "--help") or
            std.mem.eql(u8, args[i], "-h"))
        {
            try stdout.print(HELP_TEXT, .{});
            try stdout.flush();
            return;
        }
        else if (std.mem.eql(u8, args[i], "--activity"))
        {
            i += 1;
            if (i >= args.len)
            {
                try stderr.print(
                    "error: --activity requires a name argument\n",
                    .{},
                );
                fatal(stderr);
            }
            maybe_activity_name = args[i];
        }
        else
        {
            try stderr.print(
                "error: unknown argument: {s}\n",
                .{args[i]},
            );
            fatal(stderr);
        }
    }

    const activity_name = maybe_activity_name orelse
    {
        try stderr.print(
            "usage: ziis-init --activity <name>\n" ++
            "\n" ++
            "  <name>  snake_case activity name (e.g. my_widget)\n",
            .{},
        );
        fatal(stderr);
    };

    // Validate: must be non-empty, snake_case (lowercase + underscores)
    if (activity_name.len == 0)
    {
        try stderr.print("error: activity name must not be empty\n", .{});
        fatal(stderr);
    }
    for (activity_name)
        |c|
    {
        if (!std.ascii.isLower(c) and c != '_' and !std.ascii.isDigit(c))
        {
            try stderr.print(
                "error: activity name must be snake_case " ++
                "(lowercase letters, digits, underscores). got: '{s}'\n",
                .{activity_name},
            );
            fatal(stderr);
        }
    }

    // Derive PascalCase name: my_widget -> MyWidget
    const pascal_name = try snakeToPascal(allocator, activity_name);
    defer allocator.free(pascal_name);

    // Output directory: src/activities/<name>/
    const dest_dir = try std.fmt.allocPrint(
        allocator,
        "src/activities/{s}",
        .{activity_name},
    );
    defer allocator.free(dest_dir);

    const activity_path = try std.fmt.allocPrint(
        allocator,
        "{s}/activity.zig",
        .{dest_dir},
    );
    defer allocator.free(activity_path);

    const plugin_path = try std.fmt.allocPrint(
        allocator,
        "{s}/plugin.zig",
        .{dest_dir},
    );
    defer allocator.free(plugin_path);

    // Check destination doesn't already exist
    if (dirExists(dest_dir))
    {
        try stderr.print("error: {s} already exists\n", .{dest_dir});
        fatal(stderr);
    }

    // Create directory
    std.fs.cwd().makePath(dest_dir) catch
        |err|
    {
        try stderr.print(
            "error: could not create {s}: {}\n",
            .{ dest_dir, err },
        );
        fatal(stderr);
    };

    // Generate and write activity file
    const activity_content = try std.fmt.allocPrint(
        allocator,
        ACTIVITY_FMT,
        .{ pascal_name, pascal_name },
    );
    defer allocator.free(activity_content);
    try writeFile(activity_path, activity_content);

    // Generate and write plugin file
    const plugin_content = try std.fmt.allocPrint(
        allocator,
        PLUGIN_FMT,
        .{
            pascal_name, // doc comment
            pascal_name, // PLUGIN_NAME
            pascal_name, // ACTIVITY_NAME
        },
    );
    defer allocator.free(plugin_content);
    try writeFile(plugin_path, plugin_content);

    // Print success and build.zig instructions
    try stdout.print(
        \\
        \\Created:
        \\  {s}
        \\  {s}
        \\
        \\Add to build.zig plugin_sources:
        \\
        \\    .{{ "plugin_{s}", "{s}" }},
        \\
        \\Add to your studio config:
        \\
        \\    .{{ .name = "{s}Activity" }},
        \\
        \\
    ,
        .{
            activity_path,
            plugin_path,
            activity_name,
            plugin_path,
            pascal_name,
        },
    );
    try stdout.flush();
}

fn fatal(
    w: anytype,
) noreturn
{
    w.flush() catch {};
    std.process.exit(1);
}

fn dirExists(path: []const u8) bool
{
    const stat = std.fs.cwd().statFile(path) catch return false;
    return stat.kind == .directory;
}

fn writeFile(
    path: []const u8,
    content: []const u8,
) !void
{
    const file = try std.fs.cwd().createFile(path, .{});
    defer file.close();
    try file.writeAll(content);
}

/// Convert snake_case to PascalCase: "my_widget" -> "MyWidget"
fn snakeToPascal(
    allocator: std.mem.Allocator,
    snake: []const u8,
) ![]u8
{
    var result: std.ArrayListUnmanaged(u8) = .{};
    var capitalize_next = true;
    for (snake)
        |c|
    {
        if (c == '_')
        {
            capitalize_next = true;
        }
        else
        {
            if (capitalize_next)
            {
                try result.append(allocator, std.ascii.toUpper(c));
                capitalize_next = false;
            }
            else
            {
                try result.append(allocator, c);
            }
        }
    }
    return try result.toOwnedSlice(allocator);
}

// ── Help / Templates ───────────────────────────────────────────────────

const HELP_TEXT =
    \\Usage:
    \\  ziis-init --activity <name>
    \\
    \\Scaffold a new ZIIS activity plugin.
    \\
    \\  <name>  snake_case activity name (e.g. my_widget)
    \\
    \\This creates src/activities/<name>/ with two files:
    \\  activity.zig  — the activity implementation (edit this)
    \\  plugin.zig    — the plugin boilerplate (typically untouched)
    \\
    \\The generated plugin uses @import("activity.zig") (same-directory
    \\import) rather than going through demo_activities/root.zig, so new
    \\activities are self-contained.
    \\
    \\After running, add the printed lines to build.zig plugin_sources
    \\and to your studio config.
    \\
    \\Options:
    \\  --activity <name>  Create a new activity with the given name
    \\  --help, -h         Show this help message
    \\
;


const ACTIVITY_FMT =
    \\//! {s} Activity — TODO: describe what this activity does.
    \\
    \\const MeshulaLab = @import("MeshulaLab");
    \\const ziis = @import("zgui_cimgui_implot_sokol");
    \\const zgui = ziis.zgui;
    \\
    \\pub fn runUI(
    \\    _: ?*anyopaque,
    \\    _: ?*const MeshulaLab.ViewInteraction,
    \\) callconv(.c) void
    \\{{
    \\    zgui.textUnformatted("Hello from {s}Activity!");
    \\}}
    \\
;

const PLUGIN_FMT =
    \\//! Plugin: {s}Activity
    \\
    \\const std = @import("std");
    \\const MeshulaLab = @import("MeshulaLab");
    \\const ziis = @import("zgui_cimgui_implot_sokol");
    \\const activity_mod = @import("activity.zig");
    \\
    \\const PLUGIN_NAME = "{s}Plugin";
    \\const PLUGIN_VERSION = "1.0.0";
    \\const PROVENANCE = "ZIIS";
    \\const ACTIVITY_NAME: [*c]const u8 = "{s}Activity";
    \\
    \\fn getABIVersion() callconv(.c) c_int {{ return 1; }}
    \\fn getProvenance() callconv(.c) [*c]const u8 {{ return PROVENANCE; }}
    \\fn getPluginName() callconv(.c) [*c]const u8 {{ return PLUGIN_NAME; }}
    \\fn getPluginVersion() callconv(.c) [*c]const u8 {{ return PLUGIN_VERSION; }}
    \\fn getActivityCount() callconv(.c) c_int {{ return 1; }}
    \\
    \\fn getActivityName(
    \\    index: c_int,
    \\) callconv(.c) [*c]const u8
    \\{{
    \\    if (index == 0) return ACTIVITY_NAME;
    \\    return null;
    \\}}
    \\
    \\fn createActivity(
    \\    _: [*c]const u8,
    \\) callconv(.c) [*c]MeshulaLab.Activity
    \\{{
    \\    ziis.zgui.initNoContext(std.heap.c_allocator);
    \\    const act = std.heap.c_allocator.create(
    \\        MeshulaLab.Activity,
    \\    ) catch return null;
    \\    act.* = std.mem.zeroes(MeshulaLab.Activity);
    \\    act.name = ACTIVITY_NAME;
    \\    act.RunUI = &activity_mod.runUI;
    \\    return act;
    \\}}
    \\
    \\fn destroyActivity(
    \\    act: [*c]MeshulaLab.Activity,
    \\) callconv(.c) void
    \\{{
    \\    if (act != null)
    \\    {{
    \\        std.heap.c_allocator.destroy(
    \\            @as(*MeshulaLab.Activity, @ptrCast(act)),
    \\        );
    \\    }}
    \\}}
    \\
    \\const DESCRIPTOR = MeshulaLab.PluginDescriptor{{
    \\    .GetABIVersion = &getABIVersion,
    \\    .GetProvenance = &getProvenance,
    \\    .GetPluginName = &getPluginName,
    \\    .GetPluginVersion = &getPluginVersion,
    \\    .GetActivityCount = &getActivityCount,
    \\    .GetActivityName = &getActivityName,
    \\    .CreateActivity = &createActivity,
    \\    .DestroyActivity = &destroyActivity,
    \\}};
    \\
    \\export fn LabGetPluginDescriptor() ?*const MeshulaLab.PluginDescriptor
    \\{{
    \\    return &DESCRIPTOR;
    \\}}
    \\
;
