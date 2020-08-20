const ansi = @import("../ansi.zig");
const Node = @import("Node.zig");

const MAX_DEPTH = 20;

pub const Error = error{
    DiskQuota,
    FileTooBig,
    InputOutput,
    NoSpaceLeft,
    AccessDenied,
    BrokenPipe,
    SystemResources,
    OperationAborted,
    WouldBlock,
    Unexpected,
};

pub fn printList(list: *Node.List(*Node), depth: usize, out_stream: anytype) Error!void {
    for (list.items) |item, i| {
        try printNode(item, depth, (i + 1 == list.items.len), out_stream);
    }
}

fn printNode(node: *Node, depth: usize, last: bool, out_stream: anytype) Error!void {
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
        .While => {
            const while_node = node.as(.While);
            try out_stream.writeAll("\n");
            try printNode(while_node.cond, depth + 1, false, out_stream);
            try printNode(while_node.body, depth + 1, true, out_stream);
        },
        .VarDefine => {
            const define = node.as(.VarDefine);
            const mutText = if (define.mut) " mut " else " ";
            try out_stream.print("{}{}\n", .{ mutText, define.name });
            if (define.type_) |tn| try printNode(tn, depth + 1, false, out_stream);
            try printNode(define.value, depth + 1, true, out_stream);
        },
        .Block => {
            const block = node.as(.Block);
            try out_stream.print(" ({})\n", .{block.list.items.len});
            try printList(&block.list, depth + 1, out_stream);
        },
        .Proto => {
            const proto = node.as(.Proto);
            try out_stream.writeAll("\n");
            for (proto.args.items) |arg, i| {
                const isLast = proto.return_type == null and
                    i + 1 == proto.args.items.len;
                try printNode(arg.type_, depth + 1, isLast, out_stream);
            }
            if (proto.return_type) |rt|
                try printNode(rt, depth + 1, true, out_stream);
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
            try out_stream.print(" ({})\n", .{tuple.list.items.len});
            try printList(&tuple.list, depth + 1, out_stream);
        },
        .Error => {
            const error_node = node.as(.Error);
            try out_stream.print(": {}\n", .{error_node.msg});
        },
    }
}

pub fn printTree(name: []const u8, depth: usize, last: bool, out_stream: anytype) Error!void {
    const treeStyle = ansi.multi(.{ ansi.color16(ansi.FG.Red, .Bright), ansi.attr(ansi.AT.Bold) });
    const nodeStyle = ansi.multi(.{ ansi.color16(ansi.FG.Green, .Bright), ansi.attr(ansi.AT.Bold) });

    var d: usize = 0;
    while (d < depth) : (d += 1) {
        try out_stream.writeAll(comptime treeStyle("┊ "));
    }
    const pipe = if (last) "┗╸" else "┣╸";
    try out_stream.print(treeStyle("{}") ++ nodeStyle("{}"), .{ pipe, name });
}
