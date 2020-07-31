const std = @import("std");
const stdout = std.io.getStdOut().writer();
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const TypeInfo = std.builtin.TypeInfo;

const ast_node = @import("ast/node.zig");
pub const TreeNode = ast_node.TreeNode;

const Self = @This();

allocator: *Allocator,
stmts: TreeNode.ListNode,

pub fn init(allocator: *Allocator) Self {
    return Self{
        .allocator = allocator,
        .stmts = TreeNode.ListNode.init(allocator).List,
    };
}

pub fn createNode(self: *Self, node: TreeNode) !*TreeNode {
    var nodePtr = try self.allocator.create(TreeNode);
    nodePtr.* = node;
    return nodePtr;
}

pub fn appendStmt(self: *Self, node: *TreeNode) !void {
    try self.stmts.append(node);
}

pub fn print(self: *Self) !void {
    try TreeNode.printTree("RootNode List", 0, false);
    try self.stmts.print(0);
}

pub fn destroy(self: *Self) void {
    self.stmts.destroy(self.allocator);
}

const ArrayListWriteError = error{ArrayListWriteError};
fn arrayListWrite(context: *std.ArrayList(u8), bytes: []const u8) ArrayListWriteError!usize {
    context.appendSlice(bytes) catch return error.ArrayListWriteError;
    return bytes.len;
}
const ArrayListWriter = std.io.Writer(*std.ArrayList(u8), ArrayListWriteError, arrayListWrite);
fn nodeToSource(list: *ArrayListWriter, treeNode: *TreeNode) anyerror!void {
    switch (treeNode.*) {
        .VarDefine => |node| {
            const mutText = if (node.mut) "!" else "";
            try list.print("{}{} ", .{ mutText, node.name });
            if (node.typename) |tName| {
                try nodeToSource(list, tName);
                try list.writeAll(" ");
            }
            try list.writeAll("= ");
            try nodeToSource(list, node.value);
        },
        .UnaryOp => |node| {
            try list.print("{}", .{node.op.toChars()});
            try nodeToSource(list, node.right);
        },
        .BinaryOp => |node| {
            try list.writeAll("(");
            try nodeToSource(list, node.left);
            if (node.op == .Dot)
                try list.print("{}", .{node.op.toChars()})
            else
                try list.print(" {} ", .{node.op.toChars()});
            try nodeToSource(list, node.right);
            try list.writeAll(")");
        },
        .Ternary => |node| {
            try list.writeAll("(");
            try nodeToSource(list, node.cond);
            try list.writeAll(" ? ");
            try nodeToSource(list, node.first);
            try list.writeAll(" : ");
            try nodeToSource(list, node.second);
            try list.writeAll(")");
        },
        .Tuple => |*node| {
            try list.writeAll("(");
            for (node.list.list.items) |n, i| {
                try nodeToSource(list, n);
                if (i + 1 < node.list.size()) try list.writeAll(", ");
            }
            try list.writeAll(")");
        },
        .FuncCall => |node| {
            try nodeToSource(list, node.callee);
            if (node.args.tagType() != .Tuple) try list.writeAll("(");
            try nodeToSource(list, node.args);
            if (node.args.tagType() != .Tuple) try list.writeAll(")");
        },
        .Type => |node| try list.print("{}", .{node.typename}),
        .Constant => |node| try list.print("{}", .{node.chars}),
        .Variable => |node| try list.print("{}", .{node.name}),
        else => |node| try list.print("!{}!", .{treeNode.typeName()}),
    }
}
pub fn toSource(self: *Self, allocator: *Allocator) ![]const u8 {
    var buffer = std.ArrayList(u8).init(allocator);
    var list = ArrayListWriter{ .context = &buffer };

    for (self.stmts.list.items) |stmt| {
        try nodeToSource(&list, stmt);
        try list.writeAll(";\n");
    }

    return buffer.toOwnedSlice();
}
