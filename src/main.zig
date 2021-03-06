const std = @import("std");
const stdout = std.io.getStdOut().writer();
const stderr = std.io.getStdErr().writer();

const Scanner = @import("Scanner.zig");
const Parser = @import("Parser.zig");

var path: []const u8 = undefined;

const PRINT_SOURCE = false;
const PRINT_SCANNER = false;
const PRINT_AST = true;
const PRINT_AST_TO_SOURCE = true;

const ansi = @import("ansi.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .stack_trace_frames = 8 }){};
    var allocator = &gpa.allocator;
    //var allocator = std.heap.c_allocator;
    defer std.debug.assert(!gpa.deinit());

    var args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len != 2 or args[1].len == 0) {
        return stderr.writeAll("Usage: grapl [file]\n");
    }

    path = args[1];
    var source = readFile(allocator, path) catch {
        try stderr.print("Failed to open file: \"{}\"\n", .{path});
        return;
    };
    defer allocator.free(source);

    if (source.len == 0) {
        try stderr.print("Empty source file: \"{}\"\n", .{path});
        return;
    }

    try runFile(allocator, source);
}

const FileOpenError = error{FileOpenError};
fn readFile(allocator: *std.mem.Allocator, file: []const u8) FileOpenError![]const u8 {
    return std.fs.cwd().readFileAlloc(allocator, file, 1_000_000_000) catch return error.FileOpenError;
}

fn runFile(allocator: *std.mem.Allocator, source: []const u8) !void {
    if (PRINT_SOURCE) {
        std.debug.warn("Original Source: \n{}\n", .{source});
    }

    if (PRINT_SCANNER) {
        std.debug.warn("Tokens: \n", .{});
        var scanner = Scanner.init(source);
        var token = scanner.next();
        while (token.tokenType != .EOF) : (token = scanner.next())
            std.debug.warn("{}\n", .{token});
    }

    var parser = Parser.init(allocator);
    var ast = try parser.parse(source, .ShowErrors, path);
    if (PRINT_AST) {
        std.debug.print("AST: \n", .{});
        try ast.print();
    }
    if (PRINT_AST_TO_SOURCE) {
        std.debug.print("AST to Source: \n", .{});
        try ast.render();
    }
    try ast.typeResolve();
    ast.deinit();
}
