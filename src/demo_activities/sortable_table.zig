const std = @import("std");
const MeshulaLab = @import("MeshulaLab");
const ziis = @import("zgui_cimgui_implot_sokol");
const zgui = ziis.zgui;

pub const TableRowData = struct {
    id: u32,
    name: [:0]const u8,
    quantity: i32,
    price: f32,
    is_active: bool,
};

/// Context for sorting table rows
pub const SortContext = struct {
    column: i16,
    ascending: bool,

    /// Compare two TableRowData items based on the sort column
    /// and direction.
    pub fn lessThan(
        ctx: SortContext,
        a: TableRowData,
        b: TableRowData,
    ) bool
    {
        const result = switch (ctx.column)
        {
            // ID column
            0 => std.math.order(a.id, b.id),
            // Name column
            1 => std.mem.order(u8, a.name, b.name),
            // Quantity column
            2 => std.math.order(a.quantity, b.quantity),
            // Price column
            3 => std.math.order(a.price, b.price),
            // Default
            else => .eq,
        };

        return if (ctx.ascending)
            result == .lt
        else
            result == .gt;
    }
};

// Sample data for the sortable table
pub var table_data = [_]TableRowData{
    .{
        .id = 1,
        .name = "Apples",
        .quantity = 150,
        .price = 1.25,
        .is_active = true,
    },
    .{
        .id = 2,
        .name = "Bananas",
        .quantity = 200,
        .price = 0.75,
        .is_active = true,
    },
    .{
        .id = 3,
        .name = "Cherries",
        .quantity = 50,
        .price = 4.50,
        .is_active = false,
    },
    .{
        .id = 4,
        .name = "Dates",
        .quantity = 80,
        .price = 6.00,
        .is_active = true,
    },
    .{
        .id = 5,
        .name = "Elderberries",
        .quantity = 25,
        .price = 8.99,
        .is_active = false,
    },
    .{
        .id = 6,
        .name = "Figs",
        .quantity = 120,
        .price = 3.25,
        .is_active = true,
    },
    .{
        .id = 7,
        .name = "Grapes",
        .quantity = 300,
        .price = 2.50,
        .is_active = true,
    },
    .{
        .id = 8,
        .name = "Honeydew",
        .quantity = 45,
        .price = 5.00,
        .is_active = false,
    },
};

pub fn runUI(
    _: ?*anyopaque,
    _: ?*const MeshulaLab.ViewInteraction,
) callconv(.c) void
{
    zgui.separatorText("Sortable Table Demo");

    zgui.textWrapped(
        \\Click on column headers to sort. Hold Shift to multi-sort.
        \\Columns can be resized and reordered.
        ,
        .{},
    );

    zgui.spacing();

    // Begin the table with sorting enabled
    if (
        zgui.beginTable(
            "SortableTable",
            .{
                .column = 5,
                .flags = .{
                    .sortable = true,
                    .sort_multi = true,
                    .resizable = true,
                    .reorderable = true,
                    .hideable = true,
                    .row_bg = true,
                    .borders = .{
                        .inner_h = true,
                        .inner_v = true,
                        .outer_h = true,
                        .outer_v = true,
                    },
                    .sizing = .stretch_prop,
                    .scroll_y = true,
                },
                .outer_size = .{ 0, 300 },
            },
        )
    )
    {
        defer zgui.endTable();

        // Setup columns with sorting preferences
        zgui.tableSetupColumn(
            "ID",
            .{
                .flags = .{
                    .default_sort = true,
                    .prefer_sort_ascending = true,
                },
            },
        );
        zgui.tableSetupColumn(
            "Name",
            .{
                .flags = .{ .prefer_sort_ascending = true },
            },
        );
        zgui.tableSetupColumn(
            "Quantity",
            .{
                .flags = .{ .prefer_sort_descending = true },
            },
        );
        zgui.tableSetupColumn(
            "Price",
            .{
                .flags = .{ .prefer_sort_descending = true },
            },
        );
        zgui.tableSetupColumn(
            "Active",
            .{
                .flags = .{ .no_sort = true },
            },
        );

        // Freeze header row
        zgui.tableSetupScrollFreeze(0, 1);
        zgui.tableHeadersRow();

        // Handle sorting
        if (zgui.tableGetSortSpecs())
            |sort_specs|
        {
            if (sort_specs.dirty)
            {
                // Sort the data based on specs
                const specs = (
                    sort_specs.specs[0..@intCast(sort_specs.count)]
                );
                if (specs.len > 0)
                {
                    const spec = specs[0];
                    const ascending = (
                        spec.sort_direction == .ascending
                    );

                    std.mem.sort(
                        TableRowData,
                        &table_data,
                        SortContext{
                            .column = spec.index,
                            .ascending = ascending,
                        },
                        SortContext.lessThan,
                    );
                }
                sort_specs.dirty = false;
            }
        }

        // Draw rows
        for (&table_data)
            |*row|
        {
            zgui.tableNextRow(.{});

            // ID column
            _ = zgui.tableNextColumn();
            zgui.text("{d}", .{row.id});

            // Name column
            _ = zgui.tableNextColumn();
            zgui.textUnformatted(row.name);

            // Quantity column
            _ = zgui.tableNextColumn();
            zgui.text("{d}", .{row.quantity});

            // Price column
            _ = zgui.tableNextColumn();
            zgui.text("${d:.2}", .{row.price});

            // Active column with colored indicator
            _ = zgui.tableNextColumn();
            if (row.is_active)
            {
                zgui.pushStyleColor4f(
                    .{
                        .idx = .text,
                        .c = .{ 0.0, 1.0, 0.0, 1.0 },
                    },
                );
                zgui.textUnformatted("Yes");
                zgui.popStyleColor(.{});
            }
            else
            {
                zgui.pushStyleColor4f(
                    .{
                        .idx = .text,
                        .c = .{ 1.0, 0.3, 0.3, 1.0 },
                    },
                );
                zgui.textUnformatted("No");
                zgui.popStyleColor(.{});
            }
        }
    }

    zgui.spacing();
    zgui.separator();
    zgui.spacing();

    // Summary stats
    var total_quantity: i32 = 0;
    var total_value: f32 = 0;
    var active_count: u32 = 0;

    for (&table_data)
        |row|
    {
        total_quantity += row.quantity;
        total_value += (
            @as(f32, @floatFromInt(row.quantity)) * row.price
        );
        if (row.is_active)
        {
            active_count += 1;
        }
    }

    zgui.text("Total Items: {d}", .{table_data.len});
    zgui.text("Total Quantity: {d}", .{total_quantity});
    zgui.text("Total Value: ${d:.2}", .{total_value});
    zgui.text(
        "Active Products: {d}/{d}",
        .{ active_count, table_data.len },
    );
}
