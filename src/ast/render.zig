const std = @import("std");
const Node = @import("Node.zig");
const ansi = @import("../ansi.zig");
const ascii = std.ascii;

const defineStyle = ansi.color(ansi.FG.Blue);
const varStyle = ansi.color16(ansi.FG.Blue, .Bright);
const typeStyle = ansi.color16(ansi.FG.Red, .Bright);
const keywordStyle = ansi.color(ansi.FG.Magenta);
const symbolStyle = ansi.color(ansi.FG.White);
const literalStyle = ansi.color(ansi.FG.Yellow);

pub fn render(comptime out_stream: anytype, list: *Node.NodeList) !void {
    const OutStream = @TypeOf(out_stream);
    const Render = struct {
        const Self = @This();

        out: OutStream,
        depth: usize = 0,

        fn fillDepth(self: *Self) !void {
            var d: usize = 0;
            while (d < self.depth) : (d += 1)
                try self.out.writeAll("  ");
        }

        inline fn write(self: *Self, msg: []const u8) !void {
            return self.out.writeAll(msg);
        }
         
        fn renderNode(self: *Self, node: *Node) anyerror!void {
            switch (node.tag) {
                .VarDefine => {
                    var define = node.as(.VarDefine);

                    const mutText = if (define.mut) symbolStyle("!") else "";
                    try self.out.print(defineStyle("{}") ++ "{} ", .{ define.name, mutText });
                    if (define.type_) |t| {
                        try self.renderNode(t);
                        try self.out.writeAll(" ");
                    }
                    try self.out.writeAll(":= ");
                    try self.renderNode(define.value);
                    try self.out.writeAll(";");
                },
                .Block => {
                    const block = node.as(.Block);

                    try self.out.writeAll("{\n");
                    self.depth += 1;
                    for (block.list.items) |item, i| {
                        try self.fillDepth();
                        try self.renderNode(item);
                        try self.out.writeAll("\n");
                    }
                    self.depth -= 1;
                    try self.fillDepth();
                    try self.out.writeAll("}");
                },
                .Proto => {
                    const proto: *Node.Proto = node.as(.Proto);
                    for (proto.args.items) |arg, i| {
                        if (arg.name) |name| try self.write(name);
                        try self.write(" ");
                        try self.renderNode(arg.type_);
                        if (i + 1 < proto.args.items.len) 
                            try self.write(", ");
                    }
                    try self.write(" => ");
                    if (proto.return_type) |rt|    
                        try self.renderNode(rt);
                },
                .If => {
                    const if_node = node.as(.If);

                    try self.out.writeAll(keywordStyle("if") ++ " (");
                    try self.renderNode(if_node.cond);
                    try self.out.writeAll(") ");
                    try self.renderNode(if_node.body);

                    var temp: ?*Node = if_node.elif;
                    while (temp) |elif| {
                        if (elif.tag == .If) {
                            const elif_node = elif.as(.If);
                            try self.out.writeAll(keywordStyle(" elif ") ++ "(");
                            try self.renderNode(elif_node.cond);
                            try self.out.writeAll(") ");
                            try self.renderNode(elif_node.body);
                            temp = elif_node.elif;
                        } else {
                            try self.out.writeAll(keywordStyle(" else "));
                            try self.renderNode(elif);
                            temp = null;
                        }
                    }
                },
                .While => {
                    const while_node = node.as(.While);

                    try self.out.writeAll(keywordStyle("while") ++ " (");
                    try self.renderNode(while_node.cond);
                    try self.out.writeAll(") ");
                    try self.renderNode(while_node.body);
                },
                .UnaryOp => {
                    const unary = node.as(.UnaryOp);

                    try self.out.print("{}", .{unary.op.toChars()});
                    try self.renderNode(unary.right);
                },
                .BinaryOp => {
                    const binary = node.as(.BinaryOp);

                    if (binary.right.is(.BinaryOp)) try self.out.writeAll("(");
                    try self.renderNode(binary.left);
                    if (binary.op == .Dot)
                        try self.out.print("{}", .{binary.op.toChars()})
                    else
                        try self.out.print(" {} ", .{binary.op.toChars()});
                    try self.renderNode(binary.right);
                    if (binary.right.is(.BinaryOp)) try self.out.writeAll(")");
                },
                .Ternary => {
                    const ternary = node.as(.Ternary);

                    try self.out.writeAll("(");
                    try self.renderNode(ternary.cond);
                    try self.out.writeAll(" ? ");
                    try self.renderNode(ternary.first);
                    try self.out.writeAll(" : ");
                    try self.renderNode(ternary.second);
                    try self.out.writeAll(")");
                },
                .Tuple => {
                    const tuple = node.as(.Tuple);

                    try self.out.writeAll("(");
                    for (tuple.list.items) |item, i| {
                        try self.renderNode(item);
                        if (i + 1 < tuple.list.items.len)
                            try self.out.writeAll(", ");
                    }
                    try self.out.writeAll(")");
                },
                .FuncCall => {
                    const call = node.as(.FuncCall);

                    try self.renderNode(call.callee);
                    try self.renderNode(call.args);
                },
                .Literal => try self.out.print(comptime literalStyle("{}"), .{node.as(.Literal).chars}),
                .Variable => {
                    const variable = node.as(.Variable);
                    if (ascii.isUpper(variable.name[0]))
                        try self.out.print(comptime typeStyle("{}"), .{variable.name})
                    else
                        try self.out.print(comptime varStyle("{}"), .{variable.name});
                },
                .Error => try self.out.print("\u{001b}[31m!{}!\u{001b}[0m", .{node.as(.Error).msg}),
            }
        }
    };

    var self = Render{ .out = out_stream };
    for (list.items) |item| {
        try self.renderNode(item);
        try self.out.writeAll("\n");
    }
}
