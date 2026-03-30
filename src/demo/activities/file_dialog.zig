//! File Dialog Demo Activity
//!
//! Demonstrates native file dialog integration using NFD.

const std = @import("std");
const builtin = @import("builtin");
const MeshulaLab = @import("MeshulaLab");
const MeshulaLabZig = @import("MeshulaLabZig");
const ziis = @import("zgui_cimgui_implot_sokol");
const zgui = ziis.zgui;

const FileDialog = MeshulaLabZig.FileDialog;

const IS_WASM = builtin.target.cpu.arch.isWasm();

var selected_path_buf: [1024]u8 = .{0} ** 1024;
var selected_path_len: usize = 0;
var last_status: enum { none, cancelled, err } = .none;

pub fn runUI(
    _: ?*anyopaque,
    _: ?*const MeshulaLab.ViewInteraction,
) callconv(.c) void
{
    zgui.textUnformatted("Native File Dialog Demo");
    zgui.separator();

    if (IS_WASM)
    {
        zgui.textUnformatted("File dialogs are not available on WASM.");
        return;
    }

    if (zgui.button("Open File...", .{}))
    {
        handleResult(FileDialog.openFile("png,jpg;txt;*", null));
    }

    zgui.sameLine(.{});

    if (zgui.button("Save File...", .{}))
    {
        handleResult(FileDialog.saveFile("txt;*", null));
    }

    zgui.sameLine(.{});

    if (zgui.button("Pick Folder...", .{}))
    {
        handleResult(FileDialog.pickFolder(null));
    }

    zgui.separator();

    switch (last_status)
    {
        .none =>
        {
            if (selected_path_len > 0)
            {
                zgui.text(
                    "Selected: {s}",
                    .{selected_path_buf[0..selected_path_len]},
                );
            }
            else
            {
                zgui.textUnformatted("No file selected.");
            }
        },
        .cancelled => zgui.textUnformatted("Cancelled."),
        .err => zgui.textColored(
            .{ 1, 0, 0, 1 },
            "Error opening dialog.",
            .{},
        ),
    }
}

fn handleResult(
    result: FileDialog.Error!?FileDialog.DialogResult,
) void
{
    if (result)
        |maybe_dialog|
    {
        if (maybe_dialog)
            |dialog|
        {
            defer dialog.deinit();
            const len = @min(dialog.path.len, selected_path_buf.len);
            @memcpy(selected_path_buf[0..len], dialog.path[0..len]);
            selected_path_len = len;
            last_status = .none;
        }
        else
        {
            last_status = .cancelled;
        }
    }
    else |_|
    {
        last_status = .err;
    }
}
