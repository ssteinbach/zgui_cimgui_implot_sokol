//! LabLayout — parse a layout spec DSL and solve panel bounding boxes.
//!
//! The spec format uses indentation (2-space) to express hierarchy:
//!
//!     panel root
//!       direction: horizontal
//!       sizing: grow grow
//!
//!       panel main-panel
//!         sizing: grow grow
//!
//!       panel right-area
//!         direction: vertical
//!         sizing: fixed(400) grow
//!
//!         panel sidebar-panel
//!           sizing: grow grow
//!
//!         panel bottom-panel
//!           sizing: grow fixed(200)

const std = @import("std");

// -----------------------------------------------------------------
// Types
// -----------------------------------------------------------------

pub const Direction = enum {
    horizontal,
    vertical,
};

pub const SizingKind = enum {
    grow,
    fixed,
};

pub const Sizing = struct {
    w: SizingKind = .grow,
    w_fixed: f32 = 0,
    h: SizingKind = .grow,
    h_fixed: f32 = 0,
};

pub const Rect = struct {
    x: f32 = 0,
    y: f32 = 0,
    w: f32 = 0,
    h: f32 = 0,
};

pub const Panel = struct {
    name: []const u8 = "",
    direction: Direction = .vertical,
    sizing: Sizing = .{},
    rect: Rect = .{},
    depth: u8 = 0,
    parent_idx: ?u16 = null,
    first_child: ?u16 = null,
    next_sibling: ?u16 = null,
};

/// Maximum number of panels in a single layout.
const MAX_PANELS = 64;

pub const Layout = struct {
    panels: [MAX_PANELS]Panel = undefined,
    count: u16 = 0,

    // -----------------------------------------------------------------
    // Parsing
    // -----------------------------------------------------------------

    /// Parse a layout spec string into a Layout tree.
    pub fn parse(
        spec: []const u8,
    ) Layout
    {
        var layout = Layout{};
        // Track the "stack" of parent indices by depth.
        var depth_stack: [32]u16 = undefined;
        var stack_top: u8 = 0;

        var line_iter = std.mem.splitScalar(u8, spec, '\n');
        // Index of the most recently added panel — properties
        // apply to this panel.
        var current: ?u16 = null;

        while (line_iter.next())
            |raw_line|
        {
            const line = std.mem.trimEnd(u8, raw_line, &.{ ' ', '\r' });
            if (line.len == 0)
            {
                continue;
            }

            const indent = count_indent(line);
            const trimmed = std.mem.trimStart(u8, line, &.{' '});
            const depth: u8 = @intCast(indent / 2);

            if (std.mem.startsWith(u8, trimmed, "panel "))
            {
                const name = std.mem.trimStart(
                    u8,
                    trimmed["panel ".len..],
                    &.{' '},
                );

                const idx = layout.add_panel(name, depth);

                // Link into tree
                if (depth > 0 and stack_top > 0)
                {
                    // Find parent: walk stack down to depth - 1
                    var parent_depth = depth - 1;
                    while (parent_depth > 0 and
                        parent_depth >= stack_top)
                    {
                        parent_depth -= 1;
                    }
                    if (parent_depth < stack_top)
                    {
                        const parent_idx = depth_stack[parent_depth];
                        layout.panels[idx].parent_idx = parent_idx;

                        // Append as last child of parent
                        if (layout.panels[parent_idx].first_child == null)
                        {
                            layout.panels[parent_idx].first_child = idx;
                        }
                        else
                        {
                            var sib = layout.panels[parent_idx].first_child.?;
                            while (layout.panels[sib].next_sibling)
                                |ns|
                            {
                                sib = ns;
                            }
                            layout.panels[sib].next_sibling = idx;
                        }
                    }
                }

                // Push this panel onto the depth stack
                if (depth < depth_stack.len)
                {
                    depth_stack[depth] = idx;
                    stack_top = @max(stack_top, depth + 1);
                }

                current = idx;
            }
            else if (std.mem.startsWith(u8, trimmed, "direction:"))
            {
                if (current)
                    |ci|
                {
                    const val = std.mem.trimStart(
                        u8,
                        trimmed["direction:".len..],
                        &.{' '},
                    );

                    if (std.mem.eql(u8, val, "horizontal"))
                    {
                        layout.panels[ci].direction = .horizontal;
                    }
                    else
                    {
                        layout.panels[ci].direction = .vertical;
                    }
                }
            }
            else if (std.mem.startsWith(u8, trimmed, "sizing:"))
            {
                if (current)
                    |ci|
                {
                    const val = std.mem.trimStart(
                        u8,
                        trimmed["sizing:".len..],
                        &.{' '},
                    );
                    layout.panels[ci].sizing = parse_sizing(val);
                }
            }
        }

        return layout;
    }

    fn add_panel(
        self: *Layout,
        name: []const u8,
        depth: u8,
    ) u16
    {
        const idx = self.count;
        self.panels[idx] = .{
            .name = name,
            .depth = depth,
        };
        self.count += 1;
        return idx;
    }

    // -----------------------------------------------------------------
    // Solving
    // -----------------------------------------------------------------

    /// Compute bounding boxes for all panels given the available area.
    pub fn solve(
        self: *Layout,
        area: Rect,
    ) void
    {
        if (self.count == 0)
        {
            return;
        }
        self.panels[0].rect = area;
        self.solve_children(0);
    }

    fn solve_children(
        self: *Layout,
        parent_idx: u16,
    ) void
    {
        const parent = self.panels[parent_idx];
        const dir = parent.direction;
        const area = parent.rect;

        // Collect children
        var children: [MAX_PANELS]u16 = undefined;
        var child_count: u16 = 0;
        {
            var maybe_child = parent.first_child;
            while (maybe_child)
                |ci|
            {
                children[child_count] = ci;
                child_count += 1;
                maybe_child = self.panels[ci].next_sibling;
            }
        }

        if (child_count == 0)
        {
            return;
        }

        // Sum fixed sizes and count grow children along the layout axis
        var total_fixed: f32 = 0;
        var grow_count: u16 = 0;

        for (children[0..child_count])
            |ci|
        {
            const sizing = self.panels[ci].sizing;
            switch (dir)
            {
                .horizontal =>
                {
                    if (sizing.w == .fixed)
                    {
                        total_fixed += sizing.w_fixed;
                    }
                    else
                    {
                        grow_count += 1;
                    }
                },
                .vertical =>
                {
                    if (sizing.h == .fixed)
                    {
                        total_fixed += sizing.h_fixed;
                    }
                    else
                    {
                        grow_count += 1;
                    }
                },
            }
        }

        const total_axis = switch (dir)
        {
            .horizontal => area.w,
            .vertical => area.h,
        };
        const remaining = @max(0, total_axis - total_fixed);
        const grow_size = if (grow_count > 0)
            remaining / @as(f32, @floatFromInt(grow_count))
        else
            0;

        // Assign rects
        var offset: f32 = 0;

        for (children[0..child_count])
            |ci|
        {
            const sizing = self.panels[ci].sizing;

            switch (dir)
            {
                .horizontal =>
                {
                    const w = if (sizing.w == .fixed)
                        sizing.w_fixed
                    else
                        grow_size;
                    self.panels[ci].rect = .{
                        .x = area.x + offset,
                        .y = area.y,
                        .w = w,
                        .h = area.h,
                    };
                    offset += w;
                },
                .vertical =>
                {
                    const h = if (sizing.h == .fixed)
                        sizing.h_fixed
                    else
                        grow_size;
                    self.panels[ci].rect = .{
                        .x = area.x,
                        .y = area.y + offset,
                        .w = area.w,
                        .h = h,
                    };
                    offset += h;
                },
            }

            // Recurse
            self.solve_children(ci);
        }
    }

    // -----------------------------------------------------------------
    // Lookup
    // -----------------------------------------------------------------

    /// Find a panel by name. Returns its computed Rect, or null.
    pub fn find_panel(
        self: *const Layout,
        name: []const u8,
    ) ?Rect
    {
        for (self.panels[0..self.count])
            |panel|
        {
            if (std.mem.eql(u8, panel.name, name))
            {
                return panel.rect;
            }
        }
        return null;
    }
};

// -----------------------------------------------------------------
// Helpers
// -----------------------------------------------------------------

fn count_indent(
    line: []const u8,
) usize
{
    var n: usize = 0;
    for (line)
        |c|
    {
        if (c == ' ')
        {
            n += 1;
        }
        else
        {
            break;
        }
    }
    return n;
}

/// Parse "grow grow", "fixed(400) grow", "grow fixed(200)", etc.
fn parse_sizing(
    val: []const u8,
) Sizing
{
    var sizing = Sizing{};
    var token_iter = std.mem.tokenizeScalar(u8, val, ' ');

    // First token = width sizing
    if (token_iter.next())
        |tok|
    {
        if (parse_sizing_token(tok))
            |result|
        {
            sizing.w = result.kind;
            sizing.w_fixed = result.value;
        }
    }

    // Second token = height sizing
    if (token_iter.next())
        |tok|
    {
        if (parse_sizing_token(tok))
            |result|
        {
            sizing.h = result.kind;
            sizing.h_fixed = result.value;
        }
    }

    return sizing;
}

const SizingToken = struct {
    kind: SizingKind,
    value: f32,
};

fn parse_sizing_token(
    tok: []const u8,
) ?SizingToken
{
    if (std.mem.eql(u8, tok, "grow"))
    {
        return .{ .kind = .grow, .value = 0 };
    }
    if (std.mem.startsWith(u8, tok, "fixed("))
    {
        // Extract number from "fixed(400)"
        const start = "fixed(".len;
        const end = std.mem.indexOfScalar(u8, tok, ')') orelse tok.len;
        const num_str = tok[start..end];
        const value = std.fmt.parseFloat(f32, num_str) catch 0;
        return .{ .kind = .fixed, .value = value };
    }
    return null;
}

// -----------------------------------------------------------------
// Tests
// -----------------------------------------------------------------

test "Layout: parse and solve basic layout"
{
    const spec =
        \\panel root
        \\  direction: horizontal
        \\  sizing: grow grow
        \\
        \\  panel main-panel
        \\    sizing: grow grow
        \\
        \\  panel right-area
        \\    direction: vertical
        \\    sizing: fixed(400) grow
        \\
        \\    panel sidebar-panel
        \\      sizing: grow grow
        \\
        \\    panel bottom-panel
        \\      sizing: grow fixed(200)
    ;

    var layout = Layout.parse(spec);
    layout.solve(.{ .x = 0, .y = 0, .w = 1280, .h = 800 });

    // root should fill the area
    const root = layout.find_panel("root").?;
    try std.testing.expectEqual(@as(f32, 1280), root.w);
    try std.testing.expectEqual(@as(f32, 800), root.h);

    // main-panel: grow in horizontal, so 1280 - 400 = 880
    const main = layout.find_panel("main-panel").?;
    try std.testing.expectEqual(@as(f32, 880), main.w);
    try std.testing.expectEqual(@as(f32, 800), main.h);

    // right-area: fixed(400) wide
    const right = layout.find_panel("right-area").?;
    try std.testing.expectEqual(@as(f32, 400), right.w);
    try std.testing.expectEqual(@as(f32, 800), right.h);

    // sidebar: grow vertically, so 800 - 200 = 600
    const sidebar = layout.find_panel("sidebar-panel").?;
    try std.testing.expectEqual(@as(f32, 400), sidebar.w);
    try std.testing.expectEqual(@as(f32, 600), sidebar.h);

    // bottom: fixed(200) tall
    const bottom = layout.find_panel("bottom-panel").?;
    try std.testing.expectEqual(@as(f32, 400), bottom.w);
    try std.testing.expectEqual(@as(f32, 200), bottom.h);
    try std.testing.expectEqual(@as(f32, 600), bottom.y);
}
