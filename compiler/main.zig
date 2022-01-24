const std = @import("std");
const ast = @import("ast.zig");

const MiB = 1 << 20;

pub fn main() !void {
    // Read source
    const source = try std.io.getStdIn().readToEndAlloc(std.heap.page_allocator, 100 * MiB);

    // Parse grammar
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const rules = try ast.parse(arena.allocator(), source);

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
    // Render Zig code
    const output = try zig_ast.render(std.heap.page_allocator);
    defer std.heap.page_allocator.free(output);

    // Output final code
    try std.io.getStdOut().writeAll(output);
}

test {
    std.testing.refAllDecls(ast);
}
