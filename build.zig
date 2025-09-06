//! Build Script for ZIIS / Zig cImgui Implot Sokol Bundle

const std = @import("std");
const sokol = @import("sokol");
const cimgui = @import("cimgui");

pub fn build(
    b: *std.Build,
) !void 
{
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Get the matching Zig module name, C header search path and C library for
    // vanilla imgui vs the imgui docking branch.
    const cimgui_conf = cimgui.getConfig(true);

    const dep_implot = b.dependency(
        "implot",
        .{
            .target = target,
            .optimize=optimize,
        },
    );

    // note that the sokol dependency is built with `.with_sokol_imgui = true`
    const dep_sokol = b.dependency(
        "sokol",
        .{
            .target = target,
            .optimize = optimize,
            .with_sokol_imgui = true,
        }
    );
    const dep_cimgui = b.dependency(
        "cimgui",
        .{
            .target = target,
            .optimize = optimize,
        },
    );
    const dep_undo_journal = b.dependency(
        "do_undo_journal",
        .{
            .target = target,
            .optimize = optimize,
        },
    );

    // inject the cimgui header search path into the sokol C library compile step
    dep_sokol.artifact("sokol_clib").addIncludePath(
        dep_cimgui.path(cimgui_conf.include_dir)
    );

    const mod_ziis = b.addModule(
        "zgui_cimgui_implot_sokol",
        .{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ 
                    .name = "sokol",
                    .module = dep_sokol.module("sokol"),
                },
                .{
                    .name = "cimgui",
                    .module = dep_cimgui.module(cimgui_conf.module_name),
                },
                .{
                    .name = "undo",
                    .module = dep_undo_journal.module("do_undo_journal"),
                },
            },
        },
    );

    const lib_imgui = b.addLibrary(
        .{ 
            .linkage = .static,
            .name = "imgui",
            .root_module = b.createModule(
                .{
                    .target = target,
                    .optimize = optimize,
                    .link_libcpp = true,
                    .link_libc = true,
                },
            ),
        }
    );

    lib_imgui.addCSourceFiles(
        .{
            .root = b.path("src"),
            .files = &.{
                 "zgui.cpp",
                 "zplot.cpp",
            },
            .flags = &.{
                "-fno-sanitize=undefined",
                "-Wno-elaborated-enum-base",
                "-Wno-error=date-time",
            },
        },
    );
    lib_imgui.addCSourceFiles(
        .{
            .root = dep_implot.path("."),
            .files = &.{
                "implot.cpp",
                "implot_items.cpp",
                "implot_demo.cpp",
            },
        },
    );
    lib_imgui.addIncludePath(
        dep_cimgui.path("src-docking"),
    );
    lib_imgui.addIncludePath(
        dep_implot.path("implot.h").dirname(),
    );
    mod_ziis.linkLibrary(dep_cimgui.artifact(cimgui_conf.clib_name));
    mod_ziis.linkLibrary(lib_imgui);

    // main module with sokol and cimgui imports
    const mod_app_wrapper = b.createModule(
        .{
            .root_source_file = b.path("src/app_wrapper_demo.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{
                    .name = "zgui_cimgui_implot_sokol",
                    .module = mod_ziis 
                },
            },
        },
    );

    // from here on different handling for native vs wasm builds
    if (target.result.cpu.arch.isWasm()) 
    {
        try build_wasm(
            b,
            .{
                .mod_main = mod_app_wrapper,
                .dep_sokol = dep_sokol,
                .dep_cimgui = dep_cimgui,
                .cimgui_clib_name = cimgui_conf.clib_name,
            },
        );
    } 
    else 
    {
        try build_native(b, mod_app_wrapper);
    }
}

fn build_native(
    b: *std.Build,
    mod: *std.Build.Module,
) !void 
{
    const exe = b.addExecutable(
        .{
            .name = "demo",
            .root_module = mod,
        },
    );
    b.installArtifact(exe);
    b.step(
        "run",
        "Run demo"
    ).dependOn(&b.addRunArtifact(exe).step);
}

const BuildWasmOptions = struct {
    mod_main: *std.Build.Module,
    dep_sokol: *std.Build.Dependency,
    dep_cimgui: *std.Build.Dependency,
    cimgui_clib_name: []const u8,
};

fn build_wasm(
    b: *std.Build,
    opts: BuildWasmOptions,
) !void 
{
    // build the main file into a library, this is because the WASM 'exe'
    // needs to be linked in a separate build step with the Emscripten linker
    const demo = b.addLibrary(
        .{
            .name = "demo",
            .root_module = opts.mod_main,
        },
    );

    // get the Emscripten SDK dependency from the sokol dependency
    const dep_emsdk = opts.dep_sokol.builder.dependency(
        "emsdk",
        .{},
    );

    // need to inject the Emscripten system header include path into
    // the cimgui C library otherwise the C/C++ code won't find
    // C stdlib headers
    const emsdk_incl_path = dep_emsdk.path(
        "upstream/emscripten/cache/sysroot/include",
    );
    opts.dep_cimgui.artifact(
        opts.cimgui_clib_name
    ).addSystemIncludePath(emsdk_incl_path);

    // all C libraries need to depend on the sokol library, when building for
    // WASM this makes sure that the Emscripten SDK has been setup before
    // C compilation is attempted (since the sokol C library depends on the
    // Emscripten SDK setup step)
    opts.dep_cimgui.artifact(
        opts.cimgui_clib_name,
    ).step.dependOn(&opts.dep_sokol.artifact("sokol_clib").step);

    // create a build step which invokes the Emscripten linker
    const link_step = try sokol.emLinkStep(
        b,
        .{
            .lib_main = demo,
            .target = opts.mod_main.resolved_target.?,
            .optimize = opts.mod_main.optimize.?,
            .emsdk = dep_emsdk,
            .use_webgl2 = true,
            .use_emmalloc = true,
            .use_filesystem = false,
            .shell_file_path = opts.dep_sokol.path("src/sokol/web/shell.html"),
        },
    );
    // attach to default target
    b.getInstallStep().dependOn(&link_step.step);
    // ...and a special run step to start the web build output via 'emrun'
    const run = sokol.emRunStep(b, .{ .name = "demo", .emsdk = dep_emsdk });
    run.step.dependOn(&link_step.step);
    b.step("run", "Run demo").dependOn(&run.step);
}
