//! Journaling system for dealing with undos

const std = @import("std");

const command = @import("command.zig");

/// a journal of commands that support undo/redo
const Journal = struct {
    /// sorted such that lower indices in the entries arraylist are earlier
    /// than entries with larger indices
    entries: std.ArrayList(command.Command),
    max_depth: usize,
    allocator: std.mem.Allocator,

    pub fn init(
        allocator: std.mem.Allocator,
        max_depth: usize,
    ) !Journal
    {
        var entries = std.ArrayList(command.Command).init(allocator);
        try entries.ensureTotalCapacity(max_depth);

        return .{
            .allocator = allocator,
            .entries = entries,
            .max_depth = max_depth,
        };
    }

    /// add a command to the end of the journal
    pub fn add(
        self: *@This(),
        cmd: command.Command,
    ) !void
    {
        try self.entries.append(cmd);

        if (self.entries.items.len > self.max_depth) 
        {
            var popped_thing = self.entries.orderedRemove(0);
            popped_thing.destroy(self.allocator);
        }
    }

    /// undo the last command added to the journal
     pub fn undo(
         self: *@This(),
     ) !void
     {
         if (self.entries.items.len == 0) {
             return;
         }

         const cmd = self.entries.pop().?;
         try cmd.undo();
         cmd.destroy(self.allocator);
     }

    pub fn deinit(
        self: *@This(),
    ) void
    {
        while (self.entries.items.len > 0)
        {
            const cmd = self.entries.pop();
            cmd.?.destroy(self.allocator);
        }

        self.entries.deinit();
        self.max_depth = 0;
    }
};

test "Journal Test"
{
    const TEST_TYPE = i32;
    const TEST_JOURNAL_LIMIT:usize = 3;

    var journal = try Journal.init(
        std.testing.allocator,
        TEST_JOURNAL_LIMIT, 
    );
    defer journal.deinit();

    var value: TEST_TYPE = 12;

    {
        const cmd = try command.SetValue(TEST_TYPE).init(
            std.testing.allocator,
            &value,
            142,
        );

        try cmd.do();
        try std.testing.expectEqual(142, value);

        try std.testing.expectEqual(
            TEST_JOURNAL_LIMIT,
            journal.max_depth
        );
        try std.testing.expectEqual(
            0,
            journal.entries.items.len
        );

        try journal.add(cmd);
        try std.testing.expectEqual(TEST_JOURNAL_LIMIT, journal.max_depth);
        try std.testing.expectEqual(1, journal.entries.items.len);
    }

    try journal.undo();
    try std.testing.expectEqual(TEST_JOURNAL_LIMIT, journal.max_depth);
    try std.testing.expectEqual(0, journal.entries.items.len);

    var i:TEST_TYPE = 1;
    while (i <= 5)
        : (i+=1)
    {
        const cmd = try command.SetValue(TEST_TYPE).init(
            std.testing.allocator,
            &value,
            i,
        );

        try cmd.do();
        try std.testing.expectEqual(i, value);

        try journal.add(cmd);
    }

    // should have been 1,2,3,4,5, with the resulting journal being 3,4,5
    try std.testing.expectEqual(5, value);

    try std.testing.expectEqual(TEST_JOURNAL_LIMIT, journal.max_depth);
    try std.testing.expectEqual(TEST_JOURNAL_LIMIT, journal.entries.items.len);

    while (journal.entries.items.len > 0)
        : (try journal.undo())
    {
    }

    try std.testing.expectEqual(2, value);

    try std.testing.expectEqual(TEST_JOURNAL_LIMIT, journal.max_depth);
    try std.testing.expectEqual(0, journal.entries.items.len);

}

test "Journal Test (undo/redo)"
{
    const TEST_TYPE = i32;
    const TEST_JOURNAL_LIMIT:usize = 3;

    var journal = try Journal.init(
        std.testing.allocator,
        TEST_JOURNAL_LIMIT, 
    );
    defer journal.deinit();

    var value: TEST_TYPE = 12;

    var i:TEST_TYPE = 1;
    while (i <= 5)
        : (i+=1)
    {
        const cmd = try command.SetValue(TEST_TYPE).init(
            std.testing.allocator,
            &value,
            i,
        );

        try cmd.do();
        try std.testing.expectEqual(i, value);

        try journal.add(cmd);
    }

    // should have been 1,2,3,4,5, with the resulting journal being 3,4,5
    try std.testing.expectEqual(5, value);

    try std.testing.expectEqual(TEST_JOURNAL_LIMIT, journal.max_depth);
    try std.testing.expectEqual(TEST_JOURNAL_LIMIT, journal.entries.items.len);

    // undo twice, leaving one action in the journal
    try journal.undo();
    try journal.undo();

    try std.testing.expectEqual(3, value);

    try std.testing.expectEqual(TEST_JOURNAL_LIMIT, journal.max_depth);
    try std.testing.expectEqual(1, journal.entries.items.len);

    try journal.redo();
}
