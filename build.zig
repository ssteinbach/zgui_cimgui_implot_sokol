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

    const mod_ziis = b.createModule(
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

    // const dep_imgui = b.dependency(
    //     "imgui",
    //     .{
    //         .target = target,
    //         .optimize = optimize,
    //     }
    // );

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
                }
            ),
        }
    );

    lib_imgui.addCSourceFiles(
        .{
            .root = b.path("src"),
            .files = &.{
                b.pathJoin(&.{ "zgui.cpp" }),
                b.pathJoin(&.{ "zplot.cpp" }),
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
    b.installArtifact(lib_imgui);
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
    const mod_options = b.addOptions();
    mod_app_wrapper.addOptions(
        "build_options",
        mod_options
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

// const std = @import("std");
// const builtin = @import("builtin");
// const cimgui = @import("cimgui");
//
// pub fn build(
//     b: *std.Build,
// ) void 
// {
//     const target = b.standardTargetOptions(.{});
//     const optimize = b.standardOptimizeOption(.{});
//
//     const opt_docking = b.option(
//         bool,
//         "docking",
//         "Build with docking support"
//     ) orelse false;
//     const cimgui_conf = cimgui.getConfig(opt_docking);
//
//     const dep_cimgui = b.dependency(
//         "cimgui",
//         .{
//             .target = target,
//             .optimize = optimize,
//         }
//     );
//     const dep_imgui = b.dependency(
//         "imgui",
//         .{
//             .target = target,
//             .optimize = optimize,
//         }
//     );
//     const dep_implot = b.dependency(
//         "implot",
//         .{
//             .target = target,
//             .optimize = optimize,
//         }
//     );
//     const dep_sokol = b.dependency(
//         "sokol", 
//         .{
//             .target = target,
//             .optimize = optimize,
//             .with_sokol_imgui = true,
//         }
//     );
//     dep_sokol.artifact("sokol_clib").addIncludePath(
//         dep_cimgui.path(cimgui_conf.include_dir)
//     );
//
//     const dep_undo_journal = b.dependency(
//         "do_undo_journal",
//         .{
//             .target = target,
//             .optimize = optimize,
//         },
//     );
//
//     // because imgui and cimgui make assupmtions about file layout and
//     // submodules (meaning they assume that imgui is in a subdirectory called
//     // "imgui", rather at the top of the structure the way the dependency is
//     // there, create file tree for cimgui and imgui
//     const wf = b.addNamedWriteFiles("cimgui");
//     _ = wf.addCopyDirectory(
//         dep_cimgui.path("."),
//         ".",
//         .{},
//     );
//     _ = wf.addCopyDirectory(
//         dep_imgui.path("."),
//         "imgui",
//         .{},
//     );
//     _ = wf.addCopyDirectory(
//         dep_implot.path("."),
//         "implot",
//         .{}
//     );
//     const root = wf.getDirectory();
//
//     // build cimgui as C/C++ library
//     const core_mod_cimgui = b.addModule(
//         "cimgui_clib",
//         .{
//             .target = target,
//             .optimize = optimize,
//             .link_libc = true,
//         }
//     );
//     core_mod_cimgui.addIncludePath(root.path(b, "imgui"));
//     core_mod_cimgui.addIncludePath(root.path(b, "implot"));
//     core_mod_cimgui.addCSourceFiles(
//         .{
//             .root = root,
//             .files = &.{
//                 b.pathJoin(&.{"cimgui.cpp"}),
//                 b.pathJoin(&.{ "imgui",  "imgui.cpp" }),
//                 b.pathJoin(&.{ "imgui",  "imgui_widgets.cpp" }),
//                 b.pathJoin(&.{ "imgui",  "imgui_draw.cpp" }),
//                 b.pathJoin(&.{ "imgui",  "imgui_tables.cpp" }),
//                 b.pathJoin(&.{ "imgui",  "imgui_demo.cpp" }),
//                 b.pathJoin(&.{ "implot", "implot.cpp" }),
//                 b.pathJoin(&.{ "implot", "implot_demo.cpp" }),
//                 b.pathJoin(&.{ "implot", "implot_items.cpp" }),
//             },
//         }
//     );
//     core_mod_cimgui.addIncludePath(root);
//
//     const lib_cimgui = b.addLibrary(
//         .{
//             .linkage = .static,
//             .root_module = core_mod_cimgui,
//             .name = "cimgui_clib"
//         },
//     );
//
//     // inject the cimgui header search path into the sokol C library compile
//     // step
//     const cimgui_root = wf.getDirectory();
//     dep_sokol.artifact("sokol_clib").addIncludePath(cimgui_root);
//
//     // make cimgui available as artifact, this then allows to inject the
//     // Emscripten include path in another build.zig
//     b.installArtifact(lib_cimgui);
//
//     // lib compilation depends on file tree
//     lib_cimgui.step.dependOn(&wf.step);
//
//     // translate-c the cimgui.h file
//     // NOTE: always run this with the host target, that way we don't need to
//     // inject the Emscripten SDK include path into the translate-C step when
//     // building for WASM
//     // const cimgui_h = dep_cimgui.path("cimgui.h");
//     // const translate_c = b.addTranslateC(
//     //     .{
//     //         .root_source_file = cimgui_h,
//     //         .target = target,
//     //         .optimize = optimize,
//     //     }
//     // );
//     // translate_c.defineCMacroRaw("CIMGUI_DEFINE_ENUMS_AND_STRUCTS=\"\"");
//     // const entrypoint = translate_c.getOutput();
//
//     // build cimgui as a module with the header file as the entrypoint
//     // const mod_cimgui = b.addModule(
//     //     "cimgui",
//     //     .{
//     //         .root_source_file = entrypoint,
//     //         .target = target,
//     //         .optimize = optimize,
//     //         .link_libc = true,
//     //         .link_libcpp = true,
//     //     }
//     // );
//     // mod_cimgui.linkLibrary(lib_cimgui);
//
//     const mod_zgui_cimgui_implot_sokol = b.addModule(
//         "zgui_cimgui_implot_sokol",
//         .{
//             .root_source_file = b.path("src/root.zig"),
//             .target = target,
//             .optimize = optimize,
//             .link_libc = true,
//             .link_libcpp = true,
//         },
//     );
//     mod_zgui_cimgui_implot_sokol.addCSourceFiles(
//         .{
//             .root = b.path("src"),
//             .files = &.{
//                 b.pathJoin(&.{ "zgui.cpp" }),
//                 b.pathJoin(&.{ "zplot.cpp" }),
//             },
//         }
//     );
//
//     mod_zgui_cimgui_implot_sokol.addIncludePath(
//         root.path(b, "imgui")
//     );
//     mod_zgui_cimgui_implot_sokol.addIncludePath(
//         root.path(b, "implot")
//     );
//     mod_zgui_cimgui_implot_sokol.addImport(
//         "cimgui",
//         dep_cimgui.module(cimgui_conf.module_name),
//     );
//     mod_zgui_cimgui_implot_sokol.addImport(
//         "sokol",
//         dep_sokol.module("sokol"),
//     );
//     mod_zgui_cimgui_implot_sokol.addImport(
//         "undo",
//         dep_undo_journal.module("do_undo_journal")
//
//     );
//
//     lib_cimgui.step.dependOn(&dep_sokol.artifact("sokol_clib").step);
//     lib_cimgui.linkLibCpp();
//
//     if (target.result.cpu.arch.isWasm()) 
//     {
//         try build_demo_wasm(
//             b,
//             target,
//             optimize,
//             mod_zgui_cimgui_implot_sokol,
//             // translate_c,
//             lib_cimgui,
//             dep_sokol
//         );
//     }
//     else 
//     {
//         try build_demo_native(
//             b,
//             target,
//             optimize,
//             mod_zgui_cimgui_implot_sokol,
//         );
//     }
// }
//
// fn build_demo_native(
//     b: *std.Build,
//     target: std.Build.ResolvedTarget,
//     optimize: std.builtin.OptimizeMode,
//     mod_zgui_cimgui_implot_sokol: *std.Build.Module,
// ) !void
// {
//     // app wrapper demo executable
//     const exe_mod= b.addModule(
//         "app_wrapper_demo",
//         .{
//             .optimize = optimize,
//             .target = target,
//             .root_source_file = b.path("src/app_wrapper_demo.zig"),
//         },
//     );
//     exe_mod.addImport(
//         "zgui_cimgui_implot_sokol",
//         mod_zgui_cimgui_implot_sokol
//     );
//     const exe = b.addExecutable(
//         .{
//             .name = "app_wrapper_demo",
//             .root_module = exe_mod,
//         },
//     );
//     b.installArtifact(exe);
//
//     const run_demo_cmd = b.addRunArtifact(exe);
//     run_demo_cmd.step.dependOn(b.getInstallStep());
//
//     const run_demo_step = b.step(
//         "run",
//         "Run the app wrapper demo"
//     );
//     run_demo_step.dependOn(&run_demo_cmd.step);
// }
//
// fn build_demo_wasm(
//     b: *std.Build,
//     target: std.Build.ResolvedTarget,
//     optimize: std.builtin.OptimizeMode,
//     mod_zgui_cimgui_implot_sokol: *std.Build.Module,
//     // translate_c: *std.Build.Step.TranslateC,
//     lib_cimgui: *std.Build.Step.Compile,
//     dep_sokol: *std.Build.Dependency,
// ) !void
// {
//     const exe = b.addModule(
//         "app_wrapper_demo",
//         .{
//             .optimize = optimize,
//             .target = target,
//             .root_source_file = b.path("src/app_wrapper_demo.zig"),
//         },
//     );
//
//     const exe_lib = b.addLibrary(
//         .{
//             .linkage = .static,
//             .name = "app_wrapper_demo",
//             .root_module = exe,
//         },
//     );
//
//     exe.addImport(
//         "zgui_cimgui_implot_sokol",
//         mod_zgui_cimgui_implot_sokol
//     );
//
//     // get the Emscripten SDK dependency from the sokol dependency
//     // doing this outside of this build script would be through calling
//     //
//     const dep_emsdk = b.dependency(
//         "sokol",
//         .{
//             .target = target,
//             .optimize = optimize,
//         },
//         ).builder.dependency(
//         "emsdk",
//         .{
//             .target = target,
//             .optimize = optimize,
//         },
//         );
//
//     // need to inject the Emscripten system header include path into the
//     // cimgui C library otherwise the C/C++ code won't find C stdlib
//     // headers
//     const emsdk_incl_path = dep_emsdk.path(
//         b.pathJoin(
//             &.{
//                 "upstream", "emscripten", "cache", "sysroot", "include"
//             }
//         ),
//     );
//     // translate_c.addSystemIncludePath(emsdk_incl_path);
//
//     exe.addSystemIncludePath(emsdk_incl_path);
//
//     mod_zgui_cimgui_implot_sokol.addSystemIncludePath(emsdk_incl_path);
//     lib_cimgui.addIncludePath(emsdk_incl_path);
//
//     const link_step = try sokol.emLinkStep(
//         b,
//         .{
//             .lib_main = exe_lib,
//             .target = mod_zgui_cimgui_implot_sokol.resolved_target.?,
//             .optimize = mod_zgui_cimgui_implot_sokol.optimize.?,
//             .emsdk = dep_emsdk,
//             .use_webgl2 = true,
//             .use_emmalloc = true,
//             .use_filesystem = false,
//             .shell_file_path = dep_sokol.path("src/sokol/web/shell.html"),
//             .extra_args = &.{ "-fsanitize=undefined" },
//         }
//     );
//
//     // ...and a special run step to start the web build output via 'emrun'
//     const run = emRunStep(
//         b,
//         .{
//             .name = "app_wrapper_demo",
//             .emsdk = dep_emsdk 
//         },
//         );
//     run.step.dependOn(&link_step.step);
//     b.step("run", "Run example").dependOn(&run.step);
// }
//
// // UTILITIES FOR DOWNSTREAM PROJECTS
// ///////////////////////////////////////////////////////////////////////////////
//
// const sokol = @import("sokol");
// pub const emLinkStep = sokol.emLinkStep;
// pub const emRunStep = sokol.emRunStep;
//
// pub fn fetchEmSdk(
//     dep_ziis: *std.Build.Dependency,
//     optimize: std.builtin.Mode,
//     target: std.Build.ResolvedTarget,
// )  *std.Build.Dependency
// {
//     return dep_ziis.builder.dependency(
//         "sokol",
//         .{
//             .optimize = optimize,
//             .target = target,
//         }
//     ).builder.dependency("emsdk", .{});
// }
//
// pub fn fetchShellPath(
//     dep_ziis: *std.Build.Dependency,
//     optimize: std.builtin.Mode,
//     target: std.Build.ResolvedTarget,
// )  std.Build.LazyPath
// {
//     return dep_ziis.builder.dependency(
//         "sokol",
//         .{
//             .optimize = optimize,
//             .target = target,
//         }
//     ).path("src/sokol/web/shell.html");
// }
//
// pub fn fetchEmSdkIncludePath(
//     dep_ziis: *std.Build.Dependency,
//     optimize: std.builtin.Mode,
//     target: std.Build.ResolvedTarget,
// ) std.Build.LazyPath
// {
//     const dep_emsdk = fetchEmSdk(
//         dep_ziis,
//         optimize,
//         target,
//     );
//     return dep_emsdk.path(
//         "upstream/emscripten/cache/sysroot/include"
//     );
// }
