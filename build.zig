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

    // Fetch Dependencies
    ///////////////////////////////////////////////////////////////////////////

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
    // Get the matching Zig module name, C header search path and C library for
    // vanilla imgui vs the imgui docking branch.
    const cimgui_conf = cimgui.getConfig(
        // Currently *not* using the docking version, although not for any big
        // reason.
        false
    );
    const lib_cimgui = dep_cimgui.artifact(cimgui_conf.clib_name);

    const dep_undo_journal = b.dependency(
        "do_undo_journal",
        .{
            .target = target,
            .optimize = optimize,
        },
    );

    const dep_imanim = b.dependency(
        "imanim",
        .{
            .target = target,
            .optimize = optimize,
        },
    );

    // inject the cimgui header search path into the sokol C library compile step
    dep_sokol.artifact("sokol_clib").addIncludePath(
        dep_cimgui.path(cimgui_conf.include_dir)
    );

    // Assemble Module
    ///////////////////////////////////////////////////////////////////////////

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

    lib_imgui.addIncludePath(dep_sokol.path("src/sokol/c"));

    const cflags = [_][]const u8 {
        "-fno-sanitize=undefined",
        "-Wno-elaborated-enum-base",
        "-Wno-error=date-time",
    };

    lib_imgui.addCSourceFiles(
        .{
            .root = b.path("src"),
            .files = &.{
                 "zgui.cpp",
                 "zplot.cpp",
                 "zanim.cpp",
            },
            .flags = &cflags,
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
            .flags = &cflags,
        },
    );
    lib_imgui.addIncludePath(
        dep_cimgui.path("src"),
    );
    lib_imgui.addIncludePath(
        dep_implot.path("implot.h").dirname(),
    );
    lib_imgui.addIncludePath(
        dep_imanim.path("im_anim.h").dirname(),
    );

    lib_imgui.addCSourceFiles(
        .{
            .root = dep_imanim.path("."),
            .files = &.{
                "im_anim.cpp",
                "im_anim_demo.cpp",
            },
            .flags = &cflags,
        },
    );

    mod_ziis.linkLibrary(lib_cimgui);
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

    // for zls -- "check" step
    const check_step = b.step(
        "check",
        "Check if everything compiles",
    );

    // Dispatch to build function based on target
    ///////////////////////////////////////////////////////////////////////////

    // from here on different handling for native vs wasm builds
    if (target.result.cpu.arch.isWasm())
    {
        const run_step = try build_wasm(
            b,
            .{
                .app_name = "demo",
                .mod_main = mod_app_wrapper,
                .dep_ziis_builder = b,
                .target = target,
                .optimize = optimize,
                .dep_c_libs = &.{
                    lib_cimgui,
                    lib_imgui,
                },
            },
        );

        // install example.json and source file for examples
        run_step.dependOn(
            &(
                b.addInstallFile(
                    b.path("example.json"),
                    "web/example.json",
                ).step
            )
        );
        run_step.dependOn(
            &(
                b.addInstallFile(
                    b.path("src/app_wrapper_demo.zig"),
                    "web/src/app_wrapper_demo.zig",
                ).step
            )
        );
    }
    else
    {
        try build_native(
            b,
            mod_app_wrapper,
            check_step,
        );
    }
}

/// Build for native (non-wasm) target
fn build_native(
    b: *std.Build,
    mod: *std.Build.Module,
    check_step: *std.Build.Step,
) !void 
{
    const exe = b.addExecutable(
        .{
            .name = "demo",
            .root_module = mod,
        },
    );
    check_step.dependOn(&exe.step);
    b.installArtifact(exe);
    var run_step = b.step(
        "run",
        "Run demo"
    );

    run_step.dependOn(&b.addRunArtifact(exe).step);
}

/// Build for WASM
pub fn build_wasm(
    outer_builder: *std.Build,
    opts: struct {
        mod_main: *std.Build.Module,
        app_name: []const u8,
        /// call dep_ziis.builder and pass that here
        dep_ziis_builder: *std.Build,
        target: std.Build.ResolvedTarget,
        optimize: std.builtin.OptimizeMode,
        dep_c_libs: []const *std.Build.Step.Compile,
    },
) !*std.Build.Step 
{
    // build the main file into a library, this is because the WASM 'exe'
    // needs to be linked in a separate build step with the Emscripten linker
    const main_app = outer_builder.addLibrary(
        .{
            .name = opts.app_name,
            .root_module = opts.mod_main,
        },
    );

    const dep_sokol = opts.dep_ziis_builder.dependency(
        "sokol",
        .{
            .target = opts.target,
            .optimize = opts.optimize,
            .with_sokol_imgui = true,
        }
    );

    // get the Emscripten SDK dependency from the sokol dependency
    const dep_emsdk = dep_sokol.builder.dependency(
        "emsdk",
        .{},
    );

    // need to inject the Emscripten system header include path into
    // the cimgui C library otherwise the C/C++ code won't find
    // C stdlib headers
    const emsdk_incl_path = dep_emsdk.path(
        "upstream/emscripten/cache/sysroot/include",
    );

    // all C libraries need to depend on the sokol library, when building for
    // WASM this makes sure that the Emscripten SDK has been setup before
    // C compilation is attempted (since the sokol C library depends on the
    // Emscripten SDK setup step)
    for (opts.dep_c_libs)
        |lib|
    {
        lib.addSystemIncludePath(emsdk_incl_path);
        lib.step.dependOn(&dep_sokol.artifact("sokol_clib").step);
    }

    // create a build step which invokes the Emscripten linker
    const link_step = try sokol.emLinkStep(
        outer_builder,
        .{
            .lib_main = main_app,
            .target = opts.target,
            .optimize = opts.optimize,
            .emsdk = dep_emsdk,
            .use_webgl2 = true,
            .use_emmalloc = true,
            .use_filesystem = true,
            .use_webgpu = true,
            .shell_file_path = dep_sokol.path(
                "src/sokol/web/shell.html",
            ),
        },
    );
    // attach to default target
    outer_builder.getInstallStep().dependOn(&link_step.step);
    // ...and a special run step to start the web build output via 'emrun'
    const run = sokol.emRunStep(
        outer_builder,
        .{
            .name = opts.app_name,
            .emsdk = dep_emsdk,
        },
    );
    run.step.dependOn(&link_step.step);

    var buf:[1024]u8 = undefined;
    const name = try std.fmt.bufPrint(
        &buf,
        "run-{s}",
        .{opts.app_name}
    );
    const desc = try std.fmt.bufPrint(
        buf[name.len..],
        "Run {s} as a wasm build.",
        .{opts.app_name}
    );

    outer_builder.step(
        name,
        desc,
    ).dependOn(&run.step);

    return &run.step;
}
