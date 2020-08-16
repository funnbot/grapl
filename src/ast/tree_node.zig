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

const DestroyFn = fn (self: *Node, allocator: *Allocator) void;
const PrintFn = fn (self: *Node, depth: usize, out_stream: *FileWriter) anyerror!void;

const Namespace = @This();

// Base
pub const Node = struct {
    tag: Tag,

    destroyFn: DestroyFn,
    printFn: ?PrintFn,

    fn init(comptime tag: Tag) Node {
        const T = tag.Type();
        return Node{
            .tag = tag, // trait.hasFn fails for some reason.
            .destroyFn = if (@hasDecl(T, "destroy")) T.destroy else destroyDefault(T),
            .printFn = if (@hasDecl(T, "print")) T.print else null,
        };
    }

    pub fn create(allocator: *Allocator, comptime tag: Tag, init_args: anytype) !*Node {
        var node = try allocator.create(tag.Type());
        node.* = init_args;
        node.base = Node.init(tag);
        return &node.base;
    }

    pub fn print(self: *Node, depth: usize, out_stream: anytype) anyerror!void {
        const hasFn = self.printFn != null;
        try printTree(@tagName(self.tag), depth, !hasFn, out_stream);
        if (hasFn) try self.printFn.?(self, depth, out_stream);
    }

    pub fn destroy(self: *Node, allocator: *Allocator) void {
        self.destroyFn(self, allocator);
    }

    pub fn as(self: *Node, comptime tag: Tag) *(tag.Type()) {
        assert(self.tag == tag);
        return self.asType(tag.Type());
    }

    pub fn asType(self: *Node, comptime T: type) *T {
        return @fieldParentPtr(T, "base", self);
    }
};

pub const Tag = enum {
    VarDefine,
    Block,
    If,
    Ternary,
    BinaryOp,
    UnaryOp,
    FuncCall,
    Variable,
    Literal,
    Tuple,
    Error,

    pub fn Type(comptime self: Tag) type {
        inline for (meta.declarations(Namespace)) |decl| {
            // All node structs will be:
            // public, of type Struct, have a base field of Node
            if (decl.is_pub and
                @as(@TagType(TypeInfo.Declaration.Data), decl.data) == .Type and
                @hasField(decl.data.Type, "base") and
                meta.fieldInfo(decl.data.Type, "base").field_type == Node and
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

    pub fn print(node: *Node, depth: usize, out_stream: *FileWriter) anyerror!void {
        const self = node.as(.VarDefine);
        const mutText = if (self.mut) " mut " else " ";
        try out_stream.print("{}{}\n", .{ mutText, self.name });
        if (self.typename) |tn| try tn.print(depth + 1, out_stream);
        try self.value.print(depth + 1, out_stream);
    }
};

pub const Block = struct {
    base: Node = undefined,
    list: NodeList = NodeList.init(),

    pub fn print(node: *Node, depth: usize, out_stream: *FileWriter) anyerror!void {
        const self = node.as(.Block);
        try out_stream.print(" ({})\n", .{self.list.size()});
        try self.list.print(depth + 1, out_stream);
    }

    pub fn destroy(node: *Node, allocator: *Allocator) void {
        const self = node.as(.Block);
        self.list.deinit(allocator);
    }
};

// Expressions

pub const If = struct {
    base: Node = undefined,
    cond: *Node,
    body: *Node,
    /// IfNode for elif, Statement for else
    elif: ?*Node,

    pub fn print(node: *Node, depth: usize, out_stream: *FileWriter) anyerror!void {
        const self = node.as(.If);
        try out_stream.writeAll("\n");
        try self.cond.print(depth + 1, out_stream);
        try self.body.print(depth + 1, out_stream);
        if (self.elif) |e| try e.print(depth + 1, out_stream);
    }
};

pub const Ternary = struct {
    base: Node = undefined,
    cond: *Node,
    first: *Node,
    second: *Node,

    pub fn print(node: *Node, depth: usize, out_stream: *FileWriter) anyerror!void {
        const self = node.as(.Ternary);
        try self.cond.print(depth + 1, out_stream);
        try self.first.print(depth + 1, out_stream);
        try self.second.print(depth + 1, out_stream);
    }
};

pub const BinaryOp = struct {
    base: Node = undefined,
    left: *Node,
    op: TokenType,
    right: *Node,

    pub fn print(node: *Node, depth: usize, out_stream: *FileWriter) anyerror!void {
        const self = node.as(.BinaryOp);
        try out_stream.print(" {}\n", .{self.op.toChars()});
        try self.left.print(depth + 1, out_stream);
        try self.right.print(depth + 1, out_stream);
    }
};

pub const UnaryOp = struct {
    base: Node = undefined,
    op: TokenType,
    right: *Node,

    pub fn print(node: *Node, depth: usize, out_stream: *FileWriter) anyerror!void {
        const self = node.as(.UnaryOp);
        try out_stream.print(" ({}){}", .{ self.op, self.op.toChars() });
        try self.right.print(depth + 1, out_stream);
    }
};

pub const FuncCall = struct {
    base: Node = undefined,
    callee: *Node,
    args: *Node,

    pub fn print(node: *Node, depth: usize, out_stream: *FileWriter) anyerror!void {
        const self = node.as(.FuncCall);
        try out_stream.writeAll("\n");
        try self.callee.print(depth + 1, out_stream);
        try self.args.print(depth + 1, out_stream);
    }
};

pub const Variable = struct {
    base: Node = undefined,
    name: Identifier,

    pub fn print(node: *Node, depth: usize, out_stream: *FileWriter) anyerror!void {
        const self = node.as(.Variable);
        try out_stream.print(" {}\n", .{self.name});
    }
};

pub const Tuple = struct {
    base: Node = undefined,
    list: NodeList = NodeList.init(),

    pub fn print(node: *Node, depth: usize, out_stream: *FileWriter) anyerror!void {
        const self = node.as(.Tuple);
        try out_stream.print(" ({})\n", .{self.list.size()});
        try self.list.print(depth + 1, out_stream);
    }

    pub fn destroy(node: *Node, allocator: *Allocator) void {
        const self = node.as(.Tuple);
        self.list.deinit(allocator);
    }
};

pub const Literal = struct {
    base: Node = undefined,
    chars: Identifier,
    typename: TokenType,

    pub fn print(node: *Node, depth: usize, out_stream: *FileWriter) anyerror!void {
        const self = node.as(.Literal);
        try out_stream.print(" ({}) {}\n", .{ @tagName(self.typename), self.chars });
    }
};

pub const Error = struct {
    base: Node = undefined,
    msg: []const u8,

    pub fn print(node: *Node, depth: usize, out_stream: *FileWriter) anyerror!void {
        const self = node.as(.Error);
        try out_stream.print(": {}\n", .{self.msg});
    }
};

pub const NodeList = struct {
    items: std.ArrayListUnmanaged(*Node),

    pub fn init() NodeList {
        return NodeList{
            .items = std.ArrayListUnmanaged(*Node){},
        };
    }

    pub fn deinit(self: *NodeList, allocator: *Allocator) void {
        self.items.deinit(allocator);
    }

    pub fn append(self: *NodeList, allocator: *Allocator, node: *Node) !void {
        return self.items.append(allocator, node);
    }

    pub fn size(self: *NodeList) usize {
        return self.items.items.len;
    }

    pub fn print(self: *NodeList, depth: usize, out_stream: *FileWriter) !void {
        for (self.items.items) |item| {
            try item.print(depth + 1, out_stream);
        }
    }
};

pub fn printTree(name: []const u8, depth: usize, newline: bool, out_stream: *FileWriter) anyerror!void {
    const grayBold = ansi.multi(.{ ansi.color16(ansi.FG.Black, .Bright), ansi.attr(ansi.AT.Bold) });
    var d: usize = 0;
    while (d < depth) : (d += 1) try out_stream.writeAll(comptime grayBold("│ "));
    try out_stream.print(grayBold("├─") ++ "{}", .{name});
    if (newline) try out_stream.writeAll("\n");
}

fn destroyDefault(comptime T: type) DestroyFn {
    const Closure = struct {
        pub fn destroy(node: *Node, allocator: *Allocator) void {
            const self = node.asType(T);
            inline for (std.meta.fields(T)) |field| {
                if (field.field_type == *Node)
                    @field(self, field.name).destroy(allocator)
                else if (field.field_type == ?*Node) {
                    if (@field(self, field.name) != null)
                        @field(self, field.name).?.destroy(allocator);
                }
            }
            allocator.destroy(self);
        }
    };
    return Closure.destroy;
}

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
