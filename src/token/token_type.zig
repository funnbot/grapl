// zig fmt: off
pub const TokenType = enum {
    // Keywords
        // TypeBlock
    Struct, Fn, Enum, Union, Macro, Case, 
        // ControlFlow
    For, While,
    If, Elif, Else,
    
    // Constants
    True, False, Null,
    String, Char, Int, Float, Hex, Bin,

    Identifier,

    // Symbols
    Equal, EqualEqual, BangEqual, Arrow,
    Greater, GreaterEqual,
    Less, LessEqual,
    Plus, Minus, Star, Slash, Percent,
    LeftBracket, RightBracket,
    LeftBrace, RightBrace,
    LeftParen, RightParen,
    Colon, ColonEqual,
    Semicolon, Comma,
    Bar, Ampersand, Bang, Question,
    Dot,

    Newline,

    Error, EOF,

    pub fn isTypeBlock(self: TokenType) bool {
        const s = @enumToInt(self);
        return s >= @enumToInt(TokenType.Struct) and s <= @enumToInt(TokenType.Case);
    }

    pub fn isConstant(self: TokenType) bool {
        const s = @enumToInt(self);
        return s >= @enumToInt(TokenType.True) and s <= @enumToInt(TokenType.Bin);
    }

    pub fn isUnary(self: TokenType) bool {
        return self == .Plus or self == .Minus or self == .Bang;
    }

    pub fn isTerminal(self: TokenType) bool {
        return switch (self) {
            .Semicolon, .Comma,
            .RightBrace, .RightParen, .RightBracket,
            => true,
            else => false,
        };
    }

    pub fn toChars(self: TokenType) []const u8 {
        return switch (self) {
            // Keywords
                // TypeBlock
            .Struct => "struct", .Fn => "fn", .Enum => "enum", .Union => "union",
            .Macro => "macro", .Case => "case",
                // Control Flow
            .For => "for", .While => "while",
            .If => "if", .Elif => "elif", .Else => "else",
                // Constant
            .True => "true", .False => "false", .Null => "null",
            

            // Constants
            //.String , .Char, .Int, .Float, .Hex, .Bin,

            //.Identifier,

            // Symbols
            .Equal => "=", .EqualEqual => "==", .BangEqual => "!=", .Arrow => "=>",
            .Greater => ">", .GreaterEqual => ">=",
            .Less => "<", .LessEqual => "<=",
            .Plus => "+", .Minus => "-", .Star => "*", .Slash => "/", .Percent => "%",
            .LeftBracket => "[", .RightBracket => "]",
            .LeftBrace => "{", .RightBrace => "}",
            .LeftParen => "(", .RightParen => ")",
            .Colon => ":", .ColonEqual => ":=",
            .Semicolon => ";", .Comma => ",",
            .Bar => "|", .Ampersand => "&", .Bang => "!", .Question => "?",
            .Dot => ".",

            //.Newline,

            //.Error, .EOF,
            
            else => @tagName(self),
        };
    }
};
// zig fmt: on