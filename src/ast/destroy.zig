const std = @import("std");
const Allocator = std.mem.Allocator;

const Node = @import("Node.zig");

pub fn destroyList(allocator: *Allocator, list: *Node.NodeList) void {
    for (list.items) |item|
        destroyNode(allocator, item);
    list.deinit(allocator);
}

pub fn destroyNode(ator: *Allocator, node: *Node) void {
    switch (node.tag) {
        .VarDefine => {
            const define = node.as(.VarDefine);
            if (define.type_) |tn| destroyNode(ator, tn);
            destroyNode(ator, define.value);
        },
        .Block => {
            const block = node.as(.Block);
            destroyList(ator, &block.list);
        },
        .FnBlock => {
            const fn_block = node.as(.FnBlock);
            destroyProto(ator, &fn_block.proto);
            destroyNode(ator, fn_block.body);
        },
        .If => {
            const if_node = node.as(.If);
            destroyNode(ator, if_node.cond);
            destroyNode(ator, if_node.body);
            if (if_node.elif) |elif| destroyNode(ator, elif);
        },
        .While => {
            const while_node = node.as(.While);
            destroyNode(ator, while_node.cond);
            destroyNode(ator, while_node.body);
        },
        .Ternary => {
            const ternary = node.as(.Ternary);
            destroyNode(ator, ternary.cond);
            destroyNode(ator, ternary.first);
            destroyNode(ator, ternary.second);
        },
        .BinaryOp => {
            const binary = node.as(.BinaryOp);
            destroyNode(ator, binary.left);
            destroyNode(ator, binary.right);
        },
        .UnaryOp => {
            const unary = node.as(.UnaryOp);
            destroyNode(ator, unary.right);
        },
        .FuncCall => {
            const func_call = node.as(.FuncCall);
            destroyNode(ator, func_call.callee);
            destroyNode(ator, func_call.args);
        },
        .Tuple => {
            const tuple = node.as(.Tuple);
            destroyList(ator, &tuple.list);
        },
        .Variable, .Literal, .Error => {},
    }
    ator.destroy(node);
}

fn destroyProto(ator: *Allocator, proto: *Node.Proto) void {
    for (proto.args.items) |arg|
        destroyNode(ator, arg.type_);
    proto.args.deinit(ator);
    if (proto.return_type) |rt|
        destroyNode(ator, rt);
}
