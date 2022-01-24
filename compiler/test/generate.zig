const std = @import("std");
const ast = @import("../ast.zig");
const asts = @import("asts.zig");

test "parse parens" {
    var array = std.ArrayList(u8).init(std.testing.allocator);
    defer array.deinit();
    try ast.generate(array.writer(), asts.parens);
    try std.testing.expectEqualStrings(
        \\const pag = @import("pag");
        \\
        \\pub const nested: pag.Rule = &.{
        \\.{ .syms = &.{
        \\.{ .str = "(" },
        \\.{ .nt = .many },
        \\.{ .str = ")" },
        \\} },
        \\};
        \\
        \\pub const many: pag.Rule = &.{
        \\.{ .syms = &.{
        \\.{ .nt = .nested },
        \\.{ .nt = .many },
        \\} },
        \\.{ .syms = &.{
        \\} },
        \\};
        \\
        \\
    , array.items);
}

test "parse hex number" {
    var array = std.ArrayList(u8).init(std.testing.allocator);
    defer array.deinit();
    try ast.generate(array.writer(), asts.hexnum);
    try std.testing.expectEqualStrings(
        \\const pag = @import("pag");
        \\
        \\pub const num: pag.Rule = &.{
        \\.{ .syms = &.{
        \\.{ .nt = .digit },
        \\.{ .nt = .num },
        \\} },
        \\.{ .syms = &.{
        \\.{ .nt = .digit },
        \\} },
        \\};
        \\
        \\pub const digit: pag.Rule = &.{
        \\.{ .syms = &.{
        \\.{ .set = &pag.SetBuilder.init()
        \\.addRange('0', '9')
        \\.addRange('a', 'f')
        \\.addRange('A', 'F')
        \\.set },
        \\} },
        \\};
        \\
        \\
    , array.items);
}

test "parse quoted string" {
    var array = std.ArrayList(u8).init(std.testing.allocator);
    defer array.deinit();
    try ast.generate(array.writer(), asts.string);
    try std.testing.expectEqualStrings(
        \\const pag = @import("pag");
        \\
        \\pub const string: pag.Rule = &.{
        \\.{ .syms = &.{
        \\.{ .str = "\"" },
        \\.{ .nt = .@"string-chars" },
        \\.{ .str = "\"" },
        \\} },
        \\};
        \\
        \\pub const @"string-chars": pag.Rule = &.{
        \\.{ .syms = &.{
        \\.{ .nt = .@"string-char" },
        \\.{ .nt = .@"string-chars" },
        \\} },
        \\.{ .syms = &.{
        \\} },
        \\};
        \\
        \\pub const @"string-char": pag.Rule = &.{
        \\.{ .syms = &.{
        \\.{ .set = &pag.SetBuilder.init()
        \\.add("\\")
        \\.add("\"")
        \\.invert()
        \\.set },
        \\} },
        \\.{ .syms = &.{
        \\.{ .str = "\\" },
        \\.{ .nt = .@"string-char-escaped" },
        \\} },
        \\};
        \\
        \\pub const @"string-char-escaped": pag.Rule = &.{
        \\.{ .syms = &.{
        \\.{ .set = &pag.SetBuilder.init()
        \\.add("\\")
        \\.add("\"")
        \\.set },
        \\} },
        \\.{ .syms = &.{
        \\.{ .str = "x" },
        \\.{ .nt = .hexdig },
        \\.{ .nt = .hexdig },
        \\} },
        \\};
        \\
        \\pub const hexdig: pag.Rule = &.{
        \\.{ .syms = &.{
        \\.{ .set = &pag.SetBuilder.init()
        \\.addRange('0', '9')
        \\.addRange('a', 'f')
        \\.addRange('A', 'F')
        \\.set },
        \\} },
        \\};
        \\
        \\
    , array.items);
}
