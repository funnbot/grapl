const std = @import("std");
const assert = std.debug.assert;
const ascii = std.ascii;

pub const TokenType = @import("token/token_type.zig").TokenType;

pub const Token = struct {
    tokenType: TokenType,
    buffer: []const u8,
    lc: Lc,

    pub const Lc = struct {
        line: usize,
        lineStr: []const u8,
        column: usize,
    };

    pub fn format(self: Token, comptime fmt: []const u8, opts: std.fmt.FormatOptions, out_stream: anytype) !void {
        try out_stream.print("{} {}", .{
            @tagName(self.tokenType),
            self.buffer,
        });
    }
};

const Self = @This();

source: []const u8,
start: usize = 0,
current: usize = 0,

line: usize = 0,
column: usize = 0,
lineSlice: []const u8,

pub fn init(source: []const u8) Self {
    var self = Self{
        .source = source,
        .lineSlice = source[0..1],
    };
    self.lineSlice.len = 0;
    self.nextLine();
    return self;
}

pub fn next(self: *Self) Token {
    self.skipWhitespace();
    self.start = self.current;
    if (self.isEOF(0)) return self.makeToken(.EOF);

    if (self.constant()) |token| return token;
    if (self.identifier()) |token| return token;

    if (self.symbol(self.advance())) |tokenType| {
        return self.makeToken(tokenType);
    }

    return self.errorToken("Unexpected token.");
}

fn keywordRest(self: *Self, rest: []const u8, start: usize, length: usize, key: TokenType) ?TokenType {
    var wordRest = self.source[self.start + start .. self.start + start + length];
    if (self.currentLen() == start + length and
        std.mem.eql(u8, wordRest, rest))
        return key;
    return null;
}

fn keyword(self: *Self) ?TokenType {
    return switch (self.source[self.start]) {
        'c' => self.keywordRest("ase", 1, 3, .Case),
        'e' => switch (self.source[self.start + 1]) {
            'l' => switch (self.source[self.start + 2]) {
                'i' => self.keywordRest("f", 3, 1, .Elif),
                's' => self.keywordRest("e", 3, 1, .Else),
                else => null,
            },
            'n' => self.keywordRest("um", 2, 2, .Enum),
            else => null,
        },
        'f' => switch (self.source[self.start + 1]) {
            'a' => self.keywordRest("lse", 2, 3, .False),
            'o' => self.keywordRest("r", 2, 1, .For),
            'n' => TokenType.Fn,
            else => null,
        },
        'i' => self.keywordRest("f", 1, 1, .If),
        'm' => self.keywordRest("acro", 1, 4, .Macro),
        'n' => self.keywordRest("ull", 1, 3, .Null),
        's' => self.keywordRest("truct", 1, 5, .Struct),
        't' => self.keywordRest("rue", 1, 3, .True),
        'u' => self.keywordRest("nion", 1, 4, .Union),
        'w' => self.keywordRest("hile", 1, 4, .While),
        else => null,
    };
}

fn identifier(self: *Self) ?Token {
    if (!isIdentStart(self.peek(0))) return null;

    while (!self.isEOF(0) and isIdent(self.peek(0))) self.step();

    return self.makeToken(if (self.keyword()) |key| key else .Identifier);
}

fn constant(self: *Self) ?Token {
    return switch (self.peek(0)) {
        // "" and '' are string and char, but parse escape codes and others later,
        // So... '' can contain multiple characters here.
        '"', '\'' => self.string(),
        '.', '0'...'9' => self.number(),
        else => null,
    };
}

fn string(self: *Self) ?Token {
    // advance past terminator
    const term = self.advance();
    var slash_count: usize = 0;
    while (!self.isEOF(0) and self.peek(0) != term) {
        if (self.peek(0) == '\\') {
            slash_count += 1;

            if (self.peek(1) == '"' and slash_count % 2 == 0) self.step();
        } else slash_count = 0;

        if (self.peek(0) == '\n') self.line += 1;
        self.step();
    }

    if (term == '"') {
        if (self.isEOF(0)) return self.errorToken("Unterminated string.");
        self.step();
        return self.makeToken(.String);
    } else if (term == '\'') {
        if (self.isEOF(0)) return self.errorToken("Unterminated char.");
        self.step();
        return self.makeToken(.Char);
    } else unreachable;
}

fn numberDec(self: *Self) ?Token {
    // If dot found already
    var dot: bool = self.peek(0) == '.';

    if (dot) {
        // Quit early if this is just a dot.
        if (!isDecEdge(self.peek(1))) return null;
        // Skip over the dot
        self.step();
    }

    if (self.isEOF(0)) return self.makeToken(.Int);

    var char: u8 = self.advance();
    if (!isDecEdge(char)) return self.errorToken("Unexpected separator.");

    while (!self.isEOF(0) and (isDec(self.peek(0)) or self.peek(0) == '.')) {
        if (self.peek(0) == '.') {
            // This is a second dot, break and make it's own token
            if (dot) break;
            dot = true;
        }
        char = self.advance();
    }

    if (char == '.') {
        dot = true;
    } else if (!isDecEdge(char)) return self.errorToken("Unexpected separator.");
    return self.makeToken(if (dot) TokenType.Float else TokenType.Int);
}

fn numberHex(self: *Self) ?Token {
    // 0
    self.step();
    // x
    var char = self.advance();
    while (isHex(self.peek(0))) char = self.advance();
    if (char == '_') return self.errorToken("Unexpected separator");

    return self.makeToken(TokenType.Hex);
}

fn numberBin(self: *Self) ?Token {
    // 0
    self.step();
    // b
    var char = self.advance();
    while (isBin(self.peek(0))) char = self.advance();
    if (char == '_') return self.errorToken("Unexpected separator");

    return self.makeToken(TokenType.Bin);
}

fn number(self: *Self) ?Token {
    if (self.peek(0) == '0') {
        if (isHexIdent(self.peek(1))) {
            return self.numberHex();
        } else if (isBinIdent(self.peek(1))) {
            return self.numberBin();
        }
    }

    return self.numberDec();
}

// zig fmt: off
fn symbol(self: *Self, char: u8) ?TokenType {
    return switch (char) {
        '=' => {
            if (self.matchAdvance('=')) return .EqualEqual
            else if (self.matchAdvance('>')) return .Arrow
            else return .Equal;
        },
        '!' => if (self.matchAdvance('=')) TokenType.BangEqual else .Bang,
        '>' => if (self.matchAdvance('=')) TokenType.GreaterEqual else .Greater,
        '<' => if (self.matchAdvance('=')) TokenType.LessEqual else .Less,

        '+' => .Plus,
        '-' => .Minus,
        '*' => .Star,
        '/' => .Slash,
        '%' => .Percent,

        '[' => .LeftBracket, ']' => .RightBracket,
        '{' => .LeftBrace, '}' => .RightBrace,
        '(' => .LeftParen, ')' => .RightParen,

        ':' => if (self.matchAdvance('=')) TokenType.ColonEqual else .Colon,
        ';' => .Semicolon,
        ',' => .Comma,
        '|' => .Bar,
        '&' => .Ampersand,
        '.' => .Dot,
        '?' => .Question,
        else => null,
    };
}
// zig fmt: on

fn skipWhitespace(self: *Self) void {
    while (true) {
        switch (self.peek(0)) {
            ' ', '\r', '\t' => self.step(),

            '/' => {
                if (self.peek(1) == '/') {
                    while (self.peek(0) != '\n' and !self.isEOF(0))
                        self.step();
                } else break;
            },
            '\n' => {
                self.nextLine();
                self.step();
            },
            else => break,
        }
    }
}

// zig fmt: off
fn isIdent(char: u8) bool { return ascii.isAlNum(char) or char == '_'; }
fn isIdentStart(char: u8) bool { return ascii.isAlpha(char) or char == '_'; }

fn isDec(char: u8) bool { return ascii.isDigit(char) or char == '_'; }
fn isDecEdge(char: u8) bool { return ascii.isDigit(char); }

fn isHexIdent(char: u8) bool { return char == 'x' or char == 'X'; }
fn isHex(char: u8) bool { return ascii.isXDigit(char) or char == '_'; }
fn isHexEnd(char: u8) bool { return ascii.isXDigit(char); }

fn isBinIdent(char: u8) bool { return char == 'b' or char == 'B'; }
fn isBin(char: u8) bool { return isBinEnd(char) or char == '_'; }
fn isBinEnd(char: u8) bool { return char == '0' or char == '1'; }
// zig fmt: on

fn advance(self: *Self) u8 {
    var char = self.source[self.current];
    self.step();
    return char;
}

fn step(self: *Self) void {
    self.current += 1;
    self.column += 1;
}

fn nextLine(self: *Self) void {
    self.column = 0;
    self.line += 1;

    const offset: usize = if (self.line == 1) 0 else 1;
    self.lineSlice.ptr += self.lineSlice.len + offset;

    self.lineSlice.len = 0;
    var i: usize = @ptrToInt(self.lineSlice.ptr) - @ptrToInt(self.source.ptr);
    while (i < self.source.len and self.source[i] != '\n') {
        i += 1;
        self.lineSlice.len += 1;
    }
}

fn peek(self: *Self, count: usize) u8 {
    if (self.isEOF(count)) return 0;
    return self.source[self.current + count];
}

fn matchAdvance(self: *Self, expected: u8) bool {
    if (self.isEOF(0) or self.peek(0) != expected)
        return false;

    self.step();
    return true;
}

fn isEOF(self: *Self, count: usize) bool {
    return self.current + count >= self.source.len;
}

fn currentBuffer(self: *Self) []const u8 {
    return self.source[self.start..self.current];
}

fn currentLen(self: *Self) usize {
    assert(self.current >= self.start);
    return self.current - self.start;
}

fn errorToken(self: *Self, msg: []const u8) Token {
    return Token{
        .tokenType = TokenType.Error,
        .buffer = msg,
        .lc = .{
            .line = self.line,
            .column = self.column - 1,
            .lineStr = "",
        },
    };
}

fn makeToken(self: *Self, tokenType: TokenType) Token {
    const buffer = self.currentBuffer();
    //if (buffer.len == 0) return self.errorToken("Zero length token.");
    return Token{
        .tokenType = tokenType,
        .buffer = buffer,
        .lc = .{
            .line = self.line,
            .column = self.column - buffer.len,
            .lineStr = self.lineSlice,
        },
    };
}

fn expectToken(comptime src: []const u8, expectType: TokenType) void {
    var scanner = Self.init(src);
    var token = scanner.next();
    std.testing.expect(token.tokenType == expectType);
    //std.debug.warn("{}\n", .{token.?});
}

test "scanner keywords" {
    var keywords = .{
        "struct", "fn",   "enum", "union", "macro", "case", "for", "while",
        "if",     "elif", "else", "true",  "false", "null",
    };

    inline for (keywords) |key| {
        var scanner = Self.init(key);
        var token = scanner.next();
        std.testing.expect(token.tokenType != TokenType.Identifier);
    }
}

test "scanner constants" {
    expectToken("134", .Int);
    expectToken("10_10", .Int);
    expectToken("0", .Int);
    expectToken(" 123987_3182_12938 ", .Int);

    expectToken(".123", .Float);
    expectToken("1_000_000.000_000_1", .Float);
    expectToken("1000.", .Float);

    expectToken("\"how\"", .String);
    expectToken("\" \\\" hee\"", .String);
}
