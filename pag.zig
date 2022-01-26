const std = @import("std");

pub fn parse(
    comptime rules: type,
    comptime start: std.meta.DeclEnum(rules),
    context: anytype,
    text: []const u8,
) !Parser(rules, @TypeOf(context)).RuleResult(start) {
    const P = Parser(rules, @TypeOf(context));
    var result: P.RuleResult(start) = undefined;
    const n = try P.parseRule(start, context, text, &result);
    if (n != text.len) {
        return error.InvalidParse;
    }
    return result;
}

pub fn Parser(comptime rules: type, comptime Context: type) type {
    return struct {
        const RuleName = std.meta.DeclEnum(rules);
        const RuleSet = std.enums.EnumSet(RuleName);
        const BaseError = error{InvalidParse};

        pub fn parseRule(
            comptime rule_name: RuleName,
            context: Context,
            text: []const u8,
            result: *RuleResult(rule_name),
        ) RuleError(rule_name)!usize {
            const rule = @field(rules, @tagName(rule_name));
            inline for (rule) |prod| {
                if (parseProd(prod, context, text, result)) |n| {
                    return n;
                } else |err| switch (err) {
                    error.InvalidParse => {},
                    else => |e| return e,
                }
            }
            return error.InvalidParse;
        }

        fn parseProd(
            comptime prod: Production,
            context: Context,
            text: []const u8,
            result: *ProdResult(prod),
        ) ProdError(prod)!usize {
            if (@TypeOf(prod.func) == void) {
                result.*; // Assert result is *void
                var n: usize = 0;
                inline for (prod.syms) |sym| {
                    var res: SymbolResult(sym) = undefined;
                    n += try parseSym(sym, context, text[n..], &res);
                }
                return n;
            } else {
                var args: std.meta.ArgsTuple(@TypeOf(prod.func)) = undefined;
                args[0] = context;

                if (args.len != prod.syms.len + 1) {
                    @compileError(comptime std.fmt.comptimePrint(
                        "production function {} has incorrect arity (expected {}, got {})",
                        .{ @TypeOf(prod.func), args.len, prod.syms.len + 1 },
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
                    n += try parseSym(sym, context, text[n..], &args[i + 1]);
                }

                const ret = @call(.{}, prod.func, args);
                result.* = switch (@typeInfo(@TypeOf(ret))) {
                    .ErrorUnion => try ret,
                    else => ret,
                };

                return n;
            }
        }

        fn parseSym(
            comptime sym: Symbol,
            context: Context,
            text: []const u8,
            result: *SymbolResult(sym),
        ) !usize {
            switch (sym) {
                .end => if (text.len == 0) {
                    return 0;
                } else {
                    return error.InvalidParse;
                },
                .str => |expected| if (std.mem.startsWith(u8, text, expected)) {
                    result.* = text[0..expected.len];
                    return expected.len;
                } else {
                    return error.InvalidParse;
                },
                .set => |set| if (text.len > 0 and set.isSet(text[0])) {
                    result.* = text[0];
                    return 1;
                } else {
                    return error.InvalidParse;
                },
                .nt => |rule| return parseRule(rule, context, text, result),
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
            if (@TypeOf(prod.func) == void) return void;
            const ret = @typeInfo(@TypeOf(prod.func)).Fn.return_type.?;
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

            // Add func errors to the set
            if (@TypeOf(prod.func) != void) {
                const ret = @typeInfo(@TypeOf(prod.func)).Fn.return_type.?;
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

pub const Rule = []const Production;
pub const Production = struct {
    syms: []const Symbol,
    func: anytype = {},
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
