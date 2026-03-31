//! ziis-init — scaffold new ZIIS components.
//!
//! Usage:
//!     ziis-init --activity <name>
//!     ziis-init --studio <name>
//!     ziis-init --project <name>
//!
//! Creates activity/studio source files and prints the build.zig
//! lines needed to wire them up via PluginBuilder.

const std = @import("std");

pub fn create_activity(
    allocator: std.mem.Allocator,
    activity_name: []const u8,
    output_dir: []const u8,
    stdout: *std.Io.Writer,
    stderr: *std.Io.Writer,
) !void
{
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
    const pascal_name = try snake_to_pascal(allocator, activity_name);
    defer allocator.free(pascal_name);

    // Output directory: <output_dir>/src/activities/<name>/
    const dest_dir = try std.fmt.allocPrint(
        allocator,
        "{s}/src/activities/{s}",
        .{ output_dir, activity_name },
    );
    defer allocator.free(dest_dir);

    const activity_path = try std.fmt.allocPrint(
        allocator,
        "{s}/activity.zig",
        .{dest_dir},
    );
    defer allocator.free(activity_path);

    // Check destination doesn't already exist
    if (dir_exists(dest_dir))
    {
        try stderr.print("error: {s} already exists\n", .{dest_dir});
        fatal(stderr);
    }

    // Create directory
    std.fs.cwd().makePath(dest_dir) catch |err| {
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
    try write_file(activity_path, activity_content);

    // Print success and build.zig instructions
    try stdout.print(
        \\
        \\Created:
        \\  {s}
        \\
        \\Add to your activities root.zig:
        \\
        \\    pub const {s} = @import("{s}/activity.zig");
        \\
        \\Add to build.zig activity_plugins:
        \\
        \\    pb.add_activity("plugin_{s}", activities_root, .{{
        \\        .activity_field = "{s}",
        \\        .activity_name = "{s}Activity",
        \\        .plugin_name = "{s}Plugin",
        \\        .provenance = "ZIIS",
        \\    }});
        \\
        \\Add to your studio config:
        \\
        \\    .{{ .name = "{s}Activity" }},
        \\
        \\
        ,
        .{
            activity_path,
            activity_name,
            activity_name,
            activity_name,
            activity_name,
            pascal_name,
            pascal_name,
            pascal_name,
        },
    );
    try stdout.flush();
}

pub fn create_studio(
    allocator: std.mem.Allocator,
    studio_name: []const u8,
    output_dir: []const u8,
    stdout: *std.Io.Writer,
    stderr: *std.Io.Writer,
) !void
{
    // Validate: must be non-empty, snake_case (lowercase + underscores)
    if (studio_name.len == 0)
    {
        try stderr.print("error: studio name must not be empty\n", .{});
        fatal(stderr);
    }
    for (studio_name)
        |c|
    {
        if (!std.ascii.isLower(c) and c != '_' and !std.ascii.isDigit(c))
        {
            try stderr.print(
                "error: studio name must be snake_case " ++
                "(lowercase letters, digits, underscores). got: '{s}'\n",
                .{studio_name},
            );
            fatal(stderr);
        }
    }

    // Derive PascalCase name: my_studio -> MyStudio
    const pascal_name = try snake_to_pascal(allocator, studio_name);
    defer allocator.free(pascal_name);

    // Output directory: <output_dir>/src/studios/
    const dest_dir = try std.fmt.allocPrint(
        allocator,
        "{s}/src/studios",
        .{output_dir},
    );
    defer allocator.free(dest_dir);

    const config_path = try std.fmt.allocPrint(
        allocator,
        "{s}/{s}_config.zig",
        .{ dest_dir, studio_name },
    );
    defer allocator.free(config_path);

    // Create directory if needed
    std.fs.cwd().makePath(dest_dir) catch |err| {
        try stderr.print(
            "error: could not create {s}: {}\n",
            .{ dest_dir, err },
        );
        fatal(stderr);
    };

    // Check config file doesn't already exist
    if (file_exists(config_path))
    {
        try stderr.print("error: {s} already exists\n", .{config_path});
        fatal(stderr);
    }

    // Generate and write studio config file
    const config_content = try std.fmt.allocPrint(
        allocator,
        STUDIO_CONFIG_FMT,
        .{pascal_name},
    );
    defer allocator.free(config_content);
    try write_file(config_path, config_content);

    // Print success and build.zig instructions
    try stdout.print(
        \\
        \\Created:
        \\  {s}
        \\
        \\Add to build.zig:
        \\
        \\    pb.add_studio("studio_{s}", b.path("{s}"), .{{
        \\        .studio_name = "{s}Studio",
        \\        .plugin_name = "{s}StudioPlugin",
        \\        .provenance = "ZIIS",
        \\    }});
        \\
        \\
        ,
        .{
            config_path,
            studio_name,
            config_path,
            pascal_name,
            pascal_name,
        },
    );
    try stdout.flush();
}

pub fn create_project(
    allocator: std.mem.Allocator,
    project_name: []const u8,
    output_dir: []const u8,
    local_ziis: bool,
    stdout: *std.Io.Writer,
    stderr: *std.Io.Writer,
) !void
{
    // Validate: must be non-empty, snake_case (lowercase + underscores)
    if (project_name.len == 0)
    {
        try stderr.print("error: project name must not be empty\n", .{});
        fatal(stderr);
    }
    for (project_name)
        |c|
    {
        if (!std.ascii.isLower(c) and c != '_' and !std.ascii.isDigit(c))
        {
            try stderr.print(
                "error: project name must be snake_case " ++
                "(lowercase letters, digits, underscores). got: '{s}'\n",
                .{project_name},
            );
            fatal(stderr);
        }
    }

    // Derive PascalCase name: my_project -> MyProject
    const pascal_name = try snake_to_pascal(allocator, project_name);
    defer allocator.free(pascal_name);

    // Output directory: <output_dir>/<name>/
    const dest_dir = try std.fmt.allocPrint(
        allocator,
        "{s}/{s}",
        .{ output_dir, project_name },
    );
    defer allocator.free(dest_dir);

    // Check destination doesn't already exist
    if (dir_exists(dest_dir))
    {
        try stderr.print("error: {s} already exists\n", .{dest_dir});
        fatal(stderr);
    }

    // Create directories
    const src_dir = try std.fmt.allocPrint(
        allocator,
        "{s}/src",
        .{dest_dir},
    );
    defer allocator.free(src_dir);

    std.fs.cwd().makePath(src_dir) catch |err| {
        try stderr.print(
            "error: could not create {s}: {}\n",
            .{ src_dir, err },
        );
        fatal(stderr);
    };

    // Generate build.zig.zon
    const zon_path = try std.fmt.allocPrint(
        allocator,
        "{s}/build.zig.zon",
        .{dest_dir},
    );
    defer allocator.free(zon_path);

    const zon_content = if (local_ziis)
        try std.fmt.allocPrint(
            allocator,
            PROJECT_ZON_LOCAL_FMT,
            .{project_name},
        )
    else
        try std.fmt.allocPrint(
            allocator,
            PROJECT_ZON_FMT,
            .{project_name},
        );
    defer allocator.free(zon_content);
    try write_file(zon_path, zon_content);

    // Generate build.zig
    const build_path = try std.fmt.allocPrint(
        allocator,
        "{s}/build.zig",
        .{dest_dir},
    );
    defer allocator.free(build_path);

    const build_content = try std.fmt.allocPrint(
        allocator,
        PROJECT_BUILD_FMT,
        .{
            project_name, // exe name
            project_name, // run step name
            project_name, // run step description
            project_name, // activity plugin name (plugin_{name})
            project_name, // activity_field
            pascal_name, // activity_name ({Pascal}Activity)
            pascal_name, // plugin_name ({Pascal}Plugin)
            project_name, // studio plugin name (studio_{name})
            pascal_name, // studio_name ({Pascal}Studio)
            pascal_name, // studio plugin_name ({Pascal}StudioPlugin)
        },
    );
    defer allocator.free(build_content);
    try write_file(build_path, build_content);

    // Generate src/app.zig
    const app_path = try std.fmt.allocPrint(
        allocator,
        "{s}/src/app.zig",
        .{dest_dir},
    );
    defer allocator.free(app_path);

    const app_content = try std.fmt.allocPrint(
        allocator,
        PROJECT_APP_FMT,
        .{
            pascal_name, // doc comment
            pascal_name, // activate_studio name
            pascal_name, // APP.run title
        },
    );
    defer allocator.free(app_content);
    try write_file(app_path, app_content);

    // Generate src/activity.zig
    const activity_path = try std.fmt.allocPrint(
        allocator,
        "{s}/src/activity.zig",
        .{dest_dir},
    );
    defer allocator.free(activity_path);

    const activity_content = try std.fmt.allocPrint(
        allocator,
        PROJECT_ACTIVITY_FMT,
        .{ pascal_name, pascal_name },
    );
    defer allocator.free(activity_content);
    try write_file(activity_path, activity_content);

    // Generate src/activities.zig (root module re-exporting activities)
    const activities_path = try std.fmt.allocPrint(
        allocator,
        "{s}/src/activities.zig",
        .{dest_dir},
    );
    defer allocator.free(activities_path);

    const activities_content = try std.fmt.allocPrint(
        allocator,
        PROJECT_ACTIVITIES_ROOT_FMT,
        .{project_name},
    );
    defer allocator.free(activities_content);
    try write_file(activities_path, activities_content);

    // Generate src/studio_config.zig
    const studio_config_path = try std.fmt.allocPrint(
        allocator,
        "{s}/src/studio_config.zig",
        .{dest_dir},
    );
    defer allocator.free(studio_config_path);

    const studio_config_content = try std.fmt.allocPrint(
        allocator,
        PROJECT_STUDIO_CONFIG_FMT,
        .{ pascal_name, pascal_name },
    );
    defer allocator.free(studio_config_content);
    try write_file(studio_config_path, studio_config_content);

    // Seed fingerprint: run `zig build` to get the suggested value,
    // then rewrite build.zig.zon with the fingerprint inserted.
    seed_fingerprint(allocator, dest_dir, zon_path, project_name, local_ziis, stderr);

    // Print success
    try stdout.print(
        \\
        \\Created project '{s}':
        \\  {s}
        \\  {s}
        \\  {s}
        \\  {s}
        \\  {s}
        \\  {s}
        \\
        \\To get started:
        \\  cd {s}
        \\  zig build run-{s}
        \\
        \\
        ,
        .{
            project_name,
            zon_path,
            build_path,
            app_path,
            activity_path,
            activities_path,
            studio_config_path,
            project_name,
            project_name,
        },
    );
    try stdout.flush();
}

pub fn main(
) !void
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

    // Parse arguments
    var maybe_activity_name: ?[]const u8 = null;
    var maybe_studio_name: ?[]const u8 = null;
    var maybe_project_name: ?[]const u8 = null;
    var local_ziis: bool = false;
    var output_dir: []const u8 = ".";

    var i: usize = 1;
    while (i < args.len)
        : (i += 1)
    {
        if (
            std.mem.eql(u8, args[i], "--help")
            or std.mem.eql(u8, args[i], "-h")
        )
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
        else if (std.mem.eql(u8, args[i], "--studio"))
        {
            i += 1;
            if (i >= args.len)
            {
                try stderr.print(
                    "error: --studio requires a name argument\n",
                    .{},
                );
                fatal(stderr);
            }
            maybe_studio_name = args[i];
        }
        else if (std.mem.eql(u8, args[i], "--project"))
        {
            i += 1;
            if (i >= args.len)
            {
                try stderr.print(
                    "error: --project requires a name argument\n",
                    .{},
                );
                fatal(stderr);
            }
            maybe_project_name = args[i];
        }
        else if (std.mem.eql(u8, args[i], "--local-ziis"))
        {
            local_ziis = true;
        }
        else if (std.mem.eql(u8, args[i], "--output-dir"))
        {
            i += 1;
            if (i >= args.len)
            {
                try stderr.print(
                    "error: --output-dir requires a path argument\n",
                    .{},
                );
                fatal(stderr);
            }
            output_dir = args[i];
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

    const cmd_count = @as(u2, if (maybe_studio_name != null) 1 else 0)
        + @as(u2, if (maybe_activity_name != null) 1 else 0)
        + @as(u2, if (maybe_project_name != null) 1 else 0);
    if (cmd_count > 1)
    {
        try stderr.print(
            "Only one command argument " ++
            "(--studio, --activity, or --project) allowed\n",
            .{},
        );
        fatal(stderr);
    }

    if (maybe_activity_name)
        |activity_name|
    {
        try create_activity(
            allocator,
            activity_name,
            output_dir,
            stdout,
            stderr,
        );
    }

    if (maybe_studio_name)
        |studio_name|
    {
        try create_studio(
            allocator,
            studio_name,
            output_dir,
            stdout,
            stderr,
        );
    }

    if (maybe_project_name)
        |project_name|
    {
        try create_project(
            allocator,
            project_name,
            output_dir,
            local_ziis,
            stdout,
            stderr,
        );
    }
}

/// Run `zig build` in the project directory so that the build system
/// emits its "suggested value" for the missing fingerprint field.
/// Parse that hex literal from stderr and rewrite build.zig.zon with
/// the fingerprint inserted.
fn seed_fingerprint(
    allocator: std.mem.Allocator,
    dest_dir: []const u8,
    zon_path: []const u8,
    project_name: []const u8,
    local_ziis: bool,
    stderr: *std.Io.Writer,
) void
{
    const result = std.process.Child.run(
        .{
            .allocator = allocator,
            .argv = &.{ "zig", "build" },
            .cwd = dest_dir,
        },
    ) catch {
        // zig not found or other exec error — skip silently,
        // user will see the missing-fingerprint error on first build.
        return;
    };
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    // Look for the suggested fingerprint in stderr output.
    // The line looks like:
    //   ... suggested value: 0x542b89b096c7ba04
    const needle = "suggested value: ";
    const pos = std.mem.indexOf(u8, result.stderr, needle) orelse return;
    const start = pos + needle.len;

    // Find end of hex literal (0x...)
    var end = start;
    while (end < result.stderr.len and
        (result.stderr[end] == '0' or
        result.stderr[end] == 'x' or
        std.ascii.isHex(result.stderr[end])))
        : (end += 1)
    {}

    if (end <= start) return;
    const fingerprint = result.stderr[start..end];

    // Rewrite build.zig.zon with the fingerprint
    const zon_content = if (local_ziis)
        std.fmt.allocPrint(
            allocator,
            PROJECT_ZON_LOCAL_WITH_FP_FMT,
            .{ project_name, fingerprint },
        ) catch return
    else
        std.fmt.allocPrint(
            allocator,
            PROJECT_ZON_WITH_FP_FMT,
            .{ project_name, fingerprint },
        ) catch return;
    defer allocator.free(zon_content);
    write_file(zon_path, zon_content) catch |err| {
        stderr.print(
            "warning: could not update fingerprint: {}\n",
            .{err},
        ) catch {};
    };
}

fn fatal(
    w: *std.Io.Writer,
) noreturn
{
    w.flush() catch {};
    std.process.exit(1);
}

fn dir_exists(
    path: []const u8,
) bool
{
    const stat = std.fs.cwd().statFile(path) catch return false;
    return stat.kind == .directory;
}

fn file_exists(
    path: []const u8,
) bool
{
    _ = std.fs.cwd().statFile(path) catch return false;
    return true;
}

fn write_file(
    path: []const u8,
    content: []const u8,
) !void
{
    const file = try std.fs.cwd().createFile(path, .{});
    defer file.close();
    try file.writeAll(content);
}

/// Convert snake_case to PascalCase: "my_widget" -> "MyWidget"
fn snake_to_pascal(
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

// TEMPLATES
// ---------

const HELP_TEXT =
    \\Usage:
    \\  ziis-init --activity <name>
    \\  ziis-init --studio <name>
    \\  ziis-init --project <name>
    \\
    \\Scaffold new ZIIS components.
    \\
    \\  <name>  snake_case name (e.g. my_widget, my_studio)
    \\
    \\--activity creates src/activities/<name>/ with:
    \\  activity.zig  — the activity implementation (edit this)
    \\
    \\Plugin boilerplate is generated at build time via
    \\PluginBuilder.add_activity() — no plugin.zig needed.
    \\
    \\--studio creates src/studios/ with:
    \\  <name>_config.zig  — studio configuration (activity list)
    \\
    \\Plugin boilerplate is generated at build time via
    \\PluginBuilder.add_studio() — no plugin.zig needed.
    \\
    \\--project creates a standalone project directory with:
    \\  build.zig            — build script using PluginBuilder
    \\  build.zig.zon        — package manifest with ziis dependency
    \\  src/app.zig          — app entry point using FundamentalApp
    \\  src/activity.zig     — a starter activity (edit this)
    \\  src/activities.zig   — root module re-exporting activities
    \\  src/studio_config.zig — studio configuration (activity list)
    \\
    \\Plugins are generated at build time from generic templates
    \\and built as shared libraries (.dylib/.so) in lib/plugins/.
    \\
    \\Options:
    \\  --activity <name>    Create a new activity
    \\  --studio <name>      Create a new studio configuration
    \\  --project <name>     Create a new standalone project
    \\  --local-ziis         Use local path dependency (--project only)
    \\  --output-dir <path>  Write files under <path> instead of cwd
    \\  --help, -h           Show this help message
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

const STUDIO_CONFIG_FMT =
    \\//! {s}Studio configuration — activity list.
    \\
    \\pub const ActivityEntry = struct {{
    \\    name: [*:0]const u8,
    \\    initially_visible: bool = true,
    \\    panel_id: ?[*:0]const u8 = null,
    \\    window_name: ?[*:0]const u8 = null,
    \\}};
    \\
    \\pub const ACTIVITIES = [_]ActivityEntry{{
    \\    // .{{ .name = "MyActivity" }},
    \\}};
    \\
;

// -----------------------------------------------------------------
// Project templates
// -----------------------------------------------------------------

const PROJECT_ZON_FMT =
    \\.{{
    \\    .name = .{s},
    \\    .version = "0.0.0",
    \\    .dependencies = .{{
    \\        .zgui_cimgui_implot_sokol = .{{
    \\            .url = "git+https://github.com/ssteinbach/zgui_cimgui_implot_sokol.git",
    \\        }},
    \\    }},
    \\    .paths = .{{
    \\        "build.zig",
    \\        "build.zig.zon",
    \\        "src",
    \\    }},
    \\}}
    \\
;

const PROJECT_ZON_WITH_FP_FMT =
    \\.{{
    \\    .name = .{s},
    \\    .version = "0.0.0",
    \\    .fingerprint = {s},
    \\    .dependencies = .{{
    \\        .zgui_cimgui_implot_sokol = .{{
    \\            .url = "git+https://github.com/ssteinbach/zgui_cimgui_implot_sokol.git",
    \\        }},
    \\    }},
    \\    .paths = .{{
    \\        "build.zig",
    \\        "build.zig.zon",
    \\        "src",
    \\    }},
    \\}}
    \\
;

const PROJECT_ZON_LOCAL_FMT =
    \\.{{
    \\    .name = .{s},
    \\    .version = "0.0.0",
    \\    .dependencies = .{{
    \\        .zgui_cimgui_implot_sokol = .{{
    \\            .path = "../zgui_cimgui_implot_sokol",
    \\        }},
    \\    }},
    \\    .paths = .{{
    \\        "build.zig",
    \\        "build.zig.zon",
    \\        "src",
    \\    }},
    \\}}
    \\
;

const PROJECT_ZON_LOCAL_WITH_FP_FMT =
    \\.{{
    \\    .name = .{s},
    \\    .version = "0.0.0",
    \\    .fingerprint = {s},
    \\    .dependencies = .{{
    \\        .zgui_cimgui_implot_sokol = .{{
    \\            .path = "../zgui_cimgui_implot_sokol",
    \\        }},
    \\    }},
    \\    .paths = .{{
    \\        "build.zig",
    \\        "build.zig.zon",
    \\        "src",
    \\    }},
    \\}}
    \\
;

const PROJECT_BUILD_FMT =
    \\const std = @import("std");
    \\const ziis = @import("zgui_cimgui_implot_sokol");
    \\
    \\pub fn build(
    \\    b: *std.Build,
    \\) !void
    \\{{
    \\    const target = b.standardTargetOptions(.{{}});
    \\    const optimize = b.standardOptimizeOption(.{{}});
    \\
    \\    const plugin_dir = b.getInstallPath(
    \\        .{{ .custom = "lib/plugins" }},
    \\        "",
    \\    );
    \\
    \\    const dep_ziis = b.dependency(
    \\        "zgui_cimgui_implot_sokol",
    \\        .{{
    \\            .target = target,
    \\            .optimize = optimize,
    \\            .plugin_dir = plugin_dir,
    \\        }},
    \\    );
    \\    const mod_ziis = dep_ziis.module("zgui_cimgui_implot_sokol");
    \\    const mod_meshulalab_zig = dep_ziis.module("MeshulaLabZig");
    \\
    \\    // ---------------------------------------------------------------
    \\    // App executable (exports symbols for plugins via -rdynamic)
    \\    // ---------------------------------------------------------------
    \\
    \\    const mod_app = b.createModule(
    \\        .{{
    \\            .root_source_file = b.path("src/app.zig"),
    \\            .target = target,
    \\            .optimize = optimize,
    \\            .imports = &.{{
    \\                .{{
    \\                    .name = "zgui_cimgui_implot_sokol",
    \\                    .module = mod_ziis,
    \\                }},
    \\                .{{
    \\                    .name = "MeshulaLabZig",
    \\                    .module = mod_meshulalab_zig,
    \\                }},
    \\            }},
    \\        }},
    \\    );
    \\
    \\    const exe = b.addExecutable(
    \\        .{{
    \\            .name = "{s}",
    \\            .root_module = mod_app,
    \\        }},
    \\    );
    \\    exe.rdynamic = true;
    \\    b.installArtifact(exe);
    \\
    \\    const run_step = b.step("run-{s}", "Run {s}");
    \\    const run_cmd = b.addRunArtifact(exe);
    \\    // Ensure plugins are installed before the app runs,
    \\    // otherwise it starts up with no activities.
    \\    run_cmd.step.dependOn(b.getInstallStep());
    \\    run_step.dependOn(&run_cmd.step);
    \\
    \\    // ---------------------------------------------------------------
    \\    // Plugin shared libraries (generated from generic templates)
    \\    // ---------------------------------------------------------------
    \\
    \\    const pb = ziis.PluginBuilder.init(
    \\        b,
    \\        dep_ziis,
    \\        target,
    \\        optimize,
    \\    );
    \\
    \\    pb.add_activity("plugin_{s}", b.path("src/activities.zig"), .{{
    \\        .activity_field = "{s}",
    \\        .activity_name = "{s}Activity",
    \\        .plugin_name = "{s}Plugin",
    \\        .provenance = "ZIIS",
    \\    }});
    \\
    \\    pb.add_studio("studio_{s}", b.path("src/studio_config.zig"), .{{
    \\        .studio_name = "{s}Studio",
    \\        .plugin_name = "{s}StudioPlugin",
    \\        .provenance = "ZIIS",
    \\    }});
    \\}}
    \\
;

const PROJECT_APP_FMT =
    \\//! {s} — a ZIIS application.
    \\
    \\const std = @import("std");
    \\const ziis = @import("zgui_cimgui_implot_sokol");
    \\const MeshulaLab = @import("MeshulaLabZig");
    \\
    \\var APP: MeshulaLab.FundamentalApp = undefined;
    \\
    \\fn post_init() void
    \\{{
    \\    APP.activate_studio("{s}Studio");
    \\}}
    \\
    \\pub fn main() !void
    \\{{
    \\    APP = MeshulaLab.FundamentalApp.init(std.heap.c_allocator);
    \\
    \\    APP.run(
    \\        .{{
    \\            .title = "{s}",
    \\            .logger = ziis.std_log_scoped,
    \\            .maybe_post_zgui_init = &post_init,
    \\        }},
    \\    );
    \\}}
    \\
;

const PROJECT_ACTIVITY_FMT =
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
    \\    zgui.textUnformatted("Hello from {s}!");
    \\}}
    \\
;

const PROJECT_ACTIVITIES_ROOT_FMT =
    \\//! Activities root — re-exports all activity modules.
    \\
    \\pub const {s} = @import("activity.zig");
    \\
;

const PROJECT_STUDIO_CONFIG_FMT =
    \\//! {s}Studio configuration — activity list.
    \\
    \\pub const ActivityEntry = struct {{
    \\    name: [*:0]const u8,
    \\    initially_visible: bool = true,
    \\    panel_id: ?[*:0]const u8 = null,
    \\    window_name: ?[*:0]const u8 = null,
    \\}};
    \\
    \\pub const ACTIVITIES = [_]ActivityEntry{{
    \\    .{{ .name = "{s}Activity" }},
    \\}};
    \\
;

