const std = @import("std");
const ast = @import("ast.zig");

pub fn main() !void {
    std.debug.print("hi\n", .{});
}

test {
    std.testing.refAllDecls(ast);
}
