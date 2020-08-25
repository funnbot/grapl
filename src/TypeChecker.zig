const std = @import("std");
const stderr = std.io.getStdErr().writer();
const Ast = @import("Ast.zig");
const Node = Ast.Node;

const Self = @This();

ast: *Ast,

pub const Error = error {
    StdOutWrite,
};

pub fn init(ast: *Ast) Self {
    return .{.ast = ast};
}

pub fn resolve(self: *Self) void {
    for (stmts.items) |item| {
        resolveTopLevel(item);
    }
}

fn resolveTopLevel(self: *Self, node: *Node) void {
    switch (node.tag) {
        else => self.errFmt(node, "unallowed top level node '{}'", .{@tagName(node.tag)}),
    }
}

fn errFmt(self: *Self, node: *Node, comptime fmt: []const u8, args: anytype) Error!void {
    self.ast.errFmt(node.lc, fmt, args, stderr) catch return Error.StdOutWrite;
}