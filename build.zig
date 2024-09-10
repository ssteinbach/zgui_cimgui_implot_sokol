//! Build Script for ZIIS / Zig cImgui Implot Sokol Bundle

const std = @import("std");
const builtin = @import("builtin");

pub fn build(
    b: *std.Build,
) void 
{
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const build_info = struct {
        .target = target,
        .optimize = optimize,
    };

    const dep_cimgui = b.dependency(
        "cimgui",
        build_info
    );
    const dep_imgui = b.dependency(
        "imgui",
        build_info,
    );
    const dep_implot = b.dependency(
        "implot",
        build_info,
    );
    const dep_sokol = b.dependency(
        "sokol", 
        .{
            .target = target,
            .optimize = optimize,
            .with_sokol_imgui = true,
        }
    );

    // create file tree for cimgui and imgui
    const wf = b.addNamedWriteFiles("cimgui");
    _ = wf.addCopyDirectory(
        dep_cimgui.namedWriteFiles("cimgui").getDirectory(),
        "",
        .{},
    );
    _ = wf.addCopyDirectory(
        dep_imgui.namedWriteFiles("imgui").getDirectory(),
        "imgui",
        .{},
    );
    _ = wf.addCopyDirectory(
        dep_implot.namedWriteFiles("implot").getDirectory(),
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
    lib_cimgui.linkLibCpp();
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
            .target = b.host,
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

    if (target.result.isWasm()) 
    {
        // get the Emscripten SDK dependency from the sokol dependency
        const dep_emsdk = b.dependency(
            "sokol",
            build_info,
        ).builder.dependency(
        "emsdk",
        build_info
        );

        // need to inject the Emscripten system header include path into the
        // cimgui C library otherwise the C/C++ code won't find C stdlib
        // headers
        const emsdk_incl_path = dep_emsdk.path(
            "upstream/emscripten/cache/sysroot/include"
        );
        mod_zgui_cimgui_implot_sokol.addSystemIncludePath(emsdk_incl_path);
        lib_cimgui.addSystemIncludePath(emsdk_incl_path);
    }
}

const sokol = @import("sokol");
pub const emLinkStep = sokol.emLinkStep;
pub const emRunStep = sokol.emRunStep;

pub fn fetchEmSdk(
    dep_ziis: *std.Build.Dependency,
)  *std.Build.Dependency
{
    return dep_ziis.builder.dependency(
        "sokol",
        .{}
    ).builder.dependency("emsdk", .{});
}
pub fn fetchShellPath(
    dep_ziis: *std.Build.Dependency,
)  std.Build.LazyPath
{
    return dep_ziis.builder.dependency(
        "sokol",
        .{}
    ).path("src/sokol/web/shell.html");
}
