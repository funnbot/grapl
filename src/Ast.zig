const std = @import("std");
var stdout = std.io.getStdOut().writer();
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const TypeInfo = std.builtin.TypeInfo;

pub const Node = @import("ast/Node.zig");
const printAST = @import("ast/print.zig").printList;
const renderAST = @import("ast/render.zig").renderList;

const Self = @This();

allocator: *Allocator,
stmts: Node.NodeList,

pub fn init(allocator: *Allocator) Self {
    std.meta.refAllDecls(Node);
    return Self{
        .allocator = allocator,
        .stmts = Node.NodeList.init(),
    };
}

pub fn createNode(self: *Self, comptime tag: Node.Tag, init_args: anytype) !*Node {
    return Node.create(self.allocator, tag, init_args);
}

pub fn appendStmt(self: *Self, node: *Node) !void {
    try self.stmts.append(node);
}

pub fn print(self: *Self) !void {
    try printAST(&self.stmts, 0, &stdout);
}

pub fn deinit(self: *Self) void {
    self.stmts.deinit(self.allocator);
}

const ArrayListWriteError = error{ArrayListWriteError};
fn arrayListWrite(context: *std.ArrayList(u8), bytes: []const u8) ArrayListWriteError!usize {
    context.appendSlice(bytes) catch return error.ArrayListWriteError;
    return bytes.len;
}

var sourceDepth: usize = 0;
const ArrayListWriter = std.io.Writer(*std.ArrayList(u8), ArrayListWriteError, arrayListWrite);
fn fillDepth(list: *ArrayListWriter) !void {
    var depth: usize = 0;
    while (depth < sourceDepth) : (depth += 1)
        try list.writeAll("  ");
}
fn nodeToSource(list: *ArrayListWriter, treeNode: *Node) anyerror!void {
    switch (treeNode.*) {
        .VarDefine => |node| {
            const mutText = if (node.mut) "!" else "";
            try list.print("{}{} ", .{ node.name, mutText });
            if (node.typename) |tName| {
                try nodeToSource(list, tName);
                try list.writeAll(" ");
            }
            try list.writeAll(":= ");
            try nodeToSource(list, node.value);
            try list.writeAll(";");
        },
        .Block => |*node| {
            try fillDepth(list);
            try list.writeAll("{\n");
            sourceDepth += 1;
            for (node.list.list.items) |n, i| {
                try fillDepth(list);
                try nodeToSource(list, n);
                try list.writeAll("\n");
            }
            sourceDepth -= 1;
            try fillDepth(list);
            try list.writeAll("}");
        },
        .If => |node| {
            try list.writeAll("if (");
            try nodeToSource(list, node.cond);
            try list.writeAll(") ");
            try nodeToSource(list, node.body);

            var temp: ?*Node = node.elif;
            while (temp) |elif| {
                if (elif.tagType() == .If) {
                    try list.writeAll(" elif (");
                    try nodeToSource(list, elif.If.cond);
                    try list.writeAll(") ");
                    try nodeToSource(list, elif.If.body);
                    temp = elif.If.elif;
                } else {
                    try list.writeAll(" else ");
                    try nodeToSource(list, elif);
                    temp = null;
                }
            }
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
            if (node.args) |args| {
                if (args.tagType() != .Tuple) try list.writeAll("(");
                try nodeToSource(list, args);
                if (args.tagType() != .Tuple) try list.writeAll(")");
            } else
                try list.writeAll("()");
        },
        .Type => |node| try list.print("{}", .{node.typename}),
        .Constant => |node| try list.print("{}", .{node.chars}),
        .Variable => |node| try list.print("{}", .{node.name}),
        .Error => |node| try list.print("\u{001b}[31m!{}!\u{001b}[0m", .{node.msg}),
        else => |node| try list.print("!{}!", .{treeNode.typeName()}),
    }
}
pub fn toSource(self: *Self, allocator: *Allocator) ![]const u8 {
    var buffer = std.ArrayList(u8).init(allocator);
    var list = ArrayListWriter{ .context = &buffer };

    for (self.stmts.list.items) |stmt| {
        try nodeToSource(&list, stmt);
        try list.writeAll("\n");
    }

    sourceDepth = 0;
    return buffer.toOwnedSlice();
}
