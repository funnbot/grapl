const std = @import("std");
const stdout = std.io.getStdOut().writer();
const Allocator = std.mem.Allocator;

const scanner = @import("../scanner.zig");
const TokenType = scanner.TokenType;
const Token = scanner.Token;

const Ident = []const u8;

// Reuse nodes for use beyond parsing?
// Add type annotations / constants to values, or make new nodes as a pop and replace?

// As a union it would be very easy to do a type swap, instead of adding the info to each node

pub const TreeNode = union(enum) {
    // Statements
    VarDefine: VarDefineNode,

    // Expression
    Ternary: TernaryNode,
    BinaryOp: BinaryOpNode,
    UnaryOp: UnaryOpNode,
    FuncCall: FuncCallNode,

    // TypeBlock

    // Variable
    Constant: ConstantNode,
    Variable: VariableNode,

    // Type
    Type: TypeNode,
    Tuple: TupleNode,

    // Special
    List: ListNode,
    Error: ErrorNode,

    pub const TagType = @TagType(TreeNode);
    const Self = @This();

    // Statement Nodes
    pub const VarDefineNode = struct {
        name: Ident,
        typename: ?*TreeNode,
        value: *TreeNode,
        mut: bool,

        pub fn init(name: Ident, typename: ?*TreeNode, value: *TreeNode, mut: bool) Self {
            return TreeNode{ .VarDefine = .{ .name = name, .typename = typename, .value = value, .mut = mut } };
        }
        pub fn print(self: *@This(), depth: usize) !void {
            const mutText = if (self.mut) "mut" else "";
            try stdout.print("{} {}\n", .{ mutText, self.name });
            if (self.typename) |tName| try tName.print(depth + 1);
            try self.value.print(depth + 1);
        }
        pub fn destroy(self: *@This(), allocator: *Allocator) void {
            if (self.typename) |tName| tName.destroy(allocator);
            self.value.destroy(allocator);
        }
    };

    // Expression Nodes
    pub const TernaryNode = struct {
        cond: *TreeNode,
        first: *TreeNode,
        second: *TreeNode,

        pub fn init(cond: *TreeNode, first: *TreeNode, second: *TreeNode) Self {
            return TreeNode{ .Ternary = .{ .cond = cond, .first = first, .second = second } };
        }

        pub fn print(self: *@This(), depth: usize) !void {
            try stdout.writeAll("\n");
            try self.cond.print(depth + 1);
            try self.first.print(depth + 1);
            try self.second.print(depth + 1);
        }

        pub fn destroy(self: *@This(), allocator: *Allocator) void {
            self.cond.destroy(allocator);
            self.first.destroy(allocator);
            self.second.destroy(allocator);
        }
    };

    pub const BinaryOpNode = struct {
        left: *TreeNode,
        op: TokenType,
        right: *TreeNode,

        pub fn init(left: *TreeNode, op: TokenType, right: *TreeNode) Self {
            return TreeNode{ .BinaryOp = .{ .left = left, .op = op, .right = right } };
        }

        pub fn print(self: *@This(), depth: usize) !void {
            try stdout.print(" {}\n", .{@tagName(self.op)});
            try self.left.print(depth + 1);
            try self.right.print(depth + 1);
        }

        pub fn destroy(self: *@This(), allocator: *Allocator) void {
            self.left.destroy(allocator);
            self.right.destroy(allocator);
        }
    };

    pub const UnaryOpNode = struct {
        op: TokenType,
        right: *TreeNode,

        pub fn init(op: TokenType, right: *TreeNode) Self {
            return TreeNode{ .UnaryOp = .{ .op = op, .right = right } };
        }

        pub fn print(self: *@This(), depth: usize) !void {
            try stdout.print(" {}\n", .{@tagName(self.op)});
            try self.right.print(depth + 1);
        }

        pub fn destroy(self: *@This(), allocator: *Allocator) void {
            self.right.destroy(allocator);
        }
    };

    pub const FuncCallNode = struct {
        callee: *TreeNode,
        args: *TreeNode,

        pub fn init(callee: *TreeNode, args: *TreeNode) Self {
            return TreeNode{ .FuncCall = .{ .callee = callee, .args = args } };
        }

        pub fn print(self: *@This(), depth: usize) !void {
            try stdout.writeAll("\n");
            try self.callee.print(depth + 1);
            try self.args.print(depth + 1);
        }

        pub fn destroy(self: *@This(), allocator: *Allocator) void {
            self.callee.destroy(allocator);
            self.args.destroy(allocator);
        }
    };

    // Variable Nodes
    pub const VariableNode = struct {
        name: Ident,

        pub fn init(name: Ident) Self {
            return TreeNode{ .Variable = .{ .name = name } };
        }

        pub fn print(self: *@This(), depth: usize) !void {
            try stdout.print(" {}\n", .{self.name});
        }
    };

    pub const TypeNode = struct {
        typename: Ident,

        pub fn init(typename: Ident) Self {
            return TreeNode{ .Type = .{ .typename = typename } };
        }

        pub fn print(self: *@This(), depth: usize) !void {
            try stdout.print(" {}\n", .{self.typename});
        }
    };

    pub const TupleNode = struct {
        list: ListNode,

        pub fn init(allocator: *Allocator) Self {
            return Self{ .Tuple = .{ .list = ListNode.init(allocator).List } };
        }

        pub fn print(self: *@This(), depth: usize) !void {
            return self.list.print(depth);
        }

        pub fn destroy(self: *@This(), allocator: *Allocator) void {
            self.list.destroy(allocator);
        }
    };

    pub const ConstantNode = struct {
        chars: Ident,
        typename: TokenType,

        pub fn init(chars: Ident, typename: TokenType) Self {
            return Self{ .Constant = .{ .chars = chars, .typename = typename } };
        }

        pub fn print(self: *@This(), depth: usize) !void {
            try stdout.print(" ({}){}\n", .{ @tagName(self.typename), self.chars });
        }
    };

    // Special
    pub const ListNode = struct {
        list: std.ArrayList(*TreeNode),

        pub fn init(allocator: *Allocator) Self {
            return Self{ .List = .{ .list = std.ArrayList(*TreeNode).init(allocator) } };
        }

        pub fn append(self: *@This(), item: *TreeNode) !void {
            return self.list.append(item);
        }

        pub fn size(self: *@This()) usize {
            return self.list.items.len;
        }

        pub fn print(self: *@This(), depth: usize) !void {
            try stdout.print(" ({})\n", .{self.list.items.len});
            for (self.list.items) |item| try item.print(depth + 1);
        }

        pub fn destroy(self: *@This(), allocator: *Allocator) void {
            for (self.list.items) |item| item.destroy(allocator);
            self.list.deinit();
        }
    };

    pub const ErrorNode = struct {
        msg: []const u8,

        pub fn init(msg: []const u8) Self {
            return Self{ .Error = .{ .msg = msg } };
        }

        pub fn print(self: *@This(), depth: usize) !void {
            try stdout.print(": {}\n", .{self.msg});
        }
    };

    pub fn print(self: *TreeNode, depth: usize) anyerror!void {
        const tag = self.tagType();
        const tagValue = @enumToInt(tag);
        try printTree(@tagName(tag), depth, false);
        inline for (std.meta.fields(TreeNode)) |field| {
            if (field.enum_field.?.value == tagValue)
                if (std.meta.trait.hasFn("print")(field.field_type))
                // Tasty af polymorphism
                    return field.field_type.print(&@field(self.*, field.name), depth);
        }
        unreachable;
    }

    pub fn destroy(self: *TreeNode, allocator: *Allocator) void {
        const tag = self.tagType();
        const tagValue = @enumToInt(tag);
        inline for (std.meta.fields(TreeNode)) |field| {
            if (field.enum_field.?.value == tagValue) {
                // Destroy the branches
                if (comptime std.meta.trait.hasFn("destroy")(field.field_type)) {
                    // Tasty af polymorphism
                    field.field_type.destroy(&@field(self.*, field.name), allocator);
                }
                return allocator.destroy(self);
            }
        }
        unreachable;
    }

    pub fn printTree(val: []const u8, depth: usize, newline: bool) anyerror!void {
        var d: usize = 0;
        while (d < depth) : (d += 1) try stdout.writeAll("\u{001b}[30;1m\u{001b}[1m│ \u{001b}[0m");
        try stdout.print("\u{001b}[30;1m\u{001b}[1m├─\u{001b}[0m{}", .{val});
        if (newline) try stdout.writeAll("\n");
    }

    pub fn typeName(self: *TreeNode) []const u8 {
        const tag = self.tagType();
        const tagValue = @enumToInt(tag);
        inline for (std.meta.fields(TreeNode)) |field| {
            if (field.enum_field.?.value == tagValue)
                return @typeName(field.field_type);
        }
        unreachable;
    }

    pub fn tagType(self: *TreeNode) @TagType(TreeNode) {
        return @as(@TagType(TreeNode), self.*);
    }

    pub fn assertTag(self: *TreeNode, tag: TagType) void {
        if (self.tagType() != tag)
            unreachable;
    }
};
