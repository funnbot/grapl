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

pub fn escape(comptime str: []const u8, comptime code: []const u8) comptime []const u8 {
    return "\u{001f}[" ++ str ++ code;
}

fn escFnWorkaround(comptime str: []const u8) comptime []const u8 { return ""; }
pub const EscFn = @TypeOf(escFnWorkaround);

pub fn multi(comptime escs: anytype) EscFn {
    const Closure = struct {
        pub fn esc(comptime str: []const u8) comptime []const u8 {
            var s = str;
            inline for (escs) |func| {
                s = func(s);
            }
            return s;
        }
    };
    return Closure.esc;
}

pub fn color(comptime code: []const u8) EscFn {
    const Closure = struct {
        pub fn esc(comptime str: []const u8) comptime []const u8 {
            return escape(code, Code.Mode) ++ str ++ reset;
        }
    };
    return Closure.esc;
}

pub const Color16Mode = enum { Normal, Bright, };
pub fn color16(comptime code: []const u8, comptime mode: Color16Mode) fn(comptime str: []const u8) comptime []const u8 {
    const Closure = struct {
        pub fn esc(comptime str: []const u8) comptime []const u8 {
            if (mode == .Bright) {
                return escape(code ++ ";1m", Code.Mode) ++ str ++ reset;
            } else if (mode == .Normal) {
                return escape(code, Code.Mode) ++ str ++ reset;
            }
        }
    };
    return Closure.esc;
}

pub const Color256Mode = enum { Foreground, Background };
/// code is Integer string 0 to 255
pub fn color256(comptime code: []const u8, comptime mode: Color256Mode) fn(comptime str: []const u8) comptime []const u8 {
    const Closure = struct {
        pub fn esc(comptime str: []const u8) comptime []const u8 {
            if (mode == .Fore) {
                return escape("38;5;" ++ code, Code.Mode) ++ str ++ reset;
            } else if (mode == .Back) {
                return escape("48;5;" ++ code, Code.Mode) ++ str ++ reset;
            }
        }
    };
    return Closure.esc;
}