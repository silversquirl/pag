//! ASTs used for testing parser and generator
const ast = @import("../ast.zig");

pub const parens = ast.File{
    .header = "",
    .rules = &.{
        .{ .name = "nested", .type = "void", .prods = &.{
            .{ .syms = &.{
                .{ .str = "(" }, .{ .nt = "many" }, .{ .str = ")" },
            }, .func = null },
        } },
        .{ .name = "many", .type = "void", .prods = &.{
            .{ .syms = &.{
                .{ .nt = "nested" }, .{ .nt = "many" },
            }, .func = null },
            .{ .syms = &.{}, .func = null },
        } },
    },
    .context = .{
        .name = "_",
        .type = "void",
    },
};

pub const hexnum = ast.File{
    .header = "const std = @import(\"std\");",
    .rules = &.{
        .{ .name = "num", .type = "u64", .prods = &.{
            .{ .syms = &.{
                .{ .nt = "digit" },
                .{ .nt = "num" },
            }, .func = ast.Func{
                .args = &.{ "digit", "num" },
                .code = " return num << 4 | digit; ",
            } },
            .{ .syms = &.{
                .{ .nt = "digit" },
            }, .func = ast.Func{
                .args = &.{"digit"},
                .code = " return digit; ",
            } },
        } },
        .{ .name = "digit", .type = "u4", .prods = &.{
            .{ .syms = &.{
                .{ .set = .{ .entries = &.{
                    .{ .range = .{ .start = '0', .end = '9' } },
                    .{ .range = .{ .start = 'a', .end = 'f' } },
                    .{ .range = .{ .start = 'A', .end = 'F' } },
                }, .invert = false } },
            }, .func = ast.Func{
                .args = &.{"ch"},
                .code = "\n  return std.fmt.parseInt(u4, &.{ch}, 16);\n",
            } },
        } },
    },
    .context = .{
        .name = "_",
        .type = "void",
    },
};

pub const string = ast.File{
    .header = "",
    .rules = &.{
        .{ .name = "string", .type = "void", .prods = &.{
            .{ .syms = &.{
                .{ .set = .{ .entries = &.{.{ .ch = '"' }}, .invert = false } },
                .{ .nt = "string-chars" },
                .{ .set = .{ .entries = &.{.{ .ch = '"' }}, .invert = false } },
            }, .func = null },
        } },

        .{ .name = "string-chars", .type = "void", .prods = &.{
            .{ .syms = &.{ .{ .nt = "string-char" }, .{ .nt = "string-chars" } }, .func = null },
            .{ .syms = &.{}, .func = null },
        } },

        .{ .name = "string-char", .type = "void", .prods = &.{
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

        .{ .name = "string-char-escaped", .type = "void", .prods = &.{
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

        .{ .name = "hexdig", .type = "void", .prods = &.{
            .{ .syms = &.{
                .{ .set = .{ .entries = &.{
                    .{ .range = .{ .start = '0', .end = '9' } },
                    .{ .range = .{ .start = 'a', .end = 'f' } },
                    .{ .range = .{ .start = 'A', .end = 'F' } },
                }, .invert = false } },
            }, .func = null },
        } },
    },
    .context = .{
        .name = "_",
        .type = "void",
    },
};
