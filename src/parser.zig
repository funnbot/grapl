const std = @import("std");
const stdout = std.io.getStdOut().writer();
const stderr = std.io.getStdErr().writer();
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const warn = std.debug.warn;
const ansi = @import("ansi.zig");

const Ast = @import("Ast.zig");
const Node = Ast.TreeNode;

const Stack = @import("stack.zig").Stack;

const Scanner = @import("Scanner.zig");
const TokenType = Scanner.TokenType;
const Token = Scanner.Token;

const Self = @This();

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

pub fn deinit(self: *Self) void {}

pub const ParserErrorOption = enum { ShowErrors, SuppressErrors };
/// Caller owns ast, use ast.destroy()
pub fn parse(self: *Self, source: []const u8, parser_error_opt: ParserErrorOption, path: ?[]const u8) ParseError!Ast {
    self.path = path;
    self.scanner = Scanner.init(source);

    self.ast = Ast.init(self.allocator);
    errdefer self.ast.destroy();

    self.hasError = false;
    self.parser_error_opt = parser_error_opt;

    self.advance();

    while (self.next.tokenType != TokenType.EOF) {
        try self.appendList(&self.ast.stmts, try self.statement());
        if (self.hasError) self.synchronize();
    }

    if (1 == 2) {
        self.advance();
    }

    return self.ast;
}

/// Statement does not return a value
fn statement(self: *Self) ParseError!*Node {
    var node: *Node = undefined;
    errdefer self.destroyNode(node);

    if (self.matchAdvance(.Bang)) {
        try self.consume(.Identifier, "expect mutable variable name.");
        node = try self.varDefineStmt(.Mutable);
    } else if (self.matchAdvance(.Identifier)) {
        node = try self.varDefineStmt(.Constant);
    } else {
        node = try self.expression();
    }

    if (self.current.tokenType != .RightBrace)
        try self.consume(.Semicolon, "expect ';' to terminate statement.");

    return node;
}

const VarDefineStmtMutability = enum { Mutable, Constant };
fn varDefineStmt(self: *Self, mut: VarDefineStmtMutability) ParseError!*Node {
    const name = self.current.chars;
    const typename = try self.parseTypeOpt();
    try self.consume(.Equal, "expect variable assignment.");
    const expr = try self.expression();

    return self.createNode(Node.VarDefineNode.init(name, typename, expr, mut == .Mutable));
}

// -----------
// Type parser
// -----------

fn parseTypeOpt(self: *Self) ParseError!?*Node {
    return if (self.next.tokenType == .Identifier or self.next.tokenType == .LeftParen)
        self.parseType()
    else
        null;
}

fn parseType(self: *Self) ParseError!*Node {
    if (self.next.tokenType == .LeftParen) {
        return self.parseTupleType();
    }

    try self.consume(.Identifier, "expect typename.");
    const typename = self.current.chars;
    const typeNode = try self.createNode(Node.TypeNode.init(typename));

    if (self.next.tokenType == .LeftParen) {
        const args = try self.parseTuple(.AllowEmpty, "macro arguments");
        return self.createNode(Node.FuncCallNode.init(typeNode, args));
    }
    return typeNode;
}

fn parseTupleType(self: *Self) ParseError!*Node {
    try self.consume(.LeftParen, "expect '(' to begin tuple type.");

    if (self.next.tokenType == .RightParen)
        return self.errNode("expect atleast two types within tuple type, found none.");

    const first = try self.parseType();

    if (self.next.tokenType == .RightParen)
        return self.errNode("expect atleast two types within tuple type, found one.");

    var tupleNode = try self.createNode(Node.TupleNode.init(self.ast.allocator));
    try self.appendList(&tupleNode.Tuple.list, first);

    while (self.matchAdvance(.Comma)) {
        // Calling into expression parser for arbitrarily complex macro calls, scary
        const next = try self.parseType();
        try self.appendList(&tupleNode.Tuple.list, next);
    }

    try self.consume(.RightParen, "expect ')' to terminate tuple type.");

    return tupleNode;
}

// -----------------
// Expression parser
// -----------------

/// Higher precedence value gets evaluated first
const Precedence = enum {
    None,
    Assignment,
    ControlFlow,
    Ternary,
    Equality,
    Comparison,
    Term,
    Factor,
    Unary,
    Accessor,
    Call,
    Variable,

    pub fn next(self: Precedence) Precedence {
        return @intToEnum(Precedence, self.value() + 1);
    }
    pub fn value(self: Precedence) @TagType(Precedence) {
        return @enumToInt(self);
    }
    /// Precedence of binary operator
    pub fn ofBin(tokenType: TokenType) Precedence {
        return switch (tokenType) {
            .EqualEqual, .BangEqual => .Equality,
            .Less, .LessEqual, .Greater, .GreaterEqual => .Comparison,
            .Plus, .Minus => .Term,
            .Star, .Slash => .Factor,
            .Dot => .Accessor,
            else => .None,
        };
    }
};

/// Expression returns a value
fn expression(self: *Self) ParseError!*Node {
    return self.parsePrec(.Assignment);
}

fn parsePrec(self: *Self, prec: Precedence) ParseError!*Node {
    return switch (prec) {
        .Assignment => self.parsePrec(prec.next()),
        .ControlFlow => self.parseFlow(prec),
        .Ternary => self.parseTernary(prec),
        .Equality, .Comparison, .Term, .Factor => self.parseBinary(prec),
        .Unary => self.parseUnary(prec),
        .Accessor => self.parseBinary(prec),
        .Call => self.parseCall(),
        .Variable => self.parseVariable(),

        .None => self.errNode("expect expression."),
    };
}

fn parseElifAndElse(self: *Self) ParseError!?*Node {
    if (self.matchAdvance(.Elif)) {
        try self.consume(.LeftParen, "expect '(' before elif condition.");
        const cond = try self.expression();
        errdefer self.destroyNode(cond);

        try self.consume(.RightParen, "expect ')' after elif condition");
        const body = try self.expression();
        errdefer self.destroyNode(body);

        const inner = try self.parseElifAndElse();
        errdefer if (inner) |i| self.destroyNode(i);

        return self.createNode(Node.IfNode.init(cond, body, inner));
    } else if (self.matchAdvance(.Else)) {
        const body = try self.expression();
        errdefer self.destroyNode(body);

        return body;
    }

    return null;
}

fn parseFlow(self: *Self, prec: Precedence) ParseError!*Node {
    if (self.matchAdvance(.Elif))
        return self.errNode("floating elif statement.")
    else if (self.matchAdvance(.Else))
        return self.errNode("floating else statement.");

    if (self.matchAdvance(.If)) {
        try self.consume(.LeftParen, "expect '(' before if condition.");
        const cond = try self.expression();
        errdefer self.destroyNode(cond);
        try self.consume(.RightParen, "expect ')' to terminate condition.");

        const body = try self.expression();
        errdefer self.destroyNode(body);

        const chain = try self.parseElifAndElse();
        errdefer if (chain) |c| self.destroyNode(c);

        return try self.createNode(Node.IfNode.init(cond, body, chain));
    }
    return self.parsePrec(prec.next());
}

fn parseTernary(self: *Self, prec: Precedence) ParseError!*Node {
    const node = try self.parsePrec(prec.next());
    if (self.matchAdvance(.Question)) {
        var first = try self.expression();
        try self.consume(.Colon, "expect ':' for ternary else.");
        var second = try self.expression();
        return self.createNode(Node.TernaryNode.init(node, first, second));
    }

    return node;
}

fn parseBinary(self: *Self, prec: Precedence) ParseError!*Node {
    var node = try self.parsePrec(prec.next());
    while (Precedence.ofBin(self.next.tokenType).value() >= prec.value()) {
        self.advance();
        const tokenType = self.current.tokenType;
        const next = try self.parsePrec(prec.next());
        node = try self.createNode(Node.BinaryOpNode.init(node, tokenType, next));
    }
    return node;
}

fn parseUnary(self: *Self, prec: Precedence) ParseError!*Node {
    // // Is this really better than recursive?
    var node: ?*Node = null;
    // var innerPtr: *?*Node = undefined;

    // while (self.next.tokenType.isUnary()) {
    //     self.advance();
    //     const tokenType = self.current.tokenType;

    // }

    // return node orelse self.parsePrec(prec.next());

    if (self.next.tokenType.isUnary()) {
        self.advance();
        const tokenType = self.current.tokenType;
        const next = try self.parsePrec(prec);
        node = try self.createNode(Node.UnaryOpNode.init(tokenType, next));
    }
    return node orelse self.parsePrec(prec.next());
}

fn parseCall(self: *Self) ParseError!*Node {
    const node = try self.parseVariable();
    errdefer self.destroyNode(node);

    if (self.next.tokenType == .LeftParen) {
        var args = try self.parseTuple(.AllowEmpty, "arguments");
        return self.createNode(Node.FuncCallNode.init(node, args));
    }

    return node;
}

// TODO: rename something other can variable, what is the base term in an expression, includes variables groupings tuples?
fn parseVariable(self: *Self) ParseError!*Node {
    if (self.next.tokenType.isConstant()) {
        self.advance();
        return self.createNode(Node.ConstantNode.init(self.current.chars, self.current.tokenType));
    } else if (self.next.tokenType == .LeftParen) {
        return self.parseTuple(.RequireValue, "grouping or tuple");
    } else if (self.matchAdvance(.Identifier)) {
        var ident = self.current.chars;
        return self.createNode(Node.VariableNode.init(ident));
    } else if (self.next.tokenType == .LeftBrace) {
        return self.parseBlock();
    }

    return self.errNode("expect variable.");
}

const ParseTupleAllowEmpty = enum { AllowEmpty, RequireValue };
fn parseTuple(self: *Self, allow_empty: ParseTupleAllowEmpty, comptime tupleName: []const u8) ParseError!*Node {
    assert(self.next.tokenType == .LeftParen);
    self.advance();

    if (self.matchAdvance(.RightParen)) {
        if (allow_empty == .RequireValue)
            return self.errNode("expect " ++ tupleName ++ " to have atleast one value.");

        return self.createNode(Node.TupleNode.init(self.ast.allocator));
    }

    const group = try self.expression();
    errdefer self.destroyNode(group);

    if (self.next.tokenType == .Comma) {
        var tuple = try self.createNode(Node.TupleNode.init(self.ast.allocator));
        errdefer self.destroyNode(tuple);

        try self.appendList(&tuple.Tuple.list, group);

        while (self.matchAdvance(.Comma))
            try self.appendList(&tuple.Tuple.list, try self.expression());

        try self.consume(.RightParen, "expect ')' to terminate " ++ tupleName ++ ".");
        return tuple;
    }

    try self.consume(.RightParen, "expect ')' to terminate " ++ tupleName ++ ".");
    return group;
}

fn parseBlock(self: *Self) ParseError!*Node {
    try self.consume(.LeftBrace, "expect '{' to begin block.");
    var block = try self.createNode(Node.BlockNode.init(self.ast.allocator));
    errdefer self.destroyNode(block);

    while (self.next.tokenType != .RightBrace) {
        try self.appendList(&block.Block.list, try self.statement());
        if (self.hasError) self.synchronize();
    }

    try self.consume(.RightBrace, "expect '}' to terminate block.");

    return block;
}

// ---------------
// Token consuming
// ---------------

fn advance(self: *Self) void {
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
fn consume(self: *Self, expect: TokenType, msg: []const u8) ParseError!void {
    if (!self.matchAdvance(expect))
        try self.errFmt("expected token '{}', found '{}'.", .{expect.toChars(), self.next.tokenType.toChars()});
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
        while (i < self.current.column) : (i += 1)
            stderr.writeAll(" ") catch return ParseError.StdOutWrite;

        stderr.writeAll(ansi.yellow("^") ++ "\n") catch return ParseError.StdOutWrite;
    }
}

fn errNode(self: *Self, msg: []const u8) ParseError!*Node {
    try self.err(msg);
    return self.createNode(Node.ErrorNode.init(msg));
}

fn synchronize(self: *Self) void {
    while (true) {
        if (self.next.tokenType == .EOF) return;
        // current, to consume the semicolon aswell

        self.advance();

        if ((self.current.tokenType == .Semicolon or self.next.tokenType == .LeftBrace) and
            (self.next.tokenType != .Semicolon and self.next.tokenType != .RightBrace))
            break;
    }
    self.hasError = false;
}

// -------------------
// ParseError wrapping
// -------------------s

fn createNode(self: *Self, node: Node) ParseError!*Node {
    return self.ast.createNode(node) catch return ParseError.AstAlloc;
}

fn appendList(self: *Self, list: *Node.ListNode, node: *Node) ParseError!void {
    list.append(node) catch return ParseError.ArrayListAppend;
}

/// Careful, this will attempt to destroy all children nodes if set
fn destroyNode(self: *Self, node: *Node) void {
    node.destroy(self.ast.allocator);
}

// -------
// Testing
// -------