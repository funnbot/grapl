const std = @import("std");
const stdout = std.io.getStdOut().writer();
const stderr = std.io.getStdErr().writer();
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const warn = std.debug.warn;
const ansi = @import("ansi.zig");

const Ast = @import("Ast.zig");
const Node = Ast.Node;

const Stack = @import("stack.zig").Stack;

const Scanner = @import("Scanner.zig");
const TokenType = Scanner.TokenType;
const Token = Scanner.Token;

const Self = @This();

const INF_LOOP = 1000;

pub const ParseError = error{
// Wrappings
    StdOutWrite,
    AstAlloc,
    ArrayListAppend,
};

// global state
allocator: *Allocator,

// parser state
scanner: Scanner = undefined,
ast: Ast = undefined,

path: ?[]const u8 = null,
parser_error_opt: ParserErrorOption = undefined,
//state: ParseState = .Start,

// parsing state
current: Token = undefined,
next: Token = undefined,
hasError: bool = false,

pub fn init(allocator: *Allocator) Self {
    return Self{
        .allocator = allocator,
    };
}

pub const ParserErrorOption = enum { ShowErrors, SuppressErrors };
/// Caller owns ast, use ast.destroy()
pub fn parse(self: *Self, source: []const u8, parser_error_opt: ParserErrorOption, path: ?[]const u8) ParseError!Ast {
    self.path = path;
    self.scanner = Scanner.init(source);

    self.ast = Ast.init(self.allocator);
    errdefer self.ast.deinit();

    self.hasError = false;
    self.parser_error_opt = parser_error_opt;

    self.advance();

    var infLoop: usize = 0;
    while (self.next.tokenType != TokenType.EOF) {
        try self.appendList(&self.ast.stmts, try self.statement());
        if (self.hasError) self.synchronize();

        infLoop += 1;
        assert(infLoop < INF_LOOP);
    }

    return self.ast;
}

// -----------
// Type parser
// -----------

fn parseTypeOpt(self: *Self) ParseError!?*Node {
    return if (self.next.tokenType == .Identifier) {
        self.advance();
        return self.parseType();
    } else null;
}

fn parseType(self: *Self) ParseError!*Node {
    try self.ensure(.Identifier);

    const typename = self.current.chars;
    var node = try self.createNode(.Variable, .{ .name = typename });
    while (self.matchAdvance(.LeftParen)) {
        const args = try self.parseGroup(.AllowEmpty);
        node = try self.createNode(.FuncCall, .{ .callee = node, .args = args });
    }
    return node;
}

fn parseProto(self: *Self) ParseError!Node.Proto {
    var args = Node.List(Node.Proto.Arg){};
    if (self.next.tokenType == .RightBracket)
        return Node.Proto{ .args = args, .return_type = null };

    if (self.next.tokenType != .Arrow) {
        while (true) {
            try self.consume(.Identifier);
            var name: ?Node.Identifier = null;
            if (self.next.tokenType == .Identifier) {
                name = self.current.chars;
                self.advance();
            }
            const type_ = try self.parseType();

            try self.append(Node.Proto.Arg, &args, .{ .name = name, .type_ = type_ });
            if (!self.matchAdvance(.Comma)) break;
        }
    }
    // Special case for fn [Int] being: Int is the return type
    if (args.items.len == 1 and self.next.tokenType != .Arrow) {
        const type_ = args.items[0].type_;
        if (args.items[0].name != null) try self.err("unexpected named return type");
        args.deinit(self.ast.allocator);
        return Node.Proto{ .args = Node.List(Node.Proto.Arg){}, .return_type = type_ };
    }

    try self.consume(.Arrow);
    const type_ = try self.parseTypeOpt();
    return Node.Proto{ .args = args, .return_type = type_ };
}

// -----------------
// Precedence parser
// -----------------

/// Higher precedence value gets evaluated first
const Precedence = enum {
    None,
    Declaration,
    Assignment,
    Ternary,
    Equality,
    Comparison,
    Term,
    Factor,
    Unary,
    Accessor,
    Call,
    Base,

    pub fn next(self: Precedence) Precedence {
        return @intToEnum(Precedence, self.value() + 1);
    }
    pub fn value(self: Precedence) @TagType(Precedence) {
        return @enumToInt(self);
    }
    /// Precedence of binary operator
    pub fn ofBin(tokenType: TokenType) Precedence {
        return switch (tokenType) {
            .Equal => .Assignment,
            .EqualEqual, .BangEqual => .Equality,
            .Less, .LessEqual, .Greater, .GreaterEqual => .Comparison,
            .Plus, .Minus => .Term,
            .Star, .Slash => .Factor,
            .Dot => .Accessor,
            else => .None,
        };
    }
};

inline fn parsePrec(self: *Self, prec: Precedence) ParseError!*Node {
    return switch (prec) {
        .Declaration => self.parseDecl(prec),
        .Assignment => self.parseBinary(prec),
        .Ternary => self.parseTernary(prec),
        .Equality, .Comparison, .Term, .Factor => self.parseBinary(prec),
        .Unary => self.parseUnary(prec),
        .Accessor => self.parseBinary(prec),
        .Call => self.parseCall(),
        .Base => self.parseBase(),

        .None => self.errNode("unexpected expression."),
    };
}

fn statement(self: *Self) ParseError!*Node {
    var node = try self.parsePrec(.Declaration);
    errdefer self.destroyNode(node);

    if (self.current.tokenType != .RightBrace)
        try self.consume(.Semicolon);

    return node;
}

const ExprAllowAssign = enum { AllowAssign, NoAssign };
/// Expression returns a value
fn expression(self: *Self, allow_assign: ExprAllowAssign) ParseError!*Node {
    return self.parsePrec(if (allow_assign == .AllowAssign) .Assignment else .Ternary);
}

fn parseDecl(self: *Self, prec: Precedence) ParseError!*Node {
    var node = try self.parsePrec(prec.next());
    if (node.tag == .Variable) {
        // Essentially the path for every variable at decl level, (ie assign = 2)
        // Parse variable, pass if ^, fail match !, fail match next Identifier, fail match :=, return
        const name = node.as(.Variable).name;
        const is_mut = self.matchAdvance(.Bang);

        const typename = try self.parseTypeOpt();
        errdefer if (typename) |tn| self.destroyNode(tn);

        if (!self.matchAdvance(.ColonEqual)) {
            if (is_mut) try self.err("unexpected '!'.");
            if (typename) |tn| {
                self.destroyNode(tn);
                try self.err("unexpected type.");
            }
            return node;
        }

        // Variable was turned into node, but only need name chars
        self.destroyNode(node);

        const value = try self.expression(.NoAssign);
        errdefer self.destroyNode(value);

        return self.createNode(.VarDefine, .{
            .name = name,
            .type_ = typename,
            .value = value,
            .mut = is_mut,
        });
    }

    return node;
}

fn parseTernary(self: *Self, prec: Precedence) ParseError!*Node {
    const node = try self.parsePrec(prec.next());
    if (self.matchAdvance(.Question)) {
        var first = try self.expression(.NoAssign);
        try self.consume(.Colon);
        var second = try self.expression(.NoAssign);
        return self.createNode(.Ternary, .{
            .cond = node,
            .first = first,
            .second = second,
        });
    }

    return node;
}

fn parseBinary(self: *Self, prec: Precedence) ParseError!*Node {
    var node = try self.parsePrec(prec.next());
    while (Precedence.ofBin(self.next.tokenType).value() >= prec.value()) {
        self.advance();
        const tokenType = self.current.tokenType;
        const next = try self.parsePrec(prec.next());
        node = try self.createNode(.BinaryOp, .{
            .left = node,
            .op = tokenType,
            .right = next,
        });
    }
    return node;
}

fn parseUnary(self: *Self, prec: Precedence) ParseError!*Node {
    var node: ?*Node = null;

    if (self.next.tokenType.isUnary()) {
        self.advance();
        const tokenType = self.current.tokenType;
        const next = try self.parsePrec(prec);
        node = try self.createNode(.UnaryOp, .{ .op = tokenType, .right = next });
    }
    return node orelse self.parsePrec(prec.next());
}

fn parseCall(self: *Self) ParseError!*Node {
    const node = try self.parseBase();
    errdefer self.destroyNode(node);

    if (self.next.tokenType == .LeftParen) {
        var args = try self.parseGroup(.AllowEmpty);
        return self.createNode(.FuncCall, .{ .callee = node, .args = args });
    }

    return node;
}

// ----------------
// Base expressions
// ----------------

fn parseBase(self: *Self) ParseError!*Node {
    self.advance();
    if (self.current.tokenType.isConstant()) {
        return self.createNode(.Literal, .{
            .chars = self.current.chars,
            .typename = self.current.tokenType,
        });
    } else if (self.current.tokenType.isTypeBlock()) {
        return self.parseTypeBlock();
    }

    return switch (self.current.tokenType) {
        .LeftParen => self.parseGroup(.RequireValue),
        .Identifier => self.createNode(.Variable, .{ .name = self.current.chars }),
        .LeftBrace => self.parseBlock(),
        .If => self.parseIf(),
        .While => self.parseWhile(),
        else => self.errNode("expect variable"),
    };
}

fn parseTypeBlock(self: *Self) ParseError!*Node {
    switch (self.current.tokenType) {
        .Fn => {
            try self.consume(.LeftBracket);
            const proto = try self.parseProto();
            try self.consume(.RightBracket);
            const body = if (!self.next.tokenType.isTerminal())
                try self.expression(.AllowAssign) else null;
            return self.createNode(.FnBlock, .{ .proto = proto, .body = body });
        },
        else => unreachable,
    }
}

const ParseTupleAllowEmpty = enum { AllowEmpty, RequireValue };
fn parseGroup(self: *Self, allow_empty: ParseTupleAllowEmpty) ParseError!*Node {
    if (self.matchAdvance(.RightParen)) {
        if (allow_empty == .RequireValue)
            return self.errNode("expect tuple to have atleast one value.");

        return self.createNode(.Tuple, .{});
    }

    const group = try self.expression(.NoAssign);
    errdefer self.destroyNode(group);

    // Generally func calls will allow empty, if one argument, still want a tuple.
    if (self.next.tokenType == .Comma or allow_empty == .AllowEmpty) {
        var node = try self.createNode(.Tuple, .{});
        errdefer self.destroyNode(node);
        var tuple: *Node.Tuple = node.as(.Tuple);
        try self.appendList(&tuple.list, group);

        var infLoop: usize = 0;
        while (self.matchAdvance(.Comma)) {
            try self.appendList(&tuple.list, try self.expression(.NoAssign));

            infLoop += 1;
            assert(infLoop < INF_LOOP);
        }
        try self.consume(.RightParen);
        return node;
    }

    try self.consume(.RightParen);
    return group;
}

fn parseBlock(self: *Self) ParseError!*Node {
    var node = try self.createNode(.Block, .{});
    errdefer self.destroyNode(node);
    var block = node.as(.Block);

    var infLoop: usize = 0;
    while (self.next.tokenType != .RightBrace and self.next.tokenType != .EOF) {
        try self.appendList(&block.list, try self.statement());
        if (self.hasError) self.synchronize();

        infLoop += 1;
        assert(infLoop < INF_LOOP);
    }

    try self.consume(.RightBrace);

    return node;
}

fn parseIf(self: *Self) ParseError!*Node {
    try self.consume(.LeftParen);
    const cond = try self.expression(.NoAssign);
    errdefer self.destroyNode(cond);
    try self.consume(.RightParen);

    const body = try self.expression(.AllowAssign);
    errdefer self.destroyNode(body);

    const chain = try self.parseElifOrElse();
    errdefer if (chain) |c| self.destroyNode(c);

    return self.createNode(.If, .{
        .cond = cond,
        .body = body,
        .elif = chain,
    });
}

fn parseElifOrElse(self: *Self) ParseError!?*Node {
    if (self.matchAdvance(.Elif)) {
        try self.consume(.LeftParen);
        const cond = try self.expression(.NoAssign);
        errdefer self.destroyNode(cond);

        try self.consume(.RightParen);
        const body = try self.expression(.AllowAssign);
        errdefer self.destroyNode(body);

        const inner = try self.parseElifOrElse();
        errdefer if (inner) |i| self.destroyNode(i);

        return self.createNode(.If, .{
            .cond = cond,
            .body = body,
            .elif = inner,
        });
    } else if (self.matchAdvance(.Else)) {
        const body = try self.expression(.AllowAssign);
        errdefer self.destroyNode(body);

        return body;
    }

    return null;
}

fn parseWhile(self: *Self) ParseError!*Node {
    try self.consume(.LeftParen);
    const cond = try self.expression(.NoAssign);
    errdefer self.destroyNode(cond);
    try self.consume(.RightParen);

    const body = try self.expression(.AllowAssign);
    errdefer self.destroyNode(body);

    return self.createNode(.While, .{
        .cond = cond,
        .body = body,
    });
}

// ---------------
// Token consuming
// ---------------

fn advance(self: *Self) void {
    //std.debug.print("Next: {}\n", .{self.next.tokenType});
    self.current = self.next;
    self.next = self.scanner.next();
}

/// If next token is type, advance, return success
fn matchAdvance(self: *Self, expect: TokenType) bool {
    if (self.next.tokenType != expect) return false;
    self.advance();
    return true;
}

/// Expect a specific token, error if not
fn consume(self: *Self, expect: TokenType) ParseError!void {
    if (!self.matchAdvance(expect))
        try self.errFmt("expected token '{}', found '{}'.", .{ expect.toChars(), self.next.tokenType.toChars() });
}

fn ensure(self: *Self, expect: TokenType) ParseError!void {
    if (self.current.tokenType != expect)
        try self.errFmt("expected token '{}', found '{}'.", .{expect.toChars(), self.current.tokenType.toChars()});
}

fn unexpect(self: *Self, unexpected: TokenType) ParseError!void {
    if (self.next.tokenType == unexpected)
        try self.errFmt("unexpected token `{}`", .{unexpected.toChars()});
}

// --------------
// Error handling
// --------------

fn err(self: *Self, msg: []const u8) ParseError!void {
    return self.errFmt("{}", .{msg});
}

fn errFmt(self: *Self, comptime fmt: []const u8, args: anytype) ParseError!void {
    if (self.hasError) return;
    self.hasError = true;

    if (self.parser_error_opt != .ShowErrors) return;

    const bold = ansi.attr(ansi.AT.Bold);
    const redBold = ansi.multi(.{ ansi.red, bold });

    if (self.path) |p| {
        stderr.print(comptime bold("./{}:{}:{}: "), .{ p, self.current.line, self.current.column }) catch return ParseError.StdOutWrite;
    }

    stderr.print(redBold("error: ") ++ bold(fmt) ++ "\n", args) catch return ParseError.StdOutWrite;

    if (self.path != null) {
        stderr.print("{}\n", .{self.current.lineSlice}) catch return ParseError.StdOutWrite;
        var i: usize = 1;
        while (i < self.next.column) : (i += 1)
            stderr.writeAll(" ") catch return ParseError.StdOutWrite;

        stderr.writeAll(ansi.yellow("^") ++ "\n") catch return ParseError.StdOutWrite;
    }
}

fn errNode(self: *Self, msg: []const u8) ParseError!*Node {
    try self.err(msg);
    return self.createNode(.Error, .{ .msg = msg });
}

// Needs some work
fn synchronize(self: *Self) void {
    //if (self.next.tokenType == .Semicolon)
    //   self.advance();
    // while (true) {
    //     if (self.next.tokenType == .EOF) return;
    //     std.debug.print("Sync: {}\n", .{self.next.tokenType});
    //     self.advance();

    //     if (self.current.tokenType == .Semicolon) break;

    //     // if ((self.current.tokenType == .Semicolon or self.next.tokenType == .LeftBrace) and
    //     //     (self.next.tokenType != .Semicolon and self.next.tokenType != .RightBrace))
    //     //     break;
    // }
    // self.hasError = false;
}

// -------------------
// ParseError wrapping
// -------------------s

fn createNode(self: *Self, comptime tag: Node.Tag, init_args: anytype) ParseError!*Node {
    return self.ast.createNode(tag, init_args) catch return ParseError.AstAlloc;
}

fn appendList(self: *Self, list: *Node.List(*Node), node: *Node) ParseError!void {
    list.append(self.ast.allocator, node) catch return ParseError.ArrayListAppend;
}

fn append(self: *Self, comptime T: type, list: *Node.List(T), item: T) ParseError!void {
    list.append(self.ast.allocator, item) catch return ParseError.ArrayListAppend;
}

/// Careful, this will attempt to destroy all children nodes if set
fn destroyNode(self: *Self, node: *Node) void {
    self.ast.destroyNode(node);
}

// -------
// Testing
// -------
