const std = @import("std");
const stdout = std.io.getStdOut().writer();
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const TypeInfo = std.builtin.TypeInfo;

const Token = @import("Scanner.zig").Token;
const ansi = @import("ansi.zig");

pub const Node = @import("ast/Node.zig");
const printAST = @import("ast/print.zig").printList;
const renderAST = @import("ast/render.zig").render;
const destroyAST = @import("ast/destroy.zig");
const TypeChecker = @import("TypeChecker.zig");

const Self = @This();

allocator: *Allocator,
stmts: Node.List(*Node),

path: ?[]const u8,
source: []const u8,

pub fn init(allocator: *Allocator, source: []const u8, path: ?[]const u8) Self {
    return Self{
        .allocator = allocator,
        .stmts = Node.List(*Node){},
        .source = source,
        .path = path,
    };
}

pub fn createNode(self: *Self, comptime tag: Node.Tag, lc: Token.Lc, init_args: anytype) !*Node {
    return Node.create(self.allocator, tag, lc, init_args);
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

pub fn typeCheck(self: *Self) !void {
    var checker = TypeChecker.init(self);
    try checker.resolve();
}

pub fn err(lc: Token.Lc, msg: []const u8, out_stream: anytype) !void {
    return out_stream.errFormat(token, "{}", .{msg});
}

const errBold = ansi.attr(ansi.AT.Bold);
const errRedBold = ansi.multi(.{ ansi.red, errBold });
pub fn errFmt(self: *Self, lc: Token.Lc, comptime fmt: []const u8, args: anytype, out_stream: anytype) !void {
    if (self.path) |path| try errLocation(path, lc, out_stream);
    try out_stream.print(errRedBold(" error: ") ++ errBold(fmt) ++ "\n", args);
    try errCaret(lc, out_stream);
}

fn errLocation(path: []const u8, lc: Token.Lc, out_stream: anytype) !void {
    return out_stream.print(comptime errBold("./{}:{}:{}"), .{ path, lc.line, lc.column });
}

fn errCaret(lc: Token.Lc, out_stream: anytype) !void {
    try out_stream.print("{}\n", .{lc.lineStr});
    var i: usize = 1;
    while (i < lc.column) : (i += 1)
        try out_stream.writeAll(" ");
    try out_stream.writeAll(ansi.yellow("^") ++ "\n");
}
