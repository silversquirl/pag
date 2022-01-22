const pag = @import("pag");
const rules = @import("rules.zig");

pub fn parse(source: []const u8) !void {
    return pag.parse(rules, .file, source);
}

test "parse parens" {
    const source =
        \\nested = "(" many ")";
        \\many   = nested many | ;
    ;
    try parse(source);
}

test "parse hex number" {
    const source =
        \\num   = digit num | digit;
        \\digit = [0-9a-fA-F];
    ;
    try parse(source);
}

test "parse quoted string" {
    const source =
        \\string = ["] string-chars ["];
        \\string-chars = string-char string-chars | ;
        \\string-char = [^\\"] | "\\" string-char-escaped;
        \\string-char-escaped = [\\"] | "x" hexdig hexdig;
        \\
        \\hexdig = [0-9a-fA-F];
        \\
    ;
    try parse(source);
}

test "parse self" {
    const source = @embedFile("rules.pag");
    try parse(source);
}
