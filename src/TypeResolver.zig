const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const stderr = std.io.getStdErr().writer();
const assert = std.debug.assert;

const Scope = @import("type_resolver/Scope.zig");
const Nodes = @import("ast/Node.zig").Nodes;
const Ast = @import("Ast.zig");
const Node = Ast.Node;

const Self = @This();

ast: *Ast,
allocator: *Allocator,

scope: ?*Scope = null,

pub const Error = error{
    StdOutWrite,
} || Scope.Error || Allocator.Error;

pub fn init(allocator: *Allocator, ast: *Ast) Self {
    return .{
        .ast = ast,
        .allocator = allocator,
    };
}

pub fn resolve(self: *Self) Error!void {
    for (self.ast.stmts.items) |item| {
        try self.resolveTopLevel(item);
    }
}

fn resolveTopLevel(self: *Self, node: *Node) Error!void {
    switch (node.tag) {
        .VarDefine => {},
        else => try self.errFmt(node, "forbidden top level.", .{}),
    }
}

fn resolveExpression(self: *Self, node: *Node) Error!void {
    switch (node.tag) {
        .Literal => {
            
        },
        else => try self.errFmt(node, "forbidden expression.", .{}),
    }
}

fn beginScope(self: *Self) Error!void {
    const scope = try self.allocator.create(Scope);
    scope.* = Scope.init(self.allocator, self.scope);
    self.scope = scope;
}

fn endScope(self: *Self) void {
    assert(self.scope != null);
    const outer = self.scope.?.outer;
    self.allocator.destroy(self.scope);
    self.scope = outer;
}

// Errors

fn errFmt(self: *Self, node: *Node, comptime fmt: []const u8, args: anytype) Error!void {
    self.ast.errFmt(node.lc, fmt, args, stderr) catch return Error.StdOutWrite;
}
