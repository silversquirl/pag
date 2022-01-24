//! ASTs used for testing parser and generator
const ast = @import("../ast.zig");

pub const parens: ast.File = &.{
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

pub const hexnum: ast.File = &.{
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

pub const string: ast.File = &.{
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
