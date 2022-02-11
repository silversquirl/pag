const pag = @import("pag");

const std = @import("std");
const ast = @import("ast.zig");

fn ArrayBuilder(comptime T: type) type {
    return struct {
        fn build(
            allocator: std.mem.Allocator,
            elem: T,
            array: std.ArrayListUnmanaged(T),
        ) !std.ArrayListUnmanaged(T) {
            var array_var = array;
            try array_var.append(allocator, elem);
            return array_var;
        }
        fn extend(
            allocator: std.mem.Allocator,
            elems: []const T,
            array: std.ArrayListUnmanaged(T),
        ) !std.ArrayListUnmanaged(T) {
            var array_var = array;
            try array_var.appendSlice(allocator, elems);
            std.mem.reverse(T, array_var.items[array.items.len..]);
            allocator.free(elems);
            return array_var;
        }
        fn empty() std.ArrayListUnmanaged(T) {
            return .{};
        }
        fn one(allocator: std.mem.Allocator, elem: T) !std.ArrayListUnmanaged(T) {
            return build(allocator, elem, .{});
        }
        fn finish(allocator: std.mem.Allocator, array: std.ArrayListUnmanaged(T)) []const T {
            var array_var = array;
            std.mem.reverse(T, array_var.items);
            return array_var.toOwnedSlice(allocator);
        }
        fn finishDelim(allocator: std.mem.Allocator, l: u8, array: std.ArrayListUnmanaged(T), r: u8) ![]const T {
            var array_var = array;
            try array_var.append(allocator, l);
            std.mem.reverse(T, array_var.items);
            try array_var.append(allocator, r);
            return array_var.toOwnedSlice(allocator);
        }
    };
}

pub const file: pag.Rule = &.{
    .{ .syms = &.{
        .{ .nt = .@"ws?" },
        .{ .nt = .toplevel },
        .{ .nt = .file },
    }, .handler = struct {
        pub fn match(
            allocator: std.mem.Allocator,
            _: void,
            tl: ast.Toplevel,
            rest: std.ArrayListUnmanaged(ast.Toplevel),
        ) !std.ArrayListUnmanaged(ast.Toplevel) {
            _ = allocator;
            return ArrayBuilder(ast.Toplevel).build(allocator, tl, rest);
        }
    } },
    .{ .syms = &.{
        .{ .nt = .@"ws?" },
        .end,
    }, .handler = struct {
        pub fn match(
            allocator: std.mem.Allocator,
            _: void,
            _: void,
        ) !std.ArrayListUnmanaged(ast.Toplevel) {
            _ = allocator;
            return ArrayBuilder(ast.Toplevel).empty();
        }
    } },
};

pub const toplevel: pag.Rule = &.{
    .{ .syms = &.{
        .{ .nt = .pragma },
    }, .handler = struct {
        pub fn match(
            allocator: std.mem.Allocator,
            p: ast.Pragma,
        ) !ast.Toplevel {
            _ = allocator;
            return ast.Toplevel{ .pragma = p };
        }
    } },
    .{ .syms = &.{
        .{ .nt = .block },
    }, .handler = struct {
        pub fn match(
            allocator: std.mem.Allocator,
            b: []const u8,
        ) !ast.Toplevel {
            _ = allocator;
            return ast.Toplevel{ .block = b };
        }
    } },
    .{ .syms = &.{
        .{ .nt = .rule },
    }, .handler = struct {
        pub fn match(
            allocator: std.mem.Allocator,
            r: ast.Rule,
        ) !ast.Toplevel {
            _ = allocator;
            return ast.Toplevel{ .rule = r };
        }
    } },
};

pub const pragma: pag.Rule = &.{
    .{ .syms = &.{
        .{ .str = "#context" },
        .{ .nt = .ws },
        .{ .nt = .@"zig-ident" },
        .{ .nt = .@"ws?" },
        .{ .str = ":" },
        .{ .nt = .@"ws?" },
        .{ .nt = .@"zig-type" },
        .{ .nt = .@"ws?" },
        .{ .str = ";" },
    }, .handler = struct {
        pub fn match(
            allocator: std.mem.Allocator,
            _: []const u8,
            _: void,
            name: []const u8,
            _: void,
            _: []const u8,
            _: void,
            ty: []const u8,
            _: void,
            _: []const u8,
        ) !ast.Pragma {
            _ = allocator;
            return ast.Pragma{ .context = .{ .name = name, .type = ty } };
        }
    } },
};

pub const block: pag.Rule = &.{
    .{ .syms = &.{
        .{ .str = "{" },
        .{ .nt = .@"zig-code" },
        .{ .str = "}" },
    }, .handler = struct {
        pub fn match(
            allocator: std.mem.Allocator,
            _: []const u8,
            code: std.ArrayListUnmanaged(u8),
            _: []const u8,
        ) ![]const u8 {
            _ = allocator;
            return ArrayBuilder(u8).finish(allocator, code);
        }
    } },
};

pub const @"zig-code": pag.Rule = &.{
    .{ .syms = &.{
        .{ .set = &pag.SetBuilder.init()
            .add("\"")
            .add("{")
            .add("}")
            .invert()
            .set },
        .{ .nt = .@"zig-code" },
    }, .handler = struct {
        pub fn match(
            allocator: std.mem.Allocator,
            ch: u8,
            rest: std.ArrayListUnmanaged(u8),
        ) !std.ArrayListUnmanaged(u8) {
            _ = allocator;
            return ArrayBuilder(u8).build(allocator, ch, rest);
        }
    } },
    .{ .syms = &.{
        .{ .nt = .@"zig-string" },
        .{ .nt = .@"zig-code" },
    }, .handler = struct {
        pub fn match(
            allocator: std.mem.Allocator,
            str: []const u8,
            rest: std.ArrayListUnmanaged(u8),
        ) !std.ArrayListUnmanaged(u8) {
            _ = allocator;
            return ArrayBuilder(u8).extend(allocator, str, rest);
        }
    } },
    .{ .syms = &.{
        .{ .nt = .block },
        .{ .nt = .@"zig-code" },
    }, .handler = struct {
        pub fn match(
            allocator: std.mem.Allocator,
            b: []const u8,
            rest: std.ArrayListUnmanaged(u8),
        ) !std.ArrayListUnmanaged(u8) {
            _ = allocator;
            var array = rest;
            try array.ensureUnusedCapacity(allocator, b.len + 2);
            array.appendAssumeCapacity('{');
            array.appendSliceAssumeCapacity(b);
            array.appendAssumeCapacity('}');
            std.mem.reverse(u8, array.items[rest.items.len..]);
            return array;
        }
    } },
    .{ .syms = &.{}, .handler = struct {
        pub fn match(
            allocator: std.mem.Allocator,
        ) !std.ArrayListUnmanaged(u8) {
            _ = allocator;
            return ArrayBuilder(u8).empty();
        }
    } },
};

pub const @"zig-string": pag.Rule = &.{
    .{ .syms = &.{
        .{ .str = "\"" },
        .{ .nt = .@"zig-ds-chars" },
        .{ .str = "\"" },
    }, .handler = struct {
        pub fn match(
            allocator: std.mem.Allocator,
            l: u8,
            str: std.ArrayListUnmanaged(u8),
            r: u8,
        ) ![]const u8 {
            _ = allocator;
            return ArrayBuilder(u8).finishDelim(allocator, l, str, r);
        }
    } },
    .{ .syms = &.{
        .{ .str = "'" },
        .{ .nt = .@"zig-ss-chars" },
        .{ .str = "'" },
    }, .handler = struct {
        pub fn match(
            allocator: std.mem.Allocator,
            l: u8,
            str: std.ArrayListUnmanaged(u8),
            r: u8,
        ) ![]const u8 {
            _ = allocator;
            return ArrayBuilder(u8).finishDelim(allocator, l, str, r);
        }
    } },
};

pub const @"zig-ds-chars": pag.Rule = &.{
    .{ .syms = &.{
        .{ .set = &pag.SetBuilder.init()
            .add("\\")
            .add("\"")
            .invert()
            .set },
        .{ .nt = .@"zig-ds-chars" },
    }, .handler = struct {
        pub fn match(
            allocator: std.mem.Allocator,
            ch: u8,
            rest: std.ArrayListUnmanaged(u8),
        ) !std.ArrayListUnmanaged(u8) {
            _ = allocator;
            return ArrayBuilder(u8).build(allocator, ch, rest);
        }
    } },
    .{ .syms = &.{
        .{ .str = "\\" },
        .{ .set = &pag.SetBuilder.init()
            .addRange('\x00', '\xff')
            .set },
        .{ .nt = .@"zig-ss-chars" },
    }, .handler = struct {
        pub fn match(
            allocator: std.mem.Allocator,
            _: []const u8,
            ch: u8,
            rest: std.ArrayListUnmanaged(u8),
        ) !std.ArrayListUnmanaged(u8) {
            _ = allocator;
            var array = rest;
            try array.append(allocator, ch);
            try array.append(allocator, '\\');
            return array;
        }
    } },
    .{ .syms = &.{}, .handler = struct {
        pub fn match(
            allocator: std.mem.Allocator,
        ) !std.ArrayListUnmanaged(u8) {
            _ = allocator;
            return ArrayBuilder(u8).empty();
        }
    } },
};

pub const @"zig-ss-chars": pag.Rule = &.{
    .{ .syms = &.{
        .{ .set = &pag.SetBuilder.init()
            .add("\\")
            .add("'")
            .invert()
            .set },
        .{ .nt = .@"zig-ss-chars" },
    }, .handler = struct {
        pub fn match(
            allocator: std.mem.Allocator,
            ch: u8,
            rest: std.ArrayListUnmanaged(u8),
        ) !std.ArrayListUnmanaged(u8) {
            _ = allocator;
            return ArrayBuilder(u8).build(allocator, ch, rest);
        }
    } },
    .{ .syms = &.{
        .{ .str = "\\" },
        .{ .set = &pag.SetBuilder.init()
            .addRange('\x00', '\xff')
            .set },
        .{ .nt = .@"zig-ss-chars" },
    }, .handler = struct {
        pub fn match(
            allocator: std.mem.Allocator,
            _: []const u8,
            ch: u8,
            rest: std.ArrayListUnmanaged(u8),
        ) !std.ArrayListUnmanaged(u8) {
            _ = allocator;
            var array = rest;
            try array.append(allocator, ch);
            try array.append(allocator, '\\');
            return array;
        }
    } },
    .{ .syms = &.{}, .handler = struct {
        pub fn match(
            allocator: std.mem.Allocator,
        ) !std.ArrayListUnmanaged(u8) {
            _ = allocator;
            return ArrayBuilder(u8).empty();
        }
    } },
};

pub const rule: pag.Rule = &.{
    .{ .syms = &.{
        .{ .nt = .ident },
        .{ .nt = .@"ws?" },
        .{ .nt = .@"type-annotation?" },
        .{ .nt = .@"ws?" },
        .{ .str = "=" },
        .{ .nt = .@"ws?" },
        .{ .nt = .productions },
        .{ .nt = .@"ws?" },
        .{ .str = ";" },
    }, .handler = struct {
        pub fn match(
            allocator: std.mem.Allocator,
            name: []const u8,
            _: void,
            ty: ?[]const u8,
            _: void,
            _: []const u8,
            _: void,
            prods: std.ArrayListUnmanaged(ast.Production),
            _: void,
            _: []const u8,
        ) !ast.Rule {
            _ = allocator;
            return ast.Rule{
                .name = name,
                .type = ty orelse "void",
                .prods = ArrayBuilder(ast.Production).finish(allocator, prods),
            };
        }
    } },
};

pub const productions: pag.Rule = &.{
    .{ .syms = &.{
        .{ .nt = .production },
        .{ .nt = .@"ws?" },
        .{ .str = "|" },
        .{ .nt = .@"ws?" },
        .{ .nt = .productions },
    }, .handler = struct {
        pub fn match(
            allocator: std.mem.Allocator,
            prod: ast.Production,
            _: void,
            _: []const u8,
            _: void,
            rest: std.ArrayListUnmanaged(ast.Production),
        ) !std.ArrayListUnmanaged(ast.Production) {
            _ = allocator;
            return ArrayBuilder(ast.Production).build(allocator, prod, rest);
        }
    } },
    .{ .syms = &.{
        .{ .nt = .production },
    }, .handler = struct {
        pub fn match(
            allocator: std.mem.Allocator,
            prod: ast.Production,
        ) !std.ArrayListUnmanaged(ast.Production) {
            _ = allocator;
            return ArrayBuilder(ast.Production).one(allocator, prod);
        }
    } },
};

pub const production: pag.Rule = &.{
    .{ .syms = &.{
        .{ .nt = .symbols },
        .{ .nt = .@"ws?" },
        .{ .nt = .@"func?" },
    }, .handler = struct {
        pub fn match(
            allocator: std.mem.Allocator,
            syms: std.ArrayListUnmanaged(ast.Symbol),
            _: void,
            func: ?ast.Func,
        ) !ast.Production {
            _ = allocator;
            return ast.Production{
                .syms = ArrayBuilder(ast.Symbol).finish(allocator, syms),
                .func = func,
            };
        }
    } },
};

pub const symbols: pag.Rule = &.{
    .{ .syms = &.{
        .{ .nt = .symbol },
        .{ .nt = .@"ws?" },
        .{ .nt = .symbols },
    }, .handler = struct {
        pub fn match(
            allocator: std.mem.Allocator,
            sym: ast.Symbol,
            _: void,
            rest: std.ArrayListUnmanaged(ast.Symbol),
        ) !std.ArrayListUnmanaged(ast.Symbol) {
            _ = allocator;
            return ArrayBuilder(ast.Symbol).build(allocator, sym, rest);
        }
    } },
    .{ .syms = &.{}, .handler = struct {
        pub fn match(
            allocator: std.mem.Allocator,
        ) !std.ArrayListUnmanaged(ast.Symbol) {
            _ = allocator;
            return ArrayBuilder(ast.Symbol).empty();
        }
    } },
};

pub const symbol: pag.Rule = &.{
    .{ .syms = &.{
        .{ .nt = .ident },
    }, .handler = struct {
        pub fn match(
            allocator: std.mem.Allocator,
            id: []const u8,
        ) !ast.Symbol {
            _ = allocator;
            return ast.Symbol{ .nt = id };
        }
    } },
    .{ .syms = &.{
        .{ .nt = .string },
    }, .handler = struct {
        pub fn match(
            allocator: std.mem.Allocator,
            str: []const u8,
        ) !ast.Symbol {
            _ = allocator;
            return ast.Symbol{ .str = str };
        }
    } },
    .{ .syms = &.{
        .{ .nt = .set },
    }, .handler = struct {
        pub fn match(
            allocator: std.mem.Allocator,
            s: ast.Set,
        ) !ast.Symbol {
            _ = allocator;
            return ast.Symbol{ .set = s };
        }
    } },
    .{ .syms = &.{
        .{ .nt = .end },
    }, .handler = struct {
        pub fn match(
            allocator: std.mem.Allocator,
            _: void,
        ) !ast.Symbol {
            _ = allocator;
            return ast.Symbol.end;
        }
    } },
};

pub const @"func?": pag.Rule = &.{
    .{ .syms = &.{
        .{ .str = "@" },
        .{ .nt = .@"ws?" },
        .{ .str = "(" },
        .{ .nt = .@"ws?" },
        .{ .nt = .args },
        .{ .nt = .@"ws?" },
        .{ .str = ")" },
        .{ .nt = .@"ws?" },
        .{ .nt = .block },
    }, .handler = struct {
        pub fn match(
            allocator: std.mem.Allocator,
            _: []const u8,
            _: void,
            _: []const u8,
            _: void,
            a: std.ArrayListUnmanaged([]const u8),
            _: void,
            _: []const u8,
            _: void,
            b: []const u8,
        ) !?ast.Func {
            _ = allocator;
            return ast.Func{
                .args = ArrayBuilder([]const u8).finish(allocator, a),
                .code = b,
            };
        }
    } },
    .{ .syms = &.{}, .handler = struct {
        pub fn match(
            allocator: std.mem.Allocator,
        ) !?ast.Func {
            _ = allocator;
            return null;
        }
    } },
};

pub const args: pag.Rule = &.{
    .{ .syms = &.{
        .{ .nt = .@"zig-ident" },
        .{ .nt = .@"ws?" },
        .{ .str = "," },
        .{ .nt = .@"ws?" },
        .{ .nt = .args },
    }, .handler = struct {
        pub fn match(
            allocator: std.mem.Allocator,
            arg: []const u8,
            _: void,
            _: []const u8,
            _: void,
            rest: std.ArrayListUnmanaged([]const u8),
        ) !std.ArrayListUnmanaged([]const u8) {
            _ = allocator;
            return ArrayBuilder([]const u8).build(allocator, arg, rest);
        }
    } },
    .{ .syms = &.{
        .{ .nt = .@"zig-ident" },
    }, .handler = struct {
        pub fn match(
            allocator: std.mem.Allocator,
            arg: []const u8,
        ) !std.ArrayListUnmanaged([]const u8) {
            _ = allocator;
            return ArrayBuilder([]const u8).one(allocator, arg);
        }
    } },
    .{ .syms = &.{}, .handler = struct {
        pub fn match(
            allocator: std.mem.Allocator,
        ) !std.ArrayListUnmanaged([]const u8) {
            _ = allocator;
            return ArrayBuilder([]const u8).empty();
        }
    } },
};

pub const @"zig-ident": pag.Rule = &.{
    .{ .syms = &.{
        .{ .nt = .@"zig-ident-first-char" },
        .{ .nt = .@"zig-ident-rest" },
    }, .handler = struct {
        pub fn match(
            allocator: std.mem.Allocator,
            first_char: u8,
            rest: std.ArrayListUnmanaged(u8),
        ) ![]const u8 {
            _ = allocator;
            const id = try ArrayBuilder(u8).build(allocator, first_char, rest);
            return ArrayBuilder(u8).finish(allocator, id);
        }
    } },
};

pub const @"zig-ident-rest": pag.Rule = &.{
    .{ .syms = &.{
        .{ .nt = .@"zig-ident-char" },
        .{ .nt = .@"zig-ident-rest" },
    }, .handler = struct {
        pub fn match(
            allocator: std.mem.Allocator,
            ch: u8,
            rest: std.ArrayListUnmanaged(u8),
        ) !std.ArrayListUnmanaged(u8) {
            _ = allocator;
            return ArrayBuilder(u8).build(allocator, ch, rest);
        }
    } },
    .{ .syms = &.{}, .handler = struct {
        pub fn match(
            allocator: std.mem.Allocator,
        ) !std.ArrayListUnmanaged(u8) {
            _ = allocator;
            return ArrayBuilder(u8).empty();
        }
    } },
};

pub const @"zig-ident-first-char": pag.Rule = &.{
    .{ .syms = &.{
        .{ .set = &pag.SetBuilder.init()
            .addRange('a', 'z')
            .addRange('A', 'Z')
            .add("_")
            .set },
    }, .handler = struct {
        pub fn match(
            allocator: std.mem.Allocator,
            ch: u8,
        ) !u8 {
            _ = allocator;
            return ch;
        }
    } },
};

pub const @"zig-ident-char": pag.Rule = &.{
    .{ .syms = &.{
        .{ .set = &pag.SetBuilder.init()
            .addRange('a', 'z')
            .addRange('A', 'Z')
            .addRange('0', '9')
            .add("_")
            .set },
    }, .handler = struct {
        pub fn match(
            allocator: std.mem.Allocator,
            ch: u8,
        ) !u8 {
            _ = allocator;
            return ch;
        }
    } },
};

pub const @"type-annotation?": pag.Rule = &.{
    .{ .syms = &.{
        .{ .str = ":" },
        .{ .nt = .@"ws?" },
        .{ .nt = .@"zig-type" },
    }, .handler = struct {
        pub fn match(
            allocator: std.mem.Allocator,
            _: []const u8,
            _: void,
            ty: []const u8,
        ) !?[]const u8 {
            _ = allocator;
            return ty;
        }
    } },
    .{ .syms = &.{}, .handler = struct {
        pub fn match(
            allocator: std.mem.Allocator,
        ) !?[]const u8 {
            _ = allocator;
            return null;
        }
    } },
};

pub const @"zig-type": pag.Rule = &.{
    .{ .syms = &.{
        .{ .nt = .block },
    }, .handler = struct {
        pub fn match(
            allocator: std.mem.Allocator,
            ty: []const u8,
        ) ![]const u8 {
            _ = allocator;
            return ty;
        }
    } },
};

pub const ident: pag.Rule = &.{
    .{ .syms = &.{
        .{ .nt = .@"ident-internal" },
    }, .handler = struct {
        pub fn match(
            allocator: std.mem.Allocator,
            id: std.ArrayListUnmanaged(u8),
        ) ![]const u8 {
            _ = allocator;
            return ArrayBuilder(u8).finish(allocator, id);
        }
    } },
};

pub const @"ident-internal": pag.Rule = &.{
    .{ .syms = &.{
        .{ .nt = .@"ident-char" },
        .{ .nt = .@"ident-internal" },
    }, .handler = struct {
        pub fn match(
            allocator: std.mem.Allocator,
            ch: u8,
            rest: std.ArrayListUnmanaged(u8),
        ) !std.ArrayListUnmanaged(u8) {
            _ = allocator;
            return ArrayBuilder(u8).build(allocator, ch, rest);
        }
    } },
    .{ .syms = &.{
        .{ .nt = .@"ident-char" },
    }, .handler = struct {
        pub fn match(
            allocator: std.mem.Allocator,
            ch: u8,
        ) !std.ArrayListUnmanaged(u8) {
            _ = allocator;
            return ArrayBuilder(u8).one(allocator, ch);
        }
    } },
};

pub const @"ident-char": pag.Rule = &.{
    .{ .syms = &.{
        .{ .set = &pag.SetBuilder.init()
            .addRange('a', 'z')
            .addRange('A', 'Z')
            .addRange('0', '9')
            .add("?")
            .add("!")
            .add("_")
            .add("-")
            .set },
    }, .handler = struct {
        pub fn match(
            allocator: std.mem.Allocator,
            ch: u8,
        ) !u8 {
            _ = allocator;
            return ch;
        }
    } },
};

pub const string: pag.Rule = &.{
    .{ .syms = &.{
        .{ .str = "\"" },
        .{ .nt = .@"string-chars" },
        .{ .str = "\"" },
    }, .handler = struct {
        pub fn match(
            allocator: std.mem.Allocator,
            _: u8,
            str: std.ArrayListUnmanaged(u8),
            _: u8,
        ) ![]const u8 {
            _ = allocator;
            return ArrayBuilder(u8).finish(allocator, str);
        }
    } },
};

pub const @"string-chars": pag.Rule = &.{
    .{ .syms = &.{
        .{ .nt = .@"string-char" },
        .{ .nt = .@"string-chars" },
    }, .handler = struct {
        pub fn match(
            allocator: std.mem.Allocator,
            ch: u8,
            rest: std.ArrayListUnmanaged(u8),
        ) !std.ArrayListUnmanaged(u8) {
            _ = allocator;
            return ArrayBuilder(u8).build(allocator, ch, rest);
        }
    } },
    .{ .syms = &.{}, .handler = struct {
        pub fn match(
            allocator: std.mem.Allocator,
        ) !std.ArrayListUnmanaged(u8) {
            _ = allocator;
            return ArrayBuilder(u8).empty();
        }
    } },
};

pub const @"string-char": pag.Rule = &.{
    .{ .syms = &.{
        .{ .set = &pag.SetBuilder.init()
            .add("\\")
            .add("\"")
            .invert()
            .set },
    }, .handler = struct {
        pub fn match(
            allocator: std.mem.Allocator,
            ch: u8,
        ) !u8 {
            _ = allocator;
            return ch;
        }
    } },
    .{ .syms = &.{
        .{ .str = "\\" },
        .{ .nt = .@"string-char-escaped" },
    }, .handler = struct {
        pub fn match(
            allocator: std.mem.Allocator,
            _: []const u8,
            ch: u8,
        ) !u8 {
            _ = allocator;
            return ch;
        }
    } },
};

pub const @"string-char-escaped": pag.Rule = &.{
    .{ .syms = &.{
        .{ .set = &pag.SetBuilder.init()
            .add("\\")
            .add("\"")
            .set },
    }, .handler = struct {
        pub fn match(
            allocator: std.mem.Allocator,
            ch: u8,
        ) !u8 {
            _ = allocator;
            return ch;
        }
    } },
    .{ .syms = &.{
        .{ .str = "x" },
        .{ .nt = .hexdig },
        .{ .nt = .hexdig },
    }, .handler = struct {
        pub fn match(
            allocator: std.mem.Allocator,
            _: []const u8,
            h: u4,
            l: u4,
        ) !u8 {
            _ = allocator;
            return (@as(u8, h) << 4) | l;
        }
    } },
};

pub const set: pag.Rule = &.{
    .{ .syms = &.{
        .{ .str = "[" },
        .{ .nt = .@"set-invert?" },
        .{ .nt = .@"set-entries" },
        .{ .str = "]" },
    }, .handler = struct {
        pub fn match(
            allocator: std.mem.Allocator,
            _: []const u8,
            invert: bool,
            entries: std.ArrayListUnmanaged(ast.Set.Entry),
            _: []const u8,
        ) !ast.Set {
            _ = allocator;
            return ast.Set{
                .entries = ArrayBuilder(ast.Set.Entry).finish(allocator, entries),
                .invert = invert,
            };
        }
    } },
};

pub const @"set-invert?": pag.Rule = &.{
    .{ .syms = &.{
        .{ .str = "^" },
    }, .handler = struct {
        pub fn match(
            allocator: std.mem.Allocator,
            _: []const u8,
        ) !bool {
            _ = allocator;
            return true;
        }
    } },
    .{ .syms = &.{}, .handler = struct {
        pub fn match(
            allocator: std.mem.Allocator,
        ) !bool {
            _ = allocator;
            return false;
        }
    } },
};

pub const @"set-entries": pag.Rule = &.{
    .{ .syms = &.{
        .{ .nt = .@"set-entry" },
        .{ .nt = .@"set-entries" },
    }, .handler = struct {
        pub fn match(
            allocator: std.mem.Allocator,
            entry: ast.Set.Entry,
            rest: std.ArrayListUnmanaged(ast.Set.Entry),
        ) !std.ArrayListUnmanaged(ast.Set.Entry) {
            _ = allocator;
            return ArrayBuilder(ast.Set.Entry).build(allocator, entry, rest);
        }
    } },
    .{ .syms = &.{
        .{ .nt = .@"set-entry" },
    }, .handler = struct {
        pub fn match(
            allocator: std.mem.Allocator,
            entry: ast.Set.Entry,
        ) !std.ArrayListUnmanaged(ast.Set.Entry) {
            _ = allocator;
            return ArrayBuilder(ast.Set.Entry).one(allocator, entry);
        }
    } },
};

pub const @"set-entry": pag.Rule = &.{
    .{ .syms = &.{
        .{ .nt = .@"set-char" },
        .{ .str = "-" },
        .{ .nt = .@"set-char" },
    }, .handler = struct {
        pub fn match(
            allocator: std.mem.Allocator,
            start_ch: u8,
            _: []const u8,
            end_ch: u8,
        ) !ast.Set.Entry {
            _ = allocator;
            return ast.Set.Entry{ .range = .{
                .start = start_ch,
                .end = end_ch,
            } };
        }
    } },
    .{ .syms = &.{
        .{ .nt = .@"set-char" },
    }, .handler = struct {
        pub fn match(
            allocator: std.mem.Allocator,
            ch: u8,
        ) !ast.Set.Entry {
            _ = allocator;
            return ast.Set.Entry{ .ch = ch };
        }
    } },
};

pub const @"set-char": pag.Rule = &.{
    .{ .syms = &.{
        .{ .set = &pag.SetBuilder.init()
            .add("[")
            .add("]")
            .add("\\")
            .invert()
            .set },
    }, .handler = struct {
        pub fn match(
            allocator: std.mem.Allocator,
            ch: u8,
        ) !u8 {
            _ = allocator;
            return ch;
        }
    } },
    .{ .syms = &.{
        .{ .str = "\\" },
        .{ .nt = .@"set-char-escaped" },
    }, .handler = struct {
        pub fn match(
            allocator: std.mem.Allocator,
            _: []const u8,
            ch: u8,
        ) !u8 {
            _ = allocator;
            return ch;
        }
    } },
};

pub const @"set-char-escaped": pag.Rule = &.{
    .{ .syms = &.{
        .{ .set = &pag.SetBuilder.init()
            .add("[")
            .add("]")
            .add("\\")
            .set },
    }, .handler = struct {
        pub fn match(
            allocator: std.mem.Allocator,
            ch: u8,
        ) !u8 {
            _ = allocator;
            return ch;
        }
    } },
    .{ .syms = &.{
        .{ .str = "x" },
        .{ .nt = .hexdig },
        .{ .nt = .hexdig },
    }, .handler = struct {
        pub fn match(
            allocator: std.mem.Allocator,
            _: []const u8,
            h: u4,
            l: u4,
        ) !u8 {
            _ = allocator;
            return (@as(u8, h) << 4) | l;
        }
    } },
};

pub const @"ws?": pag.Rule = &.{
    .{ .syms = &.{
        .{ .nt = .ws },
    } },
    .{ .syms = &.{} },
};

pub const ws: pag.Rule = &.{
    .{ .syms = &.{
        .{ .set = &pag.SetBuilder.init()
            .add(" ")
            .add("\t")
            .add("\n")
            .set },
        .{ .nt = .@"ws?" },
    } },
    .{ .syms = &.{
        .{ .str = "//" },
        .{ .nt = .comment },
        .{ .str = "\n" },
        .{ .nt = .@"ws?" },
    } },
};

pub const comment: pag.Rule = &.{
    .{ .syms = &.{
        .{ .set = &pag.SetBuilder.init()
            .add("\n")
            .invert()
            .set },
        .{ .nt = .comment },
    } },
    .{ .syms = &.{} },
};

pub const hexdig: pag.Rule = &.{
    .{ .syms = &.{
        .{ .set = &pag.SetBuilder.init()
            .addRange('0', '9')
            .set },
    }, .handler = struct {
        pub fn match(
            allocator: std.mem.Allocator,
            ch: u8,
        ) !u4 {
            _ = allocator;
            return @intCast(u4, ch - '0');
        }
    } },
    .{ .syms = &.{
        .{ .set = &pag.SetBuilder.init()
            .addRange('a', 'f')
            .set },
    }, .handler = struct {
        pub fn match(
            allocator: std.mem.Allocator,
            ch: u8,
        ) !u4 {
            _ = allocator;
            return @intCast(u4, ch - 'a' + 10);
        }
    } },
    .{ .syms = &.{
        .{ .set = &pag.SetBuilder.init()
            .addRange('A', 'F')
            .set },
    }, .handler = struct {
        pub fn match(
            allocator: std.mem.Allocator,
            ch: u8,
        ) !u4 {
            _ = allocator;
            return @intCast(u4, ch - 'A' + 10);
        }
    } },
};

pub const end: pag.Rule = &.{
    .{ .syms = &.{
        .{ .str = "$" },
    } },
};
