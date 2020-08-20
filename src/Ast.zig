const std = @import("std");
const stdout = std.io.getStdOut().writer();
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const TypeInfo = std.builtin.TypeInfo;

pub const Node = @import("ast/Node.zig");
const printAST = @import("ast/print.zig").printList;
const renderAST = @import("ast/render.zig").render;
const destroyAST = @import("ast/destroy.zig");

const Self = @This();

allocator: *Allocator,
stmts: Node.List(*Node),

pub fn init(allocator: *Allocator) Self {
    std.meta.refAllDecls(Node);
    return Self{
        .allocator = allocator,
        .stmts = Node.List(*Node){},
    };
}

pub fn createNode(self: *Self, comptime tag: Node.Tag, init_args: anytype) !*Node {
    return Node.create(self.allocator, tag, init_args);
}

pub fn appendStmt(self: *Self, node: *Node) !void {
    try self.stmts.append(node);
}

pub fn print(self: *Self) !void {
    try printAST(&self.stmts, 0, stdout);
}

pub fn render(self: *Self) !void {
    //try renderAST(@TypeOf(stdout), stdout, &self.stmts);
    try renderAST(stdout, &self.stmts);
}

pub fn deinit(self: *Self) void {
    destroyAST.destroyList(self.allocator, &self.stmts);
}

pub fn destroyNode(self: *Self, node: *Node) void {
    destroyAST.destroyNode(self.allocator, node);
}