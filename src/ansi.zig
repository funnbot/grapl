const std = @import("std");

/// Foreground
pub const FG = struct {
    pub const Black = "30";
    pub const Red = "31";
    pub const Green = "32";
    pub const Yellow = "33";
    pub const Blue = "34";
    pub const Magenta = "35";
    pub const Cyan = "36";
    pub const White = "37";

    pub const Tag = enum {
        Black,
        Red,
        Green,
        Yellow,
        Blue,
        Magenta,
        Cyan,
        White,

        pub fn toString(comptime self: Tag) comptime []const u8 {
            return switch (self) {
                .Black => Black,
                .Red => Red,
                .Green => Green,
                .Yellow => Yellow,
                .Blue => Blue,
                .Magenta => Magenta,
                .Cyan => Cyan,
                .White => White,
            };
        }
    };
};

/// Background
pub const BG = struct {
    pub const Black = "40";
    pub const Red = "41";
    pub const Green = "42";
    pub const Yellow = "43";
    pub const Blue = "44";
    pub const Magenta = "45";
    pub const Cyan = "46";
    pub const White = "47";

    pub const Tag = enum {
        Black,
        Red,
        Green,
        Yellow,
        Blue,
        Magenta,
        Cyan,
        White,

        pub fn toString(comptime self: Tag) comptime []const u8 {
            return switch (self) {
                .Black => Black,
                .Red => Red,
                .Green => Green,
                .Yellow => Yellow,
                .Blue => Blue,
                .Magenta => Magenta,
                .Cyan => Cyan,
                .White => White,
            };
        }
    };
};

/// Attribute
pub const AT = struct {
    pub const Reset = "0";
    pub const Bold = "1";
    pub const Underscore = "4";
    pub const Blink = "5";
    pub const ReverseVid = "7";
    pub const Conceal = "8";
};

/// Escape Code
pub const Code = struct {
    /// Graphics Mode
    pub const Mode = "m";
    /// Cursor
    pub const CurPos = "H";
    pub const CurUp = "A";
    pub const CurDown = "B";
    pub const CurRight = "C";
    pub const CurLeft = "D";
    pub const CurSave = "s";
    pub const CurRestore = "u";
    /// Display
    pub const DispErase = "2J";
    pub const LineErase = "K";
};

/// Reset escape sequence
pub const reset = escape(AT.Reset, Code.Mode);

pub const black = color(FG.Black);
pub const red = color(FG.Red);
pub const yellow = color(FG.Yellow);

pub fn escape(comptime esc_val: []const u8, comptime esc_code: []const u8) comptime []const u8 {
    return "\u{001b}[" ++ esc_val ++ esc_code;
}

fn escFnWorkaround(comptime str: []const u8) comptime []const u8 {
    return "";
}
pub const EscFn = @TypeOf(escFnWorkaround);

pub fn multi(comptime esc_funcs: anytype) EscFn {
    const Closure = struct {
        pub fn esc(comptime str: []const u8) comptime []const u8 {
            var s = str;
            inline for (esc_funcs) |func| {
                std.debug.assert(@TypeOf(func) == EscFn);
                s = func(s);
            }
            return s;
        }
    };
    return Closure.esc;
}

pub fn attr(comptime attr_code: []const u8) EscFn {
    const Closure = struct {
        pub fn esc(comptime str: []const u8) comptime []const u8 {
            return escape(attr_code, Code.Mode) ++ str ++ reset;
        }
    };
    return Closure.esc;
}

pub fn fg(comptime fg_color: FG.Tag) EscFn {
    const Closure = struct {
        pub fn esc(comptime str: []const u8) comptime []const u8 {
            return escape(fg_color.toString(), Code.Mode) ++ str ++ reset;
        }
    };
    return Closure.esc;
}

pub const color = attr;

pub const Color16Mode = enum {
    Normal,
    Bright,
};
pub fn color16(comptime color_code: []const u8, comptime mode: Color16Mode) EscFn {
    const Closure = struct {
        pub fn esc(comptime str: []const u8) comptime []const u8 {
            if (mode == .Bright) {
                return escape(color_code ++ ";1", Code.Mode) ++ str ++ reset;
            } else if (mode == .Normal) {
                return escape(color_code, Code.Mode) ++ str ++ reset;
            }
        }
    };
    return Closure.esc;
}

pub const Color256Mode = enum { Foreground, Background };
/// code is integer string 0 to 255
pub fn color256(comptime color_code: []const u8, comptime mode: Color256Mode) EscFn {
    const Closure = struct {
        pub fn esc(comptime str: []const u8) comptime []const u8 {
            if (mode == .Fore) {
                return escape("38;5;" ++ color_code, Code.Mode) ++ str ++ reset;
            } else if (mode == .Back) {
                return escape("48;5;" ++ color_code, Code.Mode) ++ str ++ reset;
            }
        }
    };
    return Closure.esc;
}

/// Add to the end of .multi to reset attributes before the newline
pub const ln = newline();
fn newline() EscFn {
    const Closure = struct {
        pub fn esc(comptime str: []const u8) comptime []const u8 {
            return str ++ reset ++ "\n";
        }
    };
    return Closure.esc;
}
