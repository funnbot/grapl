const ansi = @import("../ansi.zig");
const Node = @import("Node.zig");

const MAX_DEPTH = 10;

pub fn printList(list: *Node.NodeList, depth: usize, out_stream: anytype) !void {
    for (list.items.items) |item, i| {
        try printNode(item, depth, (i + 1 == list.size()), out_stream);
    }
}

fn printNode(node: *Node, depth: usize, last: bool, out_stream: anytype) anyerror!void {
    if (depth > MAX_DEPTH) return;

    try printTree(@tagName(node.tag), depth, last, out_stream);
    switch (node.tag) {
        .If => {
            const if_node = node.as(.If);
            try out_stream.writeAll("\n");
            try printNode(if_node.cond, depth + 1, false, out_stream);
            try printNode(if_node.body, depth + 1, if_node.elif == null, out_stream);
            if (if_node.elif) |elif| try printNode(elif, depth + 1, true, out_stream);
        },
        .VarDefine => {
            const define = node.as(.VarDefine);
            const mutText = if (define.mut) " mut " else " ";
            try out_stream.print("{}{}\n", .{ mutText, define.name });
            if (define.typename) |tn| try printNode(tn, depth + 1, false, out_stream);
            try printNode(define.value, depth + 1, true, out_stream);
        },
        .Block => {
            const block = node.as(.Block);
            try out_stream.print(" ({})\n", .{block.list.size()});
            try printList(&block.list, depth + 1, out_stream);
        },
        .Literal => {
            const literal = node.as(.Literal);
            try out_stream.print(" ({}) {}\n", .{ @tagName(literal.typename), literal.chars });
        },
        .Variable => {
            const variable = node.as(.Variable);
            try out_stream.print(" {}\n", .{
                variable.name,
            });
        },
        .Ternary => {
            const ternary = node.as(.Ternary);
            try out_stream.writeAll("\n");
            try printNode(ternary.cond, depth + 1, false, out_stream);
            try printNode(ternary.first, depth + 1, false, out_stream);
            try printNode(ternary.second, depth + 1, true, out_stream);
        },
        .BinaryOp => {
            const binary = node.as(.BinaryOp);
            try out_stream.print(" {}\n", .{binary.op.toChars()});
            try printNode(binary.left, depth + 1, false, out_stream);
            try printNode(binary.right, depth + 1, true, out_stream);
        },
        .UnaryOp => {
            const unary = node.as(.UnaryOp);
            try out_stream.print(" {}\n", .{unary.op.toChars()});
            try printNode(unary.right, depth + 1, true, out_stream);
        },
        .FuncCall => {
            const func_call = node.as(.FuncCall);
            try out_stream.writeAll("\n");
            try printNode(func_call.callee, depth + 1, false, out_stream);
            try printNode(func_call.args, depth + 1, true, out_stream);
        },
        .Tuple => {
            const tuple = node.as(.Tuple);
            try out_stream.print(" ({})\n", .{tuple.list.size()});
            try printList(&tuple.list, depth + 1, out_stream);
        },
        .Error => {
            const error_node = node.as(.Error);
            try out_stream.print(": {}", .{error_node.msg});
        },
        // else => {
        //     try out_stream.print("{}", .{@tagName(node.tag)});
        // },
    }
}

pub fn printTree(name: []const u8, depth: usize, last: bool, out_stream: anytype) !void {
    const grayBold = ansi.multi(.{ ansi.color16(ansi.FG.Red, .Bright), ansi.attr(ansi.AT.Bold) });

    var range = Range.init(2, 3);
    while (range.next()) |e| try out_stream.print("Hi: {}\n", .{e});

    var d: usize = 0;
    while (d < depth) : (d += 1) {
        try out_stream.writeAll(comptime grayBold("┊ "));
    }
    if (last)
        try out_stream.print(grayBold("┗╸") ++ "{}", .{name})
    else
        try out_stream.print(grayBold("┣╸") ++ "{}", .{name});
}

const Range = struct {
    const Dir = enum(i2) { Inc = 1, Dec = -1 };

    i: isize,

    limit: isize,
    dir: Dir,
    stepAmount: isize = 1,

    pub fn init(start: isize, end_exc: isize) Range {
        return Range{
            .i = start,
            .limit = end_exc,
            .dir = if (start <= end_exc) .Inc else .Dec,
        };
    }

    pub fn next(self: *Range) ?isize {
        const temp = self.i;
        if (if (self.dir == .Inc) self.i >= self.limit else self.i <= self.limit)
            return null;
        self.i += self.stepAmount * @enumToInt(self.dir);
        return temp;
    }

    pub fn step(self: *Range, stepAmount: isize) Range {
        self.stepAmount = stepAmount;
        return self.*;
    }
};
