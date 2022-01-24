const std = @import("std");
const pag = @import("pag");
const rules = @import("rules.zig");

pub fn parse(allocator: std.mem.Allocator, source: []const u8) !File {
    const list = try pag.parse(rules, .file, allocator, source);
    return List(Rule).collect(list, allocator);
}

pub fn generate(writer: anytype, file: File) !void {
    try writer.writeAll(
        \\const pag = @import("pag");
        \\
        \\
    );
    for (file) |rule| {
        try writer.print("pub const {}: pag.Rule = &.{{\n", .{std.zig.fmtId(rule.name)});
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
            if (prod.func) |func| {
                try writer.print(", .func = funcs.{}", .{std.zig.fmtId(func)});
            }
            try writer.writeAll(" },\n");
        }
        try writer.writeAll("};\n\n");
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

    try writer.writeAll(".{ .set = &pag.SetBuilder.init()\n");
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

test {
    _ = @import("test/parse.zig");
    _ = @import("test/generate.zig");
}
