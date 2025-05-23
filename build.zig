//! Build Script for ZIIS / Zig cImgui Implot Sokol Bundle

const std = @import("std");
const builtin = @import("builtin");

pub fn build(
    b: *std.Build,
) void 
{
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const dep_cimgui = b.dependency(
        "cimgui",
        .{
            .target = target,
            .optimize = optimize,
        }
    );
    const dep_imgui = b.dependency(
        "imgui",
        .{
            .target = target,
            .optimize = optimize,
        }
    );
    const dep_implot = b.dependency(
        "implot",
        .{
            .target = target,
            .optimize = optimize,
        }
    );
    const dep_sokol = b.dependency(
        "sokol", 
        .{
            .target = target,
            .optimize = optimize,
            .with_sokol_imgui = true,
        }
    );

    // because imgui and cimgui make assupmtions about file layout and
    // submodules (meaning they assume that imgui is in a subdirectory called
    // "imgui", rather at the top of the structure the way the dependency is
    // there, create file tree for cimgui and imgui
    const wf = b.addNamedWriteFiles("cimgui");
    _ = wf.addCopyDirectory(
        dep_cimgui.path("."),
        ".",
        .{},
    );
    _ = wf.addCopyDirectory(
        dep_imgui.path("."),
        "imgui",
        .{},
    );
    _ = wf.addCopyDirectory(
        dep_implot.path("."),
        "implot",
        .{}
    );
    const root = wf.getDirectory();

    // build cimgui as C/C++ library
    const lib_cimgui = b.addStaticLibrary(
        .{
            .name = "cimgui_clib",
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }
    );
    lib_cimgui.addIncludePath(root.path(b, "imgui"));
    lib_cimgui.addIncludePath(root.path(b, "implot"));
    lib_cimgui.addCSourceFiles(
        .{
            .root = root,
            .files = &.{
                b.pathJoin(&.{"cimgui.cpp"}),
                b.pathJoin(&.{ "imgui",  "imgui.cpp" }),
                b.pathJoin(&.{ "imgui",  "imgui_widgets.cpp" }),
                b.pathJoin(&.{ "imgui",  "imgui_draw.cpp" }),
                b.pathJoin(&.{ "imgui",  "imgui_tables.cpp" }),
                b.pathJoin(&.{ "imgui",  "imgui_demo.cpp" }),
                b.pathJoin(&.{ "implot", "implot.cpp" }),
                b.pathJoin(&.{ "implot", "implot_demo.cpp" }),
                b.pathJoin(&.{ "implot", "implot_items.cpp" }),
            },
        }
    );
    lib_cimgui.addIncludePath(root);

    // inject the cimgui header search path into the sokol C library compile
    // step
    const cimgui_root = wf.getDirectory();
    dep_sokol.artifact("sokol_clib").addIncludePath(cimgui_root);

    // make cimgui available as artifact, this then allows to inject the
    // Emscripten include path in another build.zig
    b.installArtifact(lib_cimgui);

    // lib compilation depends on file tree
    lib_cimgui.step.dependOn(&wf.step);

    // translate-c the cimgui.h file
    // NOTE: always run this with the host target, that way we don't need to
    // inject the Emscripten SDK include path into the translate-C step when
    // building for WASM
    const cimgui_h = dep_cimgui.path("cimgui.h");
    const translateC = b.addTranslateC(
        .{
            .root_source_file = cimgui_h,
            .target = target,
            .optimize = optimize,
        }
    );
    translateC.defineCMacroRaw("CIMGUI_DEFINE_ENUMS_AND_STRUCTS=\"\"");
    const entrypoint = translateC.getOutput();

    // build cimgui as a module with the header file as the entrypoint
    const mod_cimgui = b.addModule(
        "cimgui",
        .{
            .root_source_file = entrypoint,
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .link_libcpp = true,
        }
    );
    mod_cimgui.linkLibrary(lib_cimgui);

    const mod_zgui_cimgui_implot_sokol = b.addModule(
        "zgui_cimgui_implot_sokol",
        .{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .link_libcpp = true,
        },
    );
    mod_zgui_cimgui_implot_sokol.addCSourceFiles(
        .{
            .root = b.path("src"),
            .files = &.{
                b.pathJoin(&.{ "zgui.cpp" }),
                b.pathJoin(&.{ "zplot.cpp" }),
            },
        }
    );

    mod_zgui_cimgui_implot_sokol.addIncludePath(
        root.path(b, "imgui")
    );
    mod_zgui_cimgui_implot_sokol.addIncludePath(
        root.path(b, "implot")
    );
    mod_zgui_cimgui_implot_sokol.addImport(
        "cimgui",
        mod_cimgui
    );
    mod_zgui_cimgui_implot_sokol.addImport(
        "sokol",
        dep_sokol.module("sokol"),
    );
    lib_cimgui.step.dependOn(&dep_sokol.artifact("sokol_clib").step);
    lib_cimgui.linkLibCpp();

    if (target.result.cpu.arch.isWasm()) 
    {
        const exe = b.addStaticLibrary(
            .{
                .name = "app_wrapper_demo",
                .optimize = optimize,
                .target = target,
                .root_source_file = b.path("src/app_wrapper_demo.zig"),
            }
        );

        exe.root_module.addImport(
            "zgui_cimgui_implot_sokol",
            mod_zgui_cimgui_implot_sokol
        );

        // get the Emscripten SDK dependency from the sokol dependency
        // doing this outside of this build script would be through calling
        //
        const dep_emsdk = b.dependency(
            "sokol",
            .{
                .target = target,
                .optimize = optimize,
            },
        ).builder.dependency(
            "emsdk",
            .{
                .target = target,
                .optimize = optimize,
            },
        );

        // need to inject the Emscripten system header include path into the
        // cimgui C library otherwise the C/C++ code won't find C stdlib
        // headers
        const emsdk_incl_path = dep_emsdk.path(
            b.pathJoin(
                &.{
                    "upstream", "emscripten", "cache", "sysroot", "include"
                }
            ),
        );
        translateC.addSystemIncludePath(emsdk_incl_path);

        exe.addSystemIncludePath(emsdk_incl_path);

        mod_zgui_cimgui_implot_sokol.addSystemIncludePath(emsdk_incl_path);
        lib_cimgui.addIncludePath(emsdk_incl_path);

        const link_step = try sokol.emLinkStep(
            b,
            .{
                .lib_main = exe,
                .target = mod_zgui_cimgui_implot_sokol.resolved_target.?,
                .optimize = mod_zgui_cimgui_implot_sokol.optimize.?,
                .emsdk = dep_emsdk,
                .use_webgl2 = true,
                .use_emmalloc = true,
                .use_filesystem = false,
                .shell_file_path = dep_sokol.path("src/sokol/web/shell.html"),
                .extra_args = &.{ "-fsanitize=undefined" },
            }
        );

        // ...and a special run step to start the web build output via 'emrun'
        const run = emRunStep(
            b,
            .{
                .name = "app_wrapper_demo",
                .emsdk = dep_emsdk 
            },
        );
        run.step.dependOn(&link_step.step);
        b.step("run", "Run example").dependOn(&run.step);
    }
    else 
    {
        // app wrapper demo executable
        const exe = b.addExecutable(
            .{
                .name = "app_wrapper_demo",
                .optimize = optimize,
                .target = target,
                .root_source_file = b.path("src/app_wrapper_demo.zig"),
            }
        );
        exe.root_module.addImport(
            "zgui_cimgui_implot_sokol",
            mod_zgui_cimgui_implot_sokol
        );
        b.installArtifact(exe);

        const run_demo_cmd = b.addRunArtifact(exe);
        run_demo_cmd.step.dependOn(b.getInstallStep());

        const run_demo_step = b.step(
            "run",
            "Run the app wrapper demo"
        );
        run_demo_step.dependOn(&run_demo_cmd.step);
    }
}

const sokol = @import("sokol");
pub const emLinkStep = sokol.emLinkStep;
pub const emRunStep = sokol.emRunStep;

pub fn fetchEmSdk(
    dep_ziis: *std.Build.Dependency,
    optimize: std.builtin.Mode,
    target: std.Build.ResolvedTarget,
)  *std.Build.Dependency
{
    return dep_ziis.builder.dependency(
        "sokol",
        .{
            .optimize = optimize,
            .target = target,
        }
    ).builder.dependency("emsdk", .{});
}

pub fn fetchShellPath(
    dep_ziis: *std.Build.Dependency,
    optimize: std.builtin.Mode,
    target: std.Build.ResolvedTarget,
)  std.Build.LazyPath
{
    return dep_ziis.builder.dependency(
        "sokol",
        .{
            .optimize = optimize,
            .target = target,
        }
    ).path("src/sokol/web/shell.html");
}

pub fn fetchEmSdkIncludePath(
    dep_ziis: *std.Build.Dependency,
    optimize: std.builtin.Mode,
    target: std.Build.ResolvedTarget,
) std.Build.LazyPath
{
    const dep_emsdk = fetchEmSdk(
        dep_ziis,
        optimize,
        target,
    );
    return dep_emsdk.path(
        "upstream/emscripten/cache/sysroot/include"
    );
}
