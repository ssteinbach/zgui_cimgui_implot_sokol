# ZGUI_CIMGUI_IMPLOT_SOKOL

## Overview

Bundles a set of tools for building user interfaces on desktop and WASM.

Usage:

```zig
// build.zig

const ziis = @import("zgui_cimgui_implot_sokol");

// fn build()
    // non-wasm
    const dep_ziis = b.dependency(
        "zgui_cimgui_implot_sokol",
        .{
            .target = target,
            .optimize = optimize,
        }
    );

    app.root_module.addImport(
        "zgui_cimgui_implot_sokol",
        dep_ziis.module("zgui_cimgui_implot_sokol")
    );

    // wasm
    const dep_emsdk = ziis.fetchEmSdk(dep_ziis);

    // create a build step which invokes the Emscripten linker
    const link_step = try ziis.emLinkStep(
        b,
        .{
            .lib_main = demo,
            .target = target,
            .optimize = optimize,
            .emsdk = dep_emsdk,
            .use_webgl2 = true,
            .use_emmalloc = true,
            .use_filesystem = true,
            .shell_file_path = ziis.fetchShellPath(dep_ziis),
            .extra_args = &.{
                "-sUSE_OFFSET_CONVERTER",
            },
        }
    );

    // ...and a special run step to start the web build output via 'emrun'
    const run = ziis.emRunStep(
        b,
        .{ 
            .name = "demo",
            .emsdk = dep_emsdk 
        }
    );
    run.step.dependOn(&link_step.step);
    b.step("run", "Run demo").dependOn(&run.step);
```
