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
        if (err == error.InvalidParse) {
            const info = p.err.?;
            const line_pos = p.linePos(info.off);

            // TODO: print file name as `filename:line:col`
            std.debug.print("{}:\n", .{line_pos});

            {
                var n = line_pos.line;
                while (n > 0) : (n /= 10) {
                    std.debug.print(" ", .{});
                }
                std.debug.print("|\n", .{});
            }

            // TODO: handle weird control chars properly
            const line = p.line(info.off);
            std.debug.print("{} | {s}\n", .{ line_pos.line, line });

            {
                var n = line_pos.line;
                while (n > 0) : (n /= 10) {
                    std.debug.print(" ", .{});
                }
                std.debug.print("| ", .{});
            }

            // TODO: handle weird control chars properly
            for (line[0..line_pos.col -| 1]) |c| {
                const ws: u8 = switch (c) {
                    '\t' => '\t',
                    else => ' ',
                };
                std.debug.print("{c}", .{ws});
            }
            std.debug.print("^\n", .{});

            const use_ansi = std.io.getStdErr().supportsAnsiEscapeCodes();
            const error_kw = if (use_ansi) "\x1b[1;31merror\x1b[0m" else "error";
            std.debug.print("{s}: {}\n\n", .{ error_kw, info.err });
        }
        return err;
    }
}

pub fn Parser(comptime rules: type, comptime Context: type) type {
    return struct {
        context: Context,
        text: []const u8,
        err: ?ErrorInfo = null,

        pub const ErrorInfo = struct {
            off: usize,
            err: ParseError,
        };

        const RuleName = std.meta.DeclEnum(rules);
        const RuleSet = std.enums.EnumSet(RuleName);
        const BaseError = error{ InvalidParse, OutOfMemory };
        const Self = @This();

        pub fn deinit(self: Self) void {
            if (self.err) |err| {
                err.err.expected.deinit();
            }
        }

        fn e(self: *Self, comptime expected: []const []const u8, off: usize) BaseError {
            // TODO: append to existing expected set unless offset has changed
            if (self.err == null or self.err.?.off != off) {
                var expected_list = std.ArrayList([]const u8).init(std.heap.page_allocator);
                if (self.err) |err| {
                    expected_list = err.err.expected;
                    expected_list.clearRetainingCapacity();
                }

                try expected_list.appendSlice(expected);
                self.err = ErrorInfo{
                    .off = off,
                    .err = .{
                        .expected = expected_list,
                        .found = if (off < self.text.len)
                            "" // TODO: get found token
                        else
                            "eof",
                    },
                };
            } else {
                try self.err.?.err.expected.appendSlice(expected);
            }
            return error.InvalidParse;
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
            var pos = LinePos{ .line = 1, .col = 0 };
            for (self.text) |ch, i| {
                pos.col += 1;
                if (i >= off) {
                    break;
                }

                if (ch == '\n') {
                    pos.line += 1;
                    pos.col = 0;
                }
            }
            return pos;
        }

        pub fn parse(self: *Self, comptime start: RuleName) !RuleResult(start) {
            var result: RuleResult(start) = undefined;
            const n = try self.parseRule(start, 0, &result);
            if (n != self.text.len) {
                return self.e(&.{"eof"}, n);
            }
            return result;
        }

        pub fn parseRule(
            self: *Self,
            comptime rule_name: RuleName,
            off: usize,
            result: *RuleResult(rule_name),
        ) RuleError(rule_name)!usize {
            const rule = @field(rules, @tagName(rule_name));
            inline for (rule) |prod| {
                if (self.parseProd(prod, off, result)) |n| {
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
                    if (@TypeOf(args[i + 1]) != SymbolResult(sym)) {
                        // Specially handle this type error for better readability
                        const expected = @typeName(@TypeOf(args[i + 1]));
                        const found = @typeName(SymbolResult(sym));
                        @compileError(comptime std.fmt.comptimePrint(
                            "expected {} to have type {s}, found {s}",
                            .{ sym, expected, found },
                        ));
                    }
                    n += try self.parseSym(sym, off + n, &args[i + 1]);
                }

                const ret = @call(.{}, h.match, args);
                result.* = switch (@typeInfo(@TypeOf(ret))) {
                    .ErrorUnion => try ret,
                    else => ret,
                };

                return n;
            } else {
                result.*; // Assert result is *void
                var n: usize = 0;
                inline for (prod.syms) |sym| {
                    var res: SymbolResult(sym) = undefined;
                    n += try self.parseSym(sym, off + n, &res);
                }
                return n;
            }
        }

        fn parseSym(
            self: *Self,
            comptime sym: Symbol,
            off: usize,
            result: *SymbolResult(sym),
        ) !usize {
            switch (sym) {
                .end => if (off >= self.text.len) {
                    return 0;
                } else {
                    return self.e(&.{"eof"}, off);
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
                    return self.e(&.{err_expected}, off);
                },
                .set => |set| if (off < self.text.len and set.isSet(self.text[off])) {
                    result.* = self.text[off];
                    return 1;
                } else {
                    return self.e(&.{"<character set>"}, off); // TODO
                },
                .nt => |rule| return self.parseRule(rule, off, result),
            }
        }

        pub fn RuleResult(comptime rule_name_e: RuleName) type {
            const rule_name = @tagName(rule_name_e);
            const rule = @field(rules, rule_name);

            if (rule.len == 0) {
                @compileError("rule '" ++ rule_name ++ "' has no productions");
            }

            const ty = ProdResult(rule[0]);
            for (rule[1..]) |prod| {
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

            if (rule.len == 0) {
                @compileError("rule '" ++ rule_name ++ "' has no productions");
            }

            var E = BaseError;
            for (rule) |prod| {
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
                .set => u8,
                .nt => |rule| RuleResult(rule),
            };
        }
    };
}

pub const LinePos = struct {
    line: usize,
    col: usize,

    pub fn format(self: LinePos, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.print("{}:{}", .{ self.line, self.col });
    }
};
pub const ParseError = struct {
    expected: std.ArrayList([]const u8),
    found: []const u8,

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

        if (self.found.len > 0) {
            try writer.print(", found {s}", .{self.found});
        }
    }
};

pub const Rule = []const Production;
pub const Production = struct {
    syms: []const Symbol,
    handler: ?type = null,
};
pub const Symbol = union(enum) {
    end: void,
    str: []const u8,
    set: *const Set,
    nt: @Type(.EnumLiteral),
};
pub const Set = std.StaticBitSet(256);
pub const SetBuilder = struct {
    set: Set = Set.initEmpty(),

    pub fn init() SetBuilder {
        return .{};
    }

    pub fn add(comptime self_const: SetBuilder, comptime chars: []const u8) SetBuilder {
        @setEvalBranchQuota(8 * chars.len);

        var self = self_const;
        for (chars) |ch| {
            self.set.set(ch);
        }
        return self;
    }

    pub fn addRange(comptime self_const: SetBuilder, comptime start: u8, comptime end: u8) SetBuilder {
        @setEvalBranchQuota(8 * (@as(u32, end - start) + 1));

        var self = self_const;
        var ch = start;
        while (true) {
            self.set.set(ch);
            if (ch == end) break;
            ch += 1;
        }
        return self;
    }

    pub fn invert(comptime self_const: SetBuilder) SetBuilder {
        var self = self_const;
        self.set.toggleAll();
        return self;
    }
};

test "parens" {
    // Construct a parser for matched paren pairs
    const rules = struct {
        pub const nested: Rule = &.{
            .{ .syms = &.{ .{ .str = "(" }, .{ .nt = .many }, .{ .str = ")" } } },
        };
        pub const many: Rule = &.{
            .{ .syms = &.{ .{ .nt = .nested }, .{ .nt = .many } } },
            .{ .syms = &.{} },
        };
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
        pub const digit: Rule = &.{
            .{ .syms = &.{
                .{ .set = &SetBuilder.init()
                    .addRange('0', '9')
                    .addRange('a', 'f')
                    .addRange('A', 'F')
                    .set },
            } },
        };
        pub const num: Rule = &.{
            .{ .syms = &.{ .{ .nt = .digit }, .{ .nt = .num } } },
            .{ .syms = &.{.{ .nt = .digit }} },
        };
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
        pub const string: Rule = &.{
            .{ .syms = &.{ .{ .str = "\"" }, .{ .nt = .chars }, .{ .str = "\"" } } },
        };
        pub const chars: Rule = &.{
            .{ .syms = &.{ .{ .nt = .char }, .{ .nt = .chars } } },
            .{ .syms = &.{} },
        };
        pub const char: Rule = &.{
            .{ .syms = &.{
                .{ .set = &SetBuilder.init()
                    .add("\\\"")
                    .invert()
                    .set },
            } },
            .{ .syms = &.{
                .{ .str = "\\" },
                .{ .nt = .escaped_char },
            } },
        };
        pub const escaped_char: Rule = &.{
            .{ .syms = &.{
                .{ .set = &SetBuilder.init()
                    .add("\\\"")
                    .set },
            } },
            .{ .syms = &.{ .{ .str = "x" }, .{ .nt = .hexdig }, .{ .nt = .hexdig } } },
        };
        pub const hexdig: Rule = &.{
            .{ .syms = &.{
                .{ .set = &SetBuilder.init()
                    .addRange('0', '9')
                    .addRange('a', 'f')
                    .addRange('A', 'F')
                    .set },
            } },
        };
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
