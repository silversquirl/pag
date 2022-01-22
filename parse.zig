const std = @import("std");

pub fn parse(
    comptime rules: type,
    comptime start: std.meta.DeclEnum(rules),
    text: []const u8,
) !Parser(rules).RuleResult(start) {
    var result: Parser(rules).RuleResult(start) = undefined;
    const n = try Parser(rules).parseRule(start, text, &result);
    if (n != text.len) {
        return error.InvalidParse;
    }
    return result;
}

// Generate a type so we can exploit memoization for faster compile times
pub fn Parser(comptime rules: type) type {
    return struct {
        const RuleName = std.meta.DeclEnum(rules);
        const RuleSet = std.enums.EnumSet(RuleName);
        const BaseError = error{InvalidParse};

        pub fn parseRule(
            comptime rule_name: RuleName,
            text: []const u8,
            result: *RuleResult(rule_name),
        ) RuleError(rule_name)!usize {
            const rule = @field(rules, @tagName(rule_name));
            inline for (rule) |prod| {
                if (parseProd(prod, text, result)) |n| {
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
            text: []const u8,
            result: *ProdResult(prod),
        ) ProdError(prod)!usize {
            if (prod.func == null) {
                result.*; // Assert result is *void
                var n: usize = 0;
                inline for (prod.syms) |sym| {
                    var res: SymbolResult(sym) = undefined;
                    n += try parseSym(sym, text[n..], &res);
                }
                return n;
            } else {
                // TODO: context arg
                var args: std.meta.ArgsTuple(prod.func) = undefined;
                if (args.len != prod.syms.len) {
                    @compileError(std.fmt.comptimePrint(
                        "production function {} has incorrect arity (expected {}, got {})",
                        .{ prod.func, args.len, prod.syms.len },
                    ));
                }

                var n: usize = 0;
                inline for (prod.syms) |sym, i| {
                    n += try parseSym(sym, text[n..], &args[i]);
                }

                result.* = @call(.{}, prod.func, args);
                return n;
            }
        }

        fn parseSym(comptime sym: Symbol, text: []const u8, result: *SymbolResult(sym)) !usize {
            switch (sym) {
                .end => if (text.len == 0) {
                    return 0;
                } else {
                    return error.InvalidParse;
                },
                .t => |expected| if (std.mem.startsWith(u8, text, expected)) {
                    result.* = text[0..expected.len];
                    return expected.len;
                } else {
                    return error.InvalidParse;
                },
                .nt => |rule| return parseRule(rule, text, result),
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
            for (rule[1..]) |prod| {
                E = E || ProdErrorR(prod, checked);
            }

            return E;
        }

        fn ProdResult(comptime prod: Production) type {
            if (prod.func == null) return void;
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
            if (prod.func != null) {
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
                .t => []const u8,
                .nt => |rule| RuleResult(rule),
            };
        }
    };
}

pub const Rule = []const Production;
pub const Production = struct {
    syms: []const Symbol,
    func: anytype = null,
};
pub const Symbol = union(enum) {
    end: void,
    t: []const u8,
    nt: @Type(.EnumLiteral),
};

test "parens" {
    // Construct a parser for matched paren pairs
    const rules = struct {
        const nested: Rule = &.{
            .{ .syms = &.{ .{ .t = "(" }, .{ .nt = .many }, .{ .t = ")" } } },
        };
        const many: Rule = &.{
            .{ .syms = &.{ .{ .nt = .nested }, .{ .nt = .many } } },
            .{ .syms = &.{} },
        };
    };

    // Check it parses correctly
    try parse(rules, .many, "");
    try parse(rules, .many, "()");
    try parse(rules, .many, "()()");
    try parse(rules, .many, "(())");
    try parse(rules, .many, "(())()");
    try parse(rules, .many, "(()())");
    try parse(rules, .many, "()((()())())");
    try parse(rules, .many, "(()()(()()))()()(()(()())())");

    // Check it fails correctly
    try std.testing.expectError(error.InvalidParse, parse(rules, .many, "("));
    try std.testing.expectError(error.InvalidParse, parse(rules, .many, ")"));
    try std.testing.expectError(error.InvalidParse, parse(rules, .many, "())"));
    try std.testing.expectError(error.InvalidParse, parse(rules, .many, "(()"));
    try std.testing.expectError(error.InvalidParse, parse(rules, .many, "()())"));
    try std.testing.expectError(error.InvalidParse, parse(rules, .many, "(()(())"));
    try std.testing.expectError(error.InvalidParse, parse(rules, .many, "[]"));
    try std.testing.expectError(error.InvalidParse, parse(rules, .many, "([])"));
    try std.testing.expectError(error.InvalidParse, parse(rules, .many, "( )"));
}
