const std = @import("std");
const demo = @import("../app_wrapper_demo.zig");
const MeshulaLab = @import("MeshulaLab");
const ziis = @import("zgui_cimgui_implot_sokol");
const zgui = ziis.zgui;

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
                        demo.STATE.TableRowData,
                        &demo.STATE.table_data,
                        demo.SortContext{
                            .column = spec.index,
                            .ascending = ascending,
                        },
                        demo.SortContext.lessThan,
                    );
                }
                sort_specs.dirty = false;
            }
        }

        // Draw rows
        for (&demo.STATE.table_data)
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

    for (&demo.STATE.table_data)
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

    zgui.text("Total Items: {d}", .{demo.STATE.table_data.len});
    zgui.text("Total Quantity: {d}", .{total_quantity});
    zgui.text("Total Value: ${d:.2}", .{total_value});
    zgui.text(
        "Active Products: {d}/{d}",
        .{ active_count, demo.STATE.table_data.len },
    );
}
