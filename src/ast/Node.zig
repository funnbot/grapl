const std = @import("std");
const meta = std.meta;
const trait = meta.trait;
const assert = std.debug.assert;

const TypeInfo = std.builtin.TypeInfo;
const Allocator = std.mem.Allocator;
const FileWriter = std.fs.File.Writer;

const Scanner = @import("../Scanner.zig");
const Token = Scanner.Token;
const TokenType = Scanner.TokenType;

const ansi = @import("../ansi.zig");

const Node = @This();

// Base
tag: Tag,

pub fn create(allocator: *Allocator, comptime tag: Tag, init_args: anytype) !*Node {
    var node = try allocator.create(tag.Type());
    node.* = init_args;
    node.base = Node{.tag = tag};
    return &node.base;
}

pub fn as(self: *Node, comptime tag: Tag) *(tag.Type()) {
    assert(self.tag == tag);
    return self.asType(tag.Type());
}

pub fn asType(self: *Node, comptime T: type) *T {
    return @fieldParentPtr(T, "base", self);
}

pub fn is(self: *Node, comptime tag: Tag) bool {
    return self.tag == tag;
}

pub const Tag = enum {
    VarDefine,
    Block,
    If,
    While,
    Ternary,
    BinaryOp,
    UnaryOp,
    FuncCall,
    Variable,
    Literal,
    Tuple,
    Error,

    pub fn Type(comptime self: Tag) type {
        inline for (meta.declarations(Node)) |decl| {
            // All node structs will be:
            // public, of type Struct, have a base field of Node
            if (decl.is_pub and
                @as(@TagType(TypeInfo.Declaration.Data), decl.data) == .Type and
                @hasField(decl.data.Type, "base") and
                decl.name.len == @tagName(self).len and
                std.mem.eql(u8, decl.name, @tagName(self)))
                return decl.data.Type;
        }
        @compileLog("unmatched type tag", self);
    }
};

const Identifier = []const u8;

// Statements
pub const VarDefine = struct {
    base: Node = undefined,
    name: Identifier,
    typename: ?*Node,
    value: *Node,
    mut: bool,
};

pub const Block = struct {
    base: Node = undefined,
    list: List = List.init(),
};

// Expressions

pub const If = struct {
    base: Node = undefined,
    cond: *Node,
    body: *Node,
    /// IfNode for elif, Statement for else
    elif: ?*Node,
};

pub const While = struct {
    base: Node = undefined,
    cond: *Node,
    body: *Node,
};

pub const Ternary = struct {
    base: Node = undefined,
    cond: *Node,
    first: *Node,
    second: *Node,
};

pub const BinaryOp = struct {
    base: Node = undefined,
    left: *Node,
    op: TokenType,
    right: *Node,
};

pub const UnaryOp = struct {
    base: Node = undefined,
    op: TokenType,
    right: *Node,
};

pub const FuncCall = struct {
    base: Node = undefined,
    callee: *Node,
    args: *Node,
};

pub const Variable = struct {
    base: Node = undefined,
    name: Identifier,
};

pub const Tuple = struct {
    base: Node = undefined,
    list: List = List.init(),
};

pub const Literal = struct {
    base: Node = undefined,
    chars: Identifier,
    typename: TokenType,
};

pub const Error = struct {
    base: Node = undefined,
    msg: []const u8,
};

pub const List = struct {
    data: std.ArrayListUnmanaged(*Node),

    pub fn init() List {
        return List{
            .data = std.ArrayListUnmanaged(*Node){},
        };
    }

    pub fn append(self: *List, allocator: *Allocator, node: *Node) !void {
        return self.data.append(allocator, node);
    }

    pub fn items(self: *List) []*Node {
        return self.data.items;
    }

    pub fn size(self: *const List) usize {
        return self.data.items.len;
    }
};

test "why" {
    std.debug.print("\n", .{});
    var node = try Node.create(std.testing.allocator, .VarDefine, .{
        .name = "foo",
        .typename = null,
        .value = try Node.create(std.testing.allocator, .If, .{
            .cond = try Node.create(std.testing.allocator, .Variable, .{ .name = "cond" }),
            .body = try Node.create(std.testing.allocator, .Literal, .{ .chars = "1.1", .typename = TokenType.Float }),
            .elif = null,
        }),
        .mut = false,
    });
    try node.print(0, &std.io.getStdErr().writer());
    node.destroy(std.testing.allocator);
}
