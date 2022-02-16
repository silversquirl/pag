const std = @import("std");

pub fn parse(
    comptime rules: type,
    comptime start: std.meta.DeclEnum(rules),
    context: anytype,
    text: []const u8,
) !Parser(rules, @TypeOf(context)).RuleResult(start) {
    var p = Parser(rules, @TypeOf(context)){
        .context = context,
        .text = text,
    };
    defer p.deinit();

    if (p.parse(start)) |result| {
        return result;
    } else |err| {
        const stderr = std.io.getStdErr();
        const opts = PrintErrorOpts{
            .color = stderr.supportsAnsiEscapeCodes(),
        };
        if (err == error.InvalidParse) {
            p.printError(stderr.writer(), opts) catch {};
        } else {
            p.printErrorMessage(stderr.writer(), "{s}", .{@errorName(err)}, opts) catch {};
        }
        return err;
    }
}

pub fn Parser(comptime rules: type, comptime Context: type) type {
    return struct {
        context: Context,
        text: []const u8,
        err: ?ParseError = null,

        const RuleName = std.meta.DeclEnum(rules);
        const RuleSet = std.enums.EnumSet(RuleName);
        const BaseError = error{ InvalidParse, InvalidUtf8 };
        const Self = @This();

        pub fn deinit(self: Self) void {
            if (self.err) |err| {
                err.expected.deinit();
            }
        }

        fn e(
            self: *Self,
            error_mode: ErrorMode,
            comptime normal_expected: []const []const u8,
            normal_off: usize,
        ) BaseError {
            var off = normal_off;
            var expected = normal_expected;
            switch (error_mode) {
                .none => return error.InvalidParse,
                .normal => {},
                .token => |tok| {
                    off = tok.off;
                    expected = &.{tok.name};
                },
            }

            if (self.err == null or off > self.err.?.found.off) {
                var expected_list = std.ArrayList([]const u8).init(std.heap.page_allocator);
                if (self.err) |err| {
                    expected_list = err.expected;
                    expected_list.clearRetainingCapacity();
                }

                expected_list.appendSlice(expected) catch {};
                self.err = ParseError{
                    .expected = expected_list,
                    .found = self.nextToken(off),
                };
            } else if (off < self.err.?.found.off) {
                // Do nothing; we don't want to backtrack errors
            } else {
                const list = &self.err.?.expected;
                // O(n^2) but meh it's probably not a big deal
                for (expected) |exp| {
                    const add = for (list.items) |exist| {
                        if (std.mem.eql(u8, exist, exp)) {
                            break false;
                        }
                    } else true;
                    if (add) {
                        list.append(exp) catch continue;
                    }
                }
            }

            return error.InvalidParse;
        }

        const ErrorMode = union(enum) {
            none,
            normal,
            token: struct {
                off: usize,
                name: []const u8,
            },
        };

        fn nextToken(self: *Self, off: usize) ParseError.Token {
            if (off >= self.text.len) return .{
                .off = off,
                .len = 0,
                .name = "eof",
            };

            // Match literal strings
            inline for (comptime std.meta.declarations(rules)) |decl| {
                if (!decl.is_pub) continue;
                const rule = @field(rules, decl.name);
                inline for (rule.prods) |prod| {
                    inline for (prod.syms) |sym| {
                        if (sym != .str) continue;
                        var res: SymbolResult(sym) = undefined;

                        if (self.parseSym(sym, .none, off, &res)) |len| {
                            return .{
                                .off = off,
                                .len = len,
                                .name = comptime std.fmt.comptimePrint("\"{}\"", .{
                                    std.zig.fmtEscapes(sym.str),
                                }),
                            };
                        } else |_| {}
                    }
                }
            }

            // Match token rules
            inline for (comptime std.meta.declarations(rules)) |decl| {
                if (!decl.is_pub) continue;
                const rule = @field(rules, decl.name);
                if (rule.kind != .token) continue;

                const rule_name = @field(RuleName, decl.name);
                var res: RuleResult(rule_name) = undefined;

                if (self.parseRuleInternal(rule_name, .none, off, &res)) |len| {
                    return .{
                        .off = off,
                        .len = len,
                        .name = @tagName(rule_name),
                    };
                } else |_| {}
            }

            return .{
                .off = off,
                .len = 0,
                .name = "",
            };
        }

        // TODO: offset range
        fn callbackError(self: *Self, off: usize) void {
            if (self.err) |*err| {
                err.expected.clearAndFree();
                err.found = .{
                    .off = off,
                    .len = 0,
                    .name = "",
                };
            } else {
                self.err = ParseError{
                    .expected = std.ArrayList([]const u8).init(std.heap.page_allocator),
                    .found = .{
                        .off = off,
                        .len = 0,
                        .name = "",
                    },
                };
            }
        }

        pub fn printError(self: *Self, w: anytype, opts: PrintErrorOpts) !void {
            try self.printErrorMessage(w, "{}", .{self.err.?}, opts);
        }

        pub fn printErrorMessage(
            self: *Self,
            w: anytype,
            comptime fmt: []const u8,
            args: anytype,
            opts: PrintErrorOpts,
        ) !void {
            const err = self.err.?;
            const line_pos = self.linePos(err.found.off);

            if (opts.filename) |fname| {
                try w.print("{s}:", .{fname});
            }
            try w.print("{}:\n", .{line_pos});

            {
                var n = line_pos.line;
                while (n > 0) : (n /= 10) {
                    try w.writeByte(' ');
                }
                try w.writeAll(" |\n");
            }

            // TODO: handle weird control chars properly
            const err_line = self.line(err.found.off);
            try w.print("{} | {s}\n", .{ line_pos.line, err_line });

            {
                var n = line_pos.line;
                while (n > 0) : (n /= 10) {
                    try w.writeByte(' ');
                }
                try w.writeAll(" | ");
            }

            // TODO: handle weird control chars properly
            for (err_line[0 .. line_pos.col - 1]) |c| {
                const ws: u8 = switch (c) {
                    '\t' => '\t',
                    else => ' ',
                };
                try w.print("{c}", .{ws});
            }
            {
                var i: usize = 0;
                while (i <= err.found.len -| 1) : (i += 1) {
                    try w.writeByte('^');
                }
                try w.writeByte('\n');
            }

            if (opts.color) {
                try w.writeAll("\x1b[1;31merror\x1b[0m: ");
            } else {
                try w.writeAll("error: ");
            }
            try w.print(fmt ++ "\n\n", args);
        }

        pub fn line(self: Self, off: usize) []const u8 {
            var start = off;
            while (start > 0) {
                start -= 1;
                if (self.text[start] == '\n') {
                    start += 1;
                    break;
                }
            }

            var end = off;
            while (end < self.text.len) : (end += 1) {
                if (self.text[end] == '\n') break;
            }

            return self.text[start..end];
        }

        pub fn linePos(self: Self, off: usize) LinePos {
            var pos = LinePos{ .line = 1, .col = 1 };
            for (self.text) |ch, i| {
                if (i >= off) {
                    break;
                }

                if (ch == '\n') {
                    pos.line += 1;
                    pos.col = 1;
                } else {
                    pos.col += 1;
                }
            }
            return pos;
        }

        pub fn parse(self: *Self, comptime start: RuleName) !RuleResult(start) {
            var result: RuleResult(start) = undefined;
            const n = try self.parseRule(start, 0, &result);
            if (n != self.text.len) {
                return self.e(.normal, &.{"eof"}, n);
            }
            return result;
        }

        pub fn parseRule(
            self: *Self,
            comptime rule_name: RuleName,
            off: usize,
            result: *RuleResult(rule_name),
        ) RuleError(rule_name)!usize {
            return self.parseRuleInternal(rule_name, .normal, off, result);
        }

        fn parseRuleInternal(
            self: *Self,
            comptime rule_name: RuleName,
            error_mode_in: ErrorMode,
            off: usize,
            result: *RuleResult(rule_name),
        ) !usize {
            const rule = @field(rules, @tagName(rule_name));
            const error_mode: ErrorMode = switch (error_mode_in) {
                .none, .token => error_mode_in,
                .normal => switch (rule.kind) {
                    .nonterminal => .normal,
                    .token => .{ .token = .{
                        .off = off,
                        .name = @tagName(rule_name),
                    } },
                },
            };

            inline for (rule.prods) |prod| {
                if (self.parseProd(prod, error_mode, off, result)) |n| {
                    return n;
                } else |err| switch (err) {
                    error.InvalidParse => {},
                    else => |e| return e,
                }
            }

            return error.InvalidParse;
        }

        fn parseProd(
            self: *Self,
            comptime prod: Production,
            error_mode: ErrorMode,
            off: usize,
            result: *ProdResult(prod),
        ) ProdError(prod)!usize {
            if (prod.handler) |h| {
                var args: std.meta.ArgsTuple(@TypeOf(h.match)) = undefined;
                args[0] = self.context;

                if (args.len != prod.syms.len + 1) {
                    @compileError(comptime std.fmt.comptimePrint(
                        "production match handler {} has incorrect arity (expected {}, got {})",
                        .{ @TypeOf(h.match), args.len, prod.syms.len + 1 },
                    ));
                }

                var n: usize = 0;
                inline for (prod.syms) |sym, i| {
                    const fty = @TypeOf(args[i + 1]);
                    const sty = SymbolResult(sym);
                    var res: sty = undefined;
                    n += try self.parseSym(sym, error_mode, off + n, &res);

                    if (fty == sty) {
                        args[i + 1] = res;
                    } else if (fty == u21 and sym == .str and (comptime try std.unicode.utf8CountCodepoints(sym.str)) == 1) {
                        // Special case for single char strings
                        args[i + 1] = comptime std.unicode.utf8Decode(sym.str) catch @compileError("invalid utf-8");
                    } else {
                        // Specially handle this type error for better readability
                        @compileError(comptime std.fmt.comptimePrint(
                            "expected {} to have type {s}, found {s}",
                            .{ sym, @typeName(fty), @typeName(sty) },
                        ));
                    }
                }

                const ret = @call(.{}, h.match, args);
                result.* = switch (@typeInfo(@TypeOf(ret))) {
                    .ErrorUnion => ret catch |err| {
                        self.callbackError(off);
                        return err;
                    },
                    else => ret,
                };

                return n;
            } else {
                result.*; // Assert result is *void
                var n: usize = 0;
                inline for (prod.syms) |sym| {
                    var res: SymbolResult(sym) = undefined;
                    n += try self.parseSym(sym, error_mode, off + n, &res);
                }
                return n;
            }
        }

        fn parseSym(
            self: *Self,
            comptime sym: Symbol,
            error_mode: ErrorMode,
            off: usize,
            result: *SymbolResult(sym),
        ) !usize {
            switch (sym) {
                .end => if (off >= self.text.len) {
                    return 0;
                } else {
                    return self.e(error_mode, &.{"eof"}, off);
                },
                .str => |expected| if (std.mem.startsWith(u8, self.text[off..], expected)) {
                    result.* = self.text[off .. off + expected.len];
                    return expected.len;
                } else {
                    const err_expected = comptime blk: {
                        const single = std.mem.count(u8, expected, "'");
                        const double = std.mem.count(u8, expected, "\"");
                        const fmt = if (double > single) "'{'}'" else "\"{}\"";
                        break :blk std.fmt.comptimePrint(fmt, .{
                            std.zig.fmtEscapes(expected),
                        });
                    };
                    return self.e(error_mode, &.{err_expected}, off);
                },
                .set => |set| {
                    if (off >= self.text.len) {
                        return self.e(error_mode, &.{comptime set.humanString()}, off); // TODO
                    }

                    const rune_len = std.unicode.utf8ByteSequenceLength(self.text[off]) catch {
                        self.callbackError(off);
                        return error.InvalidUtf8;
                    };
                    if (off + rune_len > self.text.len) {
                        return self.e(error_mode, &.{"utf-8 bytes"}, off);
                    }

                    const rune_bytes = self.text[off .. off + rune_len];
                    const rune = std.unicode.utf8Decode(rune_bytes) catch {
                        return self.e(error_mode, &.{"utf-8 bytes"}, off);
                    };

                    if (off < self.text.len and set.contains(rune)) {
                        result.* = rune;
                        return rune_len;
                    } else {
                        return self.e(error_mode, &.{comptime set.humanString()}, off); // TODO
                    }
                },
                .nt => |rule| return self.parseRuleInternal(rule, error_mode, off, result),
            }
        }

        pub fn RuleResult(comptime rule_name_e: RuleName) type {
            const rule_name = @tagName(rule_name_e);
            const rule = @field(rules, rule_name);

            if (rule.prods.len == 0) {
                @compileError("rule '" ++ rule_name ++ "' has no productions");
            }

            const ty = ProdResult(rule.prods[0]);
            for (rule.prods[1..]) |prod| {
                if (ProdResult(prod) != ty) {
                    @compileError("rule '" ++ rule_name ++ "' has productions of differing types");
                }
            }

            return ty;
        }

        pub fn RuleError(comptime rule_name_e: RuleName) type {
            return RuleErrorR(rule_name_e, RuleSet.init(.{}));
        }
        fn RuleErrorR(comptime rule_name_e: RuleName, comptime checked_const: RuleSet) type {
            @setEvalBranchQuota(10_000);
            var checked = checked_const;
            if (checked.contains(rule_name_e)) {
                return BaseError;
            } else {
                checked.insert(rule_name_e);
            }

            const rule_name = @tagName(rule_name_e);
            const rule = @field(rules, rule_name);

            if (rule.prods.len == 0) {
                @compileError("rule '" ++ rule_name ++ "' has no productions");
            }

            var E = BaseError;
            for (rule.prods) |prod| {
                E = E || ProdErrorR(prod, checked);
            }

            return E;
        }

        fn ProdResult(comptime prod: Production) type {
            const h = prod.handler orelse return void;
            const ret = @typeInfo(@TypeOf(h.match)).Fn.return_type.?;
            return switch (@typeInfo(ret)) {
                .ErrorUnion => |eu| eu.payload,
                else => ret,
            };
        }

        fn ProdError(comptime prod: Production) type {
            return ProdErrorR(prod, RuleSet.init(.{}));
        }
        fn ProdErrorR(comptime prod: Production, comptime checked: RuleSet) type {
            var E = BaseError;

            // Add handler errors to the set
            if (prod.handler) |h| {
                const ret = @typeInfo(@TypeOf(h.match)).Fn.return_type.?;
                switch (@typeInfo(ret)) {
                    .ErrorUnion => |eu| E = E || eu.error_set,
                    else => {},
                }
            }

            // Add symbol errors to the set
            // This is recursive without a base case, but type memoization will do magic
            for (prod.syms) |sym| {
                if (sym == .nt) {
                    E = E || RuleErrorR(sym.nt, checked);
                }
            }

            return E;
        }

        fn SymbolResult(comptime sym: Symbol) type {
            return switch (sym) {
                .end => void,
                .str => []const u8,
                .set => u21,
                .nt => |rule| RuleResult(rule),
            };
        }
    };
}

pub const PrintErrorOpts = struct {
    filename: ?[]const u8 = null,
    color: bool = false,
};

pub const LinePos = struct {
    line: usize,
    col: usize,

    pub fn format(self: LinePos, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.print("{}:{}", .{ self.line, self.col });
    }
};
pub const ParseError = struct {
    expected: std.ArrayList([]const u8),
    found: Token,

    pub const Token = struct {
        off: usize,
        len: usize,
        name: []const u8,
    };

    pub fn format(self: ParseError, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.writeAll("expected ");

        const n_exp = self.expected.items.len;
        std.debug.assert(n_exp > 0);
        for (self.expected.items) |exp, i| {
            if (i > 0) {
                if (i == n_exp - 1) {
                    try writer.writeAll(" or ");
                } else {
                    try writer.writeAll(", ");
                }
            }

            try writer.writeAll(exp);
        }

        if (self.found.name.len > 0) {
            try writer.print(", found {s}", .{self.found.name});
        }
    }
};

pub const Rule = struct {
    prods: []const Production,
    kind: Kind = .nonterminal,
    pub const Kind = enum { nonterminal, token };
};
pub const Production = struct {
    syms: []const Symbol,
    handler: ?type = null,
};
pub const Symbol = union(enum) {
    end: void,
    str: []const u8,
    set: Set,
    nt: @Type(.EnumLiteral),
};
pub const Set = struct {
    invert: bool,
    entries: []const Range,
    pub const Range = struct {
        start: u21,
        end: u21,
    };

    // FIXME: this is O(n); use a segment tree
    pub fn contains(comptime self: Set, rune: u21) bool {
        for (self.entries) |range| {
            if (range.start <= rune and range.end >= rune) {
                return !self.invert;
            }
        }
        return self.invert;
    }

    pub fn humanString(comptime self: Set) []const u8 {
        var str: []const u8 = "[";
        for (self.entries) |range| {
            if (range.start == range.end) {
                str = str ++ escapeRune(range.start);
            } else {
                str = str ++ escapeRune(range.start) ++ "-" ++ escapeRune(range.end);
            }
        }
        return str ++ "]";
    }

    fn escapeRune(comptime rune: u21) []const u8 {
        const prefix = switch (rune) {
            '-', '^', '\\', '[', ']' => "\\",
            else => "",
        };
        return std.fmt.comptimePrint("{s}{u}", .{ prefix, rune });
    }
};
pub const SetBuilder = struct {
    set: Set = .{
        .invert = false,
        .entries = &.{},
    },

    pub fn init() SetBuilder {
        return .{};
    }

    // TODO: merge adjacent ranges

    pub fn add(comptime self_const: SetBuilder, comptime str: []const u8) SetBuilder {
        var self = self_const;

        const len = std.unicode.utf8CountCodepoints(str) catch @compileError("invalid utf-8");
        var new: [len]Set.Range = undefined;
        var i = 0;

        var it = std.unicode.Utf8View.initUnchecked(str).iterator();
        while (it.nextCodepoint()) |rune| : (i += 1) {
            new[i] = .{ .start = rune, .end = rune };
        }
        std.debug.assert(i == len);

        self.set.entries = self.set.entries ++ new;
        return self;
    }

    pub fn addRune(comptime self_const: SetBuilder, comptime rune: u21) SetBuilder {
        return self_const.addRange(rune, rune);
    }

    pub fn addRange(comptime self_const: SetBuilder, comptime start: u21, comptime end: u21) SetBuilder {
        var self = self_const;
        self.set.entries = self.set.entries ++ [_]Set.Range{.{
            .start = start,
            .end = end,
        }};
        return self;
    }

    pub fn invert(comptime self_const: SetBuilder) SetBuilder {
        var self = self_const;
        if (self.set.invert) {
            @compileError("set inverted twice");
        }
        self.set.invert = true;
        return self;
    }
};

test "parens" {
    // Construct a parser for matched paren pairs
    const rules = struct {
        pub const nested = Rule{ .prods = &.{
            .{ .syms = &.{ .{ .str = "(" }, .{ .nt = .many }, .{ .str = ")" } } },
        } };
        pub const many = Rule{ .prods = &.{
            .{ .syms = &.{ .{ .nt = .nested }, .{ .nt = .many } } },
            .{ .syms = &.{} },
        } };
    };

    // Check it parses correctly
    try parse(rules, .many, {}, "");
    try parse(rules, .many, {}, "()");
    try parse(rules, .many, {}, "()()");
    try parse(rules, .many, {}, "(())");
    try parse(rules, .many, {}, "(())()");
    try parse(rules, .many, {}, "(()())");
    try parse(rules, .many, {}, "()((()())())");
    try parse(rules, .many, {}, "(()()(()()))()()(()(()())())");

    // Check it fails correctly
    try std.testing.expectError(error.InvalidParse, parse(rules, .many, {}, "("));
    try std.testing.expectError(error.InvalidParse, parse(rules, .many, {}, ")"));
    try std.testing.expectError(error.InvalidParse, parse(rules, .many, {}, "())"));
    try std.testing.expectError(error.InvalidParse, parse(rules, .many, {}, "(()"));
    try std.testing.expectError(error.InvalidParse, parse(rules, .many, {}, "()())"));
    try std.testing.expectError(error.InvalidParse, parse(rules, .many, {}, "(()(())"));
    try std.testing.expectError(error.InvalidParse, parse(rules, .many, {}, "[]"));
    try std.testing.expectError(error.InvalidParse, parse(rules, .many, {}, "([])"));
    try std.testing.expectError(error.InvalidParse, parse(rules, .many, {}, "( )"));
}

test "hex number" {
    // Construct a parser for unsigned hexadecimal numbers
    const rules = struct {
        pub const digit = Rule{ .prods = &.{
            .{ .syms = &.{
                .{ .set = SetBuilder.init()
                    .addRange('0', '9')
                    .addRange('a', 'f')
                    .addRange('A', 'F')
                    .set },
            } },
        } };
        pub const num = Rule{ .prods = &.{
            .{ .syms = &.{ .{ .nt = .digit }, .{ .nt = .num } } },
            .{ .syms = &.{.{ .nt = .digit }} },
        } };
    };

    // Check it parses correctly
    try parse(rules, .num, {}, "0");
    try parse(rules, .num, {}, "0123456789abcdefABCDEF");
    try parse(rules, .num, {}, "A0");
    try parse(rules, .num, {}, "aF0Ab");

    // Check it fails correctly
    try std.testing.expectError(error.InvalidParse, parse(rules, .num, {}, ""));
    try std.testing.expectError(error.InvalidParse, parse(rules, .num, {}, "x"));
    try std.testing.expectError(error.InvalidParse, parse(rules, .num, {}, "abcdefg"));
    try std.testing.expectError(error.InvalidParse, parse(rules, .num, {}, "0829an"));
    try std.testing.expectError(error.InvalidParse, parse(rules, .num, {}, "ab de"));
    try std.testing.expectError(error.InvalidParse, parse(rules, .num, {}, "G"));
    try std.testing.expectError(error.InvalidParse, parse(rules, .num, {}, "aH"));
}

test "quoted string" {
    // Construct a parser for quoted strings
    const rules = struct {
        pub const string = Rule{ .prods = &.{
            .{ .syms = &.{ .{ .str = "\"" }, .{ .nt = .chars }, .{ .str = "\"" } } },
        } };
        pub const chars = Rule{ .prods = &.{
            .{ .syms = &.{ .{ .nt = .char }, .{ .nt = .chars } } },
            .{ .syms = &.{} },
        } };
        pub const char = Rule{ .prods = &.{
            .{ .syms = &.{
                .{ .set = SetBuilder.init()
                    .add("\\\"")
                    .invert()
                    .set },
            } },
            .{ .syms = &.{
                .{ .str = "\\" },
                .{ .nt = .escaped_char },
            } },
        }, .kind = .token };
        pub const escaped_char = Rule{ .prods = &.{
            .{ .syms = &.{
                .{ .set = SetBuilder.init()
                    .add("\\\"")
                    .set },
            } },
            .{ .syms = &.{ .{ .str = "x" }, .{ .nt = .hexdig }, .{ .nt = .hexdig } } },
        } };
        pub const hexdig = Rule{ .prods = &.{
            .{ .syms = &.{
                .{ .set = SetBuilder.init()
                    .addRange('0', '9')
                    .addRange('a', 'f')
                    .addRange('A', 'F')
                    .set },
            } },
        } };
    };

    // Check it parses correctly
    try parse(rules, .string, {}, "\"\"");
    try parse(rules, .string, {}, "\"foobar\"");
    try parse(rules, .string, {}, "\"foo bar baz\"");
    try parse(rules, .string, {},
        \\"foo \" bar"
    );
    try parse(rules, .string, {},
        \\"foo \\ bar"
    );
    try parse(rules, .string, {},
        \\"\""
    );
    try parse(rules, .string, {},
        \\"\\"
    );
    try parse(rules, .string, {},
        \\"\\\""
    );
    try parse(rules, .string, {},
        \\"foo \x23 bar"
    );
    try parse(rules, .string, {},
        \\"\x4a"
    );
    try parse(rules, .string, {},
        \\"\x7f\x1B\\"
    );
    try parse(rules, .string, {},
        \\"\x09\"\xAF\xfa"
    );

    // Check it fails correctly
    try std.testing.expectError(error.InvalidParse, parse(rules, .string, {}, ""));
    try std.testing.expectError(error.InvalidParse, parse(rules, .string, {}, "\""));
    try std.testing.expectError(error.InvalidParse, parse(rules, .string, {}, "\"\"\""));
    try std.testing.expectError(error.InvalidParse, parse(rules, .string, {}, "\"\"\"\""));
    try std.testing.expectError(error.InvalidParse, parse(rules, .string, {}, "asdf"));
    try std.testing.expectError(error.InvalidParse, parse(rules, .string, {}, "asdf\""));
    try std.testing.expectError(error.InvalidParse, parse(rules, .string, {}, "\"asdf"));
    try std.testing.expectError(error.InvalidParse, parse(rules, .string, {}, "asdf\"foo\""));
    try std.testing.expectError(error.InvalidParse, parse(rules, .string, {}, "\"foo\"asdf"));
    try std.testing.expectError(error.InvalidParse, parse(rules, .string, {},
        \\"foo \a bar"
    ));
    try std.testing.expectError(error.InvalidParse, parse(rules, .string, {},
        \\"\"\m"
    ));
    try std.testing.expectError(error.InvalidParse, parse(rules, .string, {},
        \\"foo \xag bar"
    ));
    try std.testing.expectError(error.InvalidParse, parse(rules, .string, {},
        \\"\xn7"
    ));
    try std.testing.expectError(error.InvalidParse, parse(rules, .string, {},
        \\"\x3k"
    ));
}

test "error reporting" {
    // Construct a parser for matched paren pairs
    const rules = struct {
        pub const token = Rule{ .prods = &.{
            .{ .syms = &.{.{ .set = SetBuilder.init().add("abcd").set }} },
            .{ .syms = &.{.{ .str = "error" }}, .handler = struct {
                pub fn match(_: void, _: []const u8) !void {
                    return error.Error;
                }
            } },
        }, .kind = .token };
        pub const nested = Rule{ .prods = &.{
            .{ .syms = &.{.{ .nt = .token }} },
            .{ .syms = &.{ .{ .str = "(" }, .{ .nt = .many }, .{ .str = ")" } } },
        } };
        pub const many = Rule{ .prods = &.{
            .{ .syms = &.{ .{ .nt = .nested }, .{ .nt = .many } } },
            .{ .syms = &.{} },
        } };
        pub const invalid = Rule{ .prods = &.{
            .{ .syms = &.{.{ .set = SetBuilder.init().add("zxcvbn").set }} },
            .{ .syms = &.{.{ .str = "evil" }} },
        }, .kind = .token };
    };

    {
        var p = Parser(rules, void){
            .text = "()(",
            .context = {},
        };
        defer p.deinit();
        try std.testing.expectError(error.InvalidParse, p.parse(.many));
        try testError(p, 3, &.{ "token", "\"(\"", "\")\"" }, "eof", 0);
    }

    {
        var p = Parser(rules, void){
            .text = ")()",
            .context = {},
        };
        defer p.deinit();
        try std.testing.expectError(error.InvalidParse, p.parse(.many));
        try testError(p, 0, &.{ "token", "\"(\"", "eof" }, "\")\"", 1);
    }

    {
        var p = Parser(rules, void){
            .text = "(zxcv)",
            .context = {},
        };
        defer p.deinit();
        try std.testing.expectError(error.InvalidParse, p.parse(.many));
        try testError(p, 1, &.{ "token", "\"(\"", "\")\"" }, "invalid", 1);
    }

    {
        var p = Parser(rules, void){
            .text = "evil",
            .context = {},
        };
        defer p.deinit();
        try std.testing.expectError(error.InvalidParse, p.parse(.many));
        try testError(p, 0, &.{ "token", "\"(\"", "eof" }, "\"evil\"", 4);
    }

    {
        var p = Parser(rules, void){
            .text = "(j)",
            .context = {},
        };
        defer p.deinit();
        try std.testing.expectError(error.InvalidParse, p.parse(.many));
        try testError(p, 1, &.{ "token", "\"(\"", "\")\"" }, "", 0);
    }

    {
        var p = Parser(rules, void){
            .text = "(error)",
            .context = {},
        };
        defer p.deinit();
        try std.testing.expectError(error.Error, p.parse(.many));
        try testError(p, 1, &.{}, "", 0);
    }
}

fn testError(p: anytype, off: usize, expected: []const []const u8, found: []const u8, len: usize) !void {
    try std.testing.expect(p.err != null);
    try std.testing.expectEqual(off, p.err.?.found.off);

    try std.testing.expectEqual(expected.len, p.err.?.expected.items.len);
    for (p.err.?.expected.items) |e, i| {
        try std.testing.expectEqualStrings(expected[i], e);
    }

    try std.testing.expectEqualStrings(found, p.err.?.found.name);
    try std.testing.expectEqual(len, p.err.?.found.len);
}
