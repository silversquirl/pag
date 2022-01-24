const std = @import("std");
const ast = @import("../ast.zig");
const asts = @import("asts.zig");

fn expectEqualAsts(expected: ast.File, actual: ast.File) !void {
    try std.testing.expectEqual(expected.len, actual.len);
    for (expected) |rule_e, i| {
        const rule_a = actual[i];
        try std.testing.expectEqualStrings(rule_e.name, rule_a.name);
        try std.testing.expectEqual(rule_e.prods.len, rule_a.prods.len);
        for (rule_e.prods) |prod_e, j| {
            const prod_a = rule_a.prods[j];

            for (prod_e.syms) |sym_e, k| {
                const sym_a = prod_e.syms[k];
                try std.testing.expectEqual(@as(std.meta.Tag(ast.Symbol), sym_e), sym_a);
                switch (sym_e) {
                    .end => {},
                    .str => |e| try std.testing.expectEqualStrings(e, sym_a.str),
                    .set => |e| {
                        try std.testing.expectEqualSlices(ast.Set.Entry, e.entries, sym_a.set.entries);
                        try std.testing.expectEqual(e.invert, sym_a.set.invert);
                    },
                    .nt => |e| try std.testing.expectEqualStrings(e, sym_a.nt),
                }
            }

            if (prod_e.func == null) {
                try std.testing.expectEqual(prod_e.func, prod_a.func);
            } else {
                try std.testing.expect(prod_a.func != null);
                try std.testing.expectEqualStrings(prod_e.func.?, prod_a.func.?);
            }
        }
    }
}

test "parse parens" {
    const source =
        \\nested = "(" many ")";
        \\many   = nested many | ;
    ;

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const actual = try ast.parse(arena.allocator(), source);
    try expectEqualAsts(asts.parens, actual);
}

test "parse hex number" {
    const source =
        \\num   = digit num | digit;
        \\digit = [0-9a-fA-F];
    ;

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const actual = try ast.parse(arena.allocator(), source);
    try expectEqualAsts(asts.hexnum, actual);
}

test "parse quoted string" {
    const source =
        \\string = ["] string-chars ["];
        \\string-chars = string-char string-chars | ;
        \\string-char = [^\\"] | "\\" string-char-escaped;
        \\string-char-escaped = [\\"] | "x" hexdig hexdig;
        \\
        \\hexdig = [0-9a-fA-F];
        \\
    ;

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const actual = try ast.parse(arena.allocator(), source);
    try expectEqualAsts(asts.string, actual);
}

test "parse self" {
    const source = @embedFile("../rules.pag");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    _ = try ast.parse(arena.allocator(), source);
}
