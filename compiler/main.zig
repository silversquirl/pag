const std = @import("std");
const parse = @import("parse.zig");

pub fn main() !void {
    std.debug.print("hi\n", .{});
}

test {
    std.testing.refAllDecls(parse);
}
