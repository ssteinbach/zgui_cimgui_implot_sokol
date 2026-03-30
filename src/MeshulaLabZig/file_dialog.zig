//! File Dialog — Zig-ergonomic wrapper for native file dialogs.
//!
//! Uses nativefiledialog (NFD) on desktop platforms.
//! Not available on WASM.

const builtin = @import("builtin");

const IS_WASM = builtin.target.cpu.arch.isWasm();

pub const Error = error{
    NfdError,
    Unsupported,
};

pub const DialogResult = struct
{
    path: [:0]const u8,

    pub fn deinit(self: DialogResult) void
    {
        if (!IS_WASM)
        {
            nfd.freePath(self.path);
        }
    }
};

/// Open a single-file dialog.
/// `filter` uses semicolon-separated groups, e.g. "png,jpg;pdf".
/// Returns the selected path, or null if cancelled.
pub fn openFile(
    filter: ?[:0]const u8,
    default_path: ?[:0]const u8,
) Error!?DialogResult
{
    if (IS_WASM) return error.Unsupported;
    const maybe_path = nfd.openFileDialog(filter, default_path) catch
        return error.NfdError;
    return if (maybe_path)
        |p|
        DialogResult{ .path = p }
    else
        null;
}

/// Open a save-file dialog.
pub fn saveFile(
    filter: ?[:0]const u8,
    default_path: ?[:0]const u8,
) Error!?DialogResult
{
    if (IS_WASM) return error.Unsupported;
    const maybe_path = nfd.saveFileDialog(filter, default_path) catch
        return error.NfdError;
    return if (maybe_path)
        |p|
        DialogResult{ .path = p }
    else
        null;
}

/// Open a folder-picker dialog.
pub fn pickFolder(
    default_path: ?[:0]const u8,
) Error!?DialogResult
{
    if (IS_WASM) return error.Unsupported;
    const maybe_path = nfd.openFolderDialog(default_path) catch
        return error.NfdError;
    return if (maybe_path)
        |p|
        DialogResult{ .path = p }
    else
        null;
}

const nfd = if (!IS_WASM) @import("nfd") else struct {};
