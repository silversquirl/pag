const std = @import("std");
const pag = @import("pag");
const pag_rules = @import("rules.zig");

pub fn parse(allocator: std.mem.Allocator, source: []const u8) !File {
    var tls_rev = try pag.parse(pag_rules, .file, allocator, source);
    defer tls_rev.deinit(allocator);

    var header = std.ArrayList(u8).init(allocator);
    errdefer header.deinit();
    var rules = std.ArrayList(Rule).init(allocator);
    errdefer rules.deinit();
    var ignore = std.StringHashMap(void).init(allocator);
    errdefer ignore.deinit();
    var context = Context{
        .name = "_",
        .type = "void",
    };

    var i: usize = tls_rev.items.len;
    while (i > 0) {
        i -= 1;
        switch (tls_rev.items[i]) {
            .pragma => |prag| switch (prag) {
                .context => |ctx| context = ctx,
                .ignore => |name| try ignore.put(name, {}),
            },
            .block => |code| {
                try header.appendSlice(code);
                allocator.free(code);
            },
            .rule => |rule| try rules.append(rule),
        }
    }

    return File{
        .header = header.toOwnedSlice(),
        .rules = rules.toOwnedSlice(),
        .ignore = ignore.unmanaged,
        .context = context,
    };
}

pub fn generate(writer: anytype, file: File) !void {
    try writer.writeAll(
        \\const pag = @import("pag");
        \\
        \\
    );

    if (file.header.len > 0) {
        try writer.writeAll(file.header);
        try writer.writeAll("\n\n");
    }

    for (file.rules) |rule| {
        try writer.print("pub const {} = pag.Rule{{ .prods = &.{{\n", .{std.zig.fmtId(rule.name)});
        for (rule.prods) |prod| {
            try writer.writeAll(".{ .syms = &.{\n");
            for (prod.syms) |sym| {
                switch (sym) {
                    .end => try writer.writeAll(".end,\n"),
                    .str => |str| try writer.print(".{{ .str = \"{}\" }},\n", .{std.zig.fmtEscapes(str)}),
                    .set => |set| try generateSet(writer, set),
                    .nt => |name| try writer.print(".{{ .nt = .{} }},\n", .{std.zig.fmtId(name)}),
                }
            }
            try writer.writeAll("}");

            if (prod.func) |_| {
                try writer.writeAll(", .handler = struct {\n");

                const func = prod.func orelse continue;
                try writer.writeAll("pub fn match(\n");
                try writer.print("{s}: {s},\n", .{ file.context.name, file.context.type });

                for (func.args) |arg_name, i| {
                    const ty = switch (prod.syms[i]) {
                        .end => "void",
                        .str => "[]const u8",
                        .set => "u21",

                        // TODO: make this not O(n^2)
                        .nt => |name| for (file.rules) |rule2| {
                            if (std.mem.eql(u8, rule2.name, name)) {
                                break rule2.type;
                            }
                        } else {
                            return error.RuleNotDefined;
                        },
                    };

                    try writer.print("{s}: {s},\n", .{ arg_name, ty });
                }

                try writer.print(") !{s} {{", .{rule.type});
                if (!std.mem.eql(u8, file.context.name, "_")) {
                    try writer.print(" _ = {s};", .{file.context.name});
                }
                try writer.print("{s}}}\n", .{func.code});
                try writer.writeAll("}");
            }

            try writer.writeAll(" },\n");
        }
        try writer.writeAll("}");
        if (file.ignore.get(rule.name)) |_| {
            try writer.writeAll(", .kind = .ignored_token");
        } else if (isToken(rule.name)) {
            try writer.writeAll(", .kind = .token");
        }
        try writer.writeAll(" };\n\n");
    }
}
fn generateSet(writer: anytype, set: Set) !void {
    if (!set.invert and set.entries.len == 1 and set.entries[0] == .ch) {
        // For single-char sets, emit a string instead for efficiency
        // FIXME: this messes up the types; maybe add a char symbol too?
        try writer.print(".{{ .str = \"{}\" }},\n", .{
            std.zig.fmtEscapes(&.{set.entries[0].ch}),
        });
        return;
    }

    try writer.writeAll(".{ .set = pag.SetBuilder.init()\n");
    for (set.entries) |entry| {
        switch (entry) {
            // TODO: merge all chars into one add
            .ch => |ch| try writer.print(".add(\"{}\")\n", .{
                std.zig.fmtEscapes(&.{ch}),
            }),
            .range => |r| try writer.print(".addRange('{'}', '{'}')\n", .{
                std.zig.fmtEscapes(&.{r.start}),
                std.zig.fmtEscapes(&.{r.end}),
            }),
        }
    }
    if (set.invert) {
        try writer.writeAll(".invert()\n");
    }
    try writer.writeAll(".set },\n");
}
fn isToken(s: []const u8) bool {
    for (s) |c| {
        if (std.ascii.isLower(c)) {
            return false;
        }
    }
    return true;
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

                node_opt = node.next;
                if (node.next) |n| {
                    allocator.destroy(n);
                }
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

pub const File = struct {
    header: []const u8,
    rules: []const Rule,
    ignore: std.StringHashMapUnmanaged(void) = .{},
    context: Context,
};
pub const Context = struct {
    name: []const u8,
    type: []const u8,
};
pub const Toplevel = union(enum) {
    pragma: Pragma,
    block: []const u8,
    rule: Rule,
};
pub const Pragma = union(enum) {
    context: Context,
    ignore: []const u8,
};
pub const Rule = struct {
    name: []const u8,
    type: []const u8,
    prods: []const Production,
};
pub const Production = struct {
    syms: []const Symbol,
    func: ?Func,
};
pub const Func = struct {
    args: []const []const u8,
    code: []const u8,
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

test {
    _ = @import("test/parse.zig");
    _ = @import("test/generate.zig");
}
