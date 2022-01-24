const std = @import("std");
const pag = @import("pag");
const rules = @import("rules.zig");

pub fn parse(allocator: std.mem.Allocator, source: []const u8) !File {
    const list = try pag.parse(rules, .file, allocator, source);
    return List(Rule).collect(list, allocator);
}

pub fn List(comptime T: type) type {
    return struct {
        value: T,
        next: ?*Self = null,

        const Self = @This();

        pub fn initAlloc(allocator: std.mem.Allocator, value: T, next: ?Self) !Self {
            return Self{
                .value = value,
                .next = if (next) |n|
                    try n.dupe(allocator)
                else
                    null,
            };
        }

        pub fn len(self: ?Self) usize {
            var node_opt = if (self) |*n| n else null;
            var i: usize = 0;
            while (node_opt) |node| {
                node_opt = node.next;
                i += 1;
            }
            return i;
        }

        /// Convert a list to a slice. Frees the entire list, unless an error occurs
        pub fn collect(self: ?Self, allocator: std.mem.Allocator) ![]T {
            const slice = try allocator.alloc(T, len(self));

            var i: usize = 0;
            var node_opt = if (self) |*n| n else null;
            while (node_opt) |node| {
                slice[i] = node.value;
                allocator.destroy(node);

                node_opt = node.next;
                i += 1;
            }

            return slice;
        }

        pub fn dupe(self: Self, allocator: std.mem.Allocator) !*Self {
            const new = try allocator.create(Self);
            new.* = self;
            return new;
        }
    };
}

pub const File = []const Rule;
pub const Rule = struct {
    name: []const u8,
    prods: []const Production,
};
pub const Production = struct {
    syms: []const Symbol,
    func: ?[]const u8,
};
pub const Symbol = union(enum) {
    end: void,
    str: []const u8,
    set: Set,
    nt: []const u8,
};
pub const Set = struct {
    entries: []const Entry,
    invert: bool,

    pub const Entry = union(enum) {
        ch: u8,
        range: struct {
            start: u8,
            end: u8,
        },
    };
};

fn expectEqualAsts(expected: File, actual: File) !void {
    try std.testing.expectEqual(expected.len, actual.len);
    for (expected) |rule_e, i| {
        const rule_a = actual[i];
        try std.testing.expectEqualStrings(rule_e.name, rule_a.name);
        try std.testing.expectEqual(rule_e.prods.len, rule_a.prods.len);
        for (rule_e.prods) |prod_e, j| {
            const prod_a = rule_a.prods[j];

            for (prod_e.syms) |sym_e, k| {
                const sym_a = prod_e.syms[k];
                try std.testing.expectEqual(@as(std.meta.Tag(Symbol), sym_e), sym_a);
                switch (sym_e) {
                    .end => {},
                    .str => |e| try std.testing.expectEqualStrings(e, sym_a.str),
                    .set => |e| {
                        try std.testing.expectEqualSlices(Set.Entry, e.entries, sym_a.set.entries);
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
    const expected: File = &.{
        .{ .name = "nested", .prods = &.{
            .{ .syms = &.{
                .{ .str = "(" }, .{ .nt = "many" }, .{ .str = ")" },
            }, .func = null },
        } },
        .{ .name = "many", .prods = &.{
            .{ .syms = &.{
                .{ .nt = "nested" }, .{ .nt = "many" },
            }, .func = null },
            .{ .syms = &.{}, .func = null },
        } },
    };

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const ast = try parse(arena.allocator(), source);
    try expectEqualAsts(expected, ast);
}

test "parse hex number" {
    const source =
        \\num   = digit num | digit;
        \\digit = [0-9a-fA-F];
    ;
    const expected: File = &.{
        .{ .name = "num", .prods = &.{
            .{ .syms = &.{ .{ .nt = "digit" }, .{ .nt = "num" } }, .func = null },
            .{ .syms = &.{.{ .nt = "digit" }}, .func = null },
        } },
        .{ .name = "digit", .prods = &.{
            .{ .syms = &.{
                .{ .set = .{ .entries = &.{
                    .{ .range = .{ .start = '0', .end = '9' } },
                    .{ .range = .{ .start = 'a', .end = 'f' } },
                    .{ .range = .{ .start = 'A', .end = 'F' } },
                }, .invert = false } },
            }, .func = null },
        } },
    };

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const ast = try parse(arena.allocator(), source);
    try expectEqualAsts(expected, ast);
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
    const expected: File = &.{
        .{ .name = "string", .prods = &.{
            .{ .syms = &.{
                .{ .set = .{ .entries = &.{.{ .ch = '"' }}, .invert = false } },
                .{ .nt = "string-chars" },
                .{ .set = .{ .entries = &.{.{ .ch = '"' }}, .invert = false } },
            }, .func = null },
        } },

        .{ .name = "string-chars", .prods = &.{
            .{ .syms = &.{ .{ .nt = "string-char" }, .{ .nt = "string-chars" } }, .func = null },
            .{ .syms = &.{}, .func = null },
        } },

        .{ .name = "string-char", .prods = &.{
            .{ .syms = &.{.{
                .set = .{
                    .entries = &.{
                        .{ .ch = '\\' },
                        .{ .ch = '"' },
                    },
                    .invert = true,
                },
            }}, .func = null },
            .{ .syms = &.{
                .{ .str = "\\" },
                .{ .nt = "string-char-escaped" },
            }, .func = null },
        } },

        .{ .name = "string-char-escaped", .prods = &.{
            .{ .syms = &.{.{
                .set = .{
                    .entries = &.{
                        .{ .ch = '\\' },
                        .{ .ch = '"' },
                    },
                    .invert = false,
                },
            }}, .func = null },
            .{ .syms = &.{
                .{ .str = "x" },
                .{ .nt = "hexdig" },
                .{ .nt = "hexdig" },
            }, .func = null },
        } },

        .{ .name = "hexdig", .prods = &.{
            .{ .syms = &.{
                .{ .set = .{ .entries = &.{
                    .{ .range = .{ .start = '0', .end = '9' } },
                    .{ .range = .{ .start = 'a', .end = 'f' } },
                    .{ .range = .{ .start = 'A', .end = 'F' } },
                }, .invert = false } },
            }, .func = null },
        } },
    };

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const ast = try parse(arena.allocator(), source);
    try expectEqualAsts(expected, ast);
}

test "parse self" {
    const source = @embedFile("rules.pag");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    _ = try parse(arena.allocator(), source);
}
