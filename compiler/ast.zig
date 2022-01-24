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

test {
    _ = @import("test.zig");
}
