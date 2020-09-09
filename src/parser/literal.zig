const std = @import("std");
const fmt = std.fmt;
const Allocator = std.mem.Allocator;

const Token = @import("../Scanner.zig").Token;
const Literal = @import("../Ast.zig").Node.Nodes.Literal;
const Data = Literal.Data;

pub const Error = error{
    InvalidEscapeSequence,
    CharTooLong,
    InvalidCharacter,
} || std.fmt.ParseIntError || std.mem.Allocator.Error;

pub fn parseLiteral(allocator: *Allocator, token: Token) Error!Data {
    return switch (token.tokenType) {
        .String => .{ .String = try escapeString(allocator, token.buffer[1 .. token.buffer.len - 1], false) },
        .Char => .{ .Char = try escapeString(allocator, token.buffer[1 .. token.buffer.len - 1], true) },
        .Int => .{ .Int = try fmt.parseInt(i64, token.buffer, 10) },
        .Hex => .{ .Int = try fmt.parseInt(i64, token.buffer[2..token.buffer.len], 16) },
        .Bin => .{ .Int = try fmt.parseInt(i64, token.buffer[2..token.buffer.len], 2) },
        .Float => .{ .Float = try fmt.parseFloat(f64, token.buffer) },
        .True => .{ .Bool = true },
        .False => .{ .Bool = false },
        .Null => .{ .Null = 0 },
        else => unreachable,
    };
}

/// Caller owns memory
pub fn escapeString(allocator: *Allocator, str: []const u8, comptime req_length_one: bool) Error!(if (req_length_one) u8 else []const u8) {
    var builder = try std.ArrayList(u8).initCapacity(allocator, str.len);
    errdefer builder.deinit();
    var iter = SliceIterator(u8){ .items = str };

    while (iter.next()) |c| {
        try switch (c) {
            '\\' => builder.append(if (iter.next()) |c2|
                @as(u8, switch (c2) {
                    '\\' => '\\',
                    'b' => '\x08',
                    'n' => '\n',
                    'r' => '\r',
                    't' => '\t',
                    '\'' => '\'',
                    '"' => '"',
                    '0' => 0,
                    else => return Error.InvalidEscapeSequence,
                })
            else
                return Error.InvalidEscapeSequence),
            else => builder.append(c),
        };
    }

    if (req_length_one) {
        if (builder.items.len == 1) {
            const char = builder.items[0];
            builder.deinit();
            return char;
        } else return Error.CharTooLong;
    }

    return builder.toOwnedSlice();
}

fn SliceIterator(comptime T: type) type {
    return struct {
        const Self = @This();
        items: []const T,
        index: usize = 0,

        pub fn next(self: *Self) ?T {
            if (self.index >= self.items.len) return null;
            const temp = self.items[self.index];
            self.index += 1;
            return temp;
        }
    };
}
