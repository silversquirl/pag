const std = @import("std");
const ast = @import("../ast.zig");
const asts = @import("asts.zig");

test "generate parens" {
    var array = std.ArrayList(u8).init(std.testing.allocator);
    defer array.deinit();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const in_ast = try asts.parens(arena.allocator());
    try ast.generate(array.writer(), in_ast);
    try std.testing.expectEqualStrings(
        \\const pag = @import("pag");
        \\
        \\pub const WS = pag.Rule{ .prods = &.{
        \\.{ .syms = &.{
        \\.{ .set = pag.SetBuilder.init()
        \\.add(" ")
        \\.add("\t")
        \\.add("\n")
        \\.set },
        \\} },
        \\}, .kind = .ignored_token };
        \\
        \\pub const nested = pag.Rule{ .prods = &.{
        \\.{ .syms = &.{
        \\.{ .str = "(" },
        \\.{ .nt = .many },
        \\.{ .str = ")" },
        \\} },
        \\} };
        \\
        \\pub const many = pag.Rule{ .prods = &.{
        \\.{ .syms = &.{
        \\.{ .nt = .nested },
        \\.{ .nt = .many },
        \\} },
        \\.{ .syms = &.{
        \\} },
        \\} };
        \\
        \\
    , array.items);
}

test "generate hex number" {
    var array = std.ArrayList(u8).init(std.testing.allocator);
    defer array.deinit();
    try ast.generate(array.writer(), asts.hexnum);
    try std.testing.expectEqualStrings(
        \\const pag = @import("pag");
        \\
        \\const std = @import("std");
        \\
        \\pub const num = pag.Rule{ .prods = &.{
        \\.{ .syms = &.{
        \\.{ .nt = .digit },
        \\.{ .nt = .num },
        \\}, .handler = struct {
        \\pub fn match(
        \\_: void,
        \\digit: u4,
        \\num: u64,
        \\) !u64 { return num << 4 | digit; }
        \\} },
        \\.{ .syms = &.{
        \\.{ .nt = .digit },
        \\}, .handler = struct {
        \\pub fn match(
        \\_: void,
        \\digit: u4,
        \\) !u64 { return digit; }
        \\} },
        \\} };
        \\
        \\pub const digit = pag.Rule{ .prods = &.{
        \\.{ .syms = &.{
        \\.{ .set = pag.SetBuilder.init()
        \\.addRange('0', '9')
        \\.addRange('a', 'f')
        \\.addRange('A', 'F')
        \\.set },
        \\}, .handler = struct {
        \\pub fn match(
        \\_: void,
        \\ch: u21,
        \\) !u4 {
        \\  return std.fmt.parseInt(u4, &.{ch}, 16);
        \\}
        \\} },
        \\} };
        \\
        \\
    , array.items);
}

test "generate quoted string" {
    var array = std.ArrayList(u8).init(std.testing.allocator);
    defer array.deinit();
    try ast.generate(array.writer(), asts.string);
    try std.testing.expectEqualStrings(
        \\const pag = @import("pag");
        \\
        \\pub const string = pag.Rule{ .prods = &.{
        \\.{ .syms = &.{
        \\.{ .str = "\"" },
        \\.{ .nt = .@"string-chars" },
        \\.{ .str = "\"" },
        \\} },
        \\} };
        \\
        \\pub const @"string-chars" = pag.Rule{ .prods = &.{
        \\.{ .syms = &.{
        \\.{ .nt = .@"string-char" },
        \\.{ .nt = .@"string-chars" },
        \\} },
        \\.{ .syms = &.{
        \\} },
        \\} };
        \\
        \\pub const @"string-char" = pag.Rule{ .prods = &.{
        \\.{ .syms = &.{
        \\.{ .set = pag.SetBuilder.init()
        \\.add("\\")
        \\.add("\"")
        \\.invert()
        \\.set },
        \\} },
        \\.{ .syms = &.{
        \\.{ .str = "\\" },
        \\.{ .nt = .@"string-char-escaped" },
        \\} },
        \\} };
        \\
        \\pub const @"string-char-escaped" = pag.Rule{ .prods = &.{
        \\.{ .syms = &.{
        \\.{ .set = pag.SetBuilder.init()
        \\.add("\\")
        \\.add("\"")
        \\.set },
        \\} },
        \\.{ .syms = &.{
        \\.{ .str = "x" },
        \\.{ .nt = .hexdig },
        \\.{ .nt = .hexdig },
        \\} },
        \\} };
        \\
        \\pub const hexdig = pag.Rule{ .prods = &.{
        \\.{ .syms = &.{
        \\.{ .set = pag.SetBuilder.init()
        \\.addRange('0', '9')
        \\.addRange('a', 'f')
        \\.addRange('A', 'F')
        \\.set },
        \\} },
        \\} };
        \\
        \\
    , array.items);
}
