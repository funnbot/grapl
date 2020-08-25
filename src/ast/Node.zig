const std = @import("std");
const meta = std.meta;
const trait = meta.trait;
const assert = std.debug.assert;

const TypeInfo = std.builtin.TypeInfo;
const Allocator = std.mem.Allocator;
const FileWriter = std.fs.File.Writer;

const GenTagType = @import("../Compose.zig").GenTagType;

const Scanner = @import("../Scanner.zig");
const Token = Scanner.Token;
const TokenType = Scanner.TokenType;

const ansi = @import("../ansi.zig");

const Node = @This();

// Base
tag: Tag = undefined,
lc: Token.Lc = undefined,

pub fn create(allocator: *Allocator, comptime tag: Tag, lc: Token.Lc, init_args: anytype) !*Node {
    var node = try allocator.create(genTagType.Type(tag));
    node.* = init_args;
    node.base.tag = tag;
    node.base.lc = lc;
    return &node.base;
}

pub fn as(self: *Node, comptime tag: Tag) *(genTagType.Type(tag)) {
    assert(self.tag == tag);
    return self.asType(genTagType.Type(tag));
}

pub fn asType(self: *Node, comptime T: type) *T {
    return @fieldParentPtr(T, "base", self);
}

pub fn is(self: *Node, comptime tag: Tag) bool {
    return self.tag == tag;
}

const genTagType = GenTagType(Node, Nodes, 15).init();
pub const Tag = genTagType.TagType;

pub const Identifier = []const u8;

pub const Proto = struct {
    pub const Arg = struct {
        name: ?Identifier,
        type_: *Node,
    };

    args: List(Arg) = List(Arg){},
    return_type: ?*Node,
};

pub const Nodes = struct {
    // Statements
    pub const VarDefine = struct {
        base: Node = undefined,
        name: Identifier,
        type_: ?*Node,
        value: *Node,
        mut: bool,
    };

    pub const Block = struct {
        base: Node = undefined,
        list: NodeList = NodeList{},
    };

    // Type Nodes

    pub const FnBlock = struct {
        base: Node = undefined,
        proto: Proto,
        /// Null = fn block pointer
        body: ?*Node,
    };

    // Expressions

    pub const If = struct {
        base: Node = undefined,
        cond: *Node,
        body: *Node,
        /// IfNode for elif, Statement for else
        elif: ?*Node,
    };

    const While = struct {
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
        list: NodeList = NodeList{},
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
};

pub const List = std.ArrayListUnmanaged;
pub const NodeList = List(*Node);

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
