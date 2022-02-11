const std = @import("std");
const ast = @import("ast.zig");

const MiB = 1 << 20;

pub fn main() !u8 {
    // Read source
    const source = try std.io.getStdIn().readToEndAlloc(std.heap.page_allocator, 100 * MiB);

    // Parse grammar
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const rules = ast.parse(arena.allocator(), source) catch return 1;

    // Generate rules
    var array = std.ArrayList(u8).init(std.heap.page_allocator);
    defer array.deinit();
    try ast.generate(array.writer(), rules);

    // Free grammar AST
    arena.deinit();
    // Create new arena for parsing Zig code
    arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);

    // Parse Zig code
    const zig_source = try array.toOwnedSliceSentinel(0);
    defer std.heap.page_allocator.free(zig_source);
    const zig_ast = try std.zig.parse(arena.allocator(), zig_source);

    if (zig_ast.errors.len > 0) {
        std.debug.print("Generated code has errors!! TODO: properly display these with references to the pag source\n", .{});
        try std.io.getStdOut().writeAll(zig_source);
        return 1;
    } else {
        // Render Zig code
        const output = try zig_ast.render(std.heap.page_allocator);
        defer std.heap.page_allocator.free(output);

        // Output final code
        try std.io.getStdOut().writeAll(output);
        return 0;
    }
}

test {
    std.testing.refAllDecls(ast);
}
