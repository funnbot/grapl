const std = @import("std");
const stdout = std.io.getStdOut().writer();
const stderr = std.io.getStdErr().writer();

const Scanner = @import("Scanner.zig");
const Parser = @import("Parser.zig");

var path: []const u8 = undefined;

const PRINT_SOURCE = false;
const PRINT_SCANNER = false;
const PRINT_AST = true;
const PRINT_AST_TO_SOURCE = false;

const ansi = @import("ansi.zig");

pub fn main() !void {    
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var allocator = &gpa.allocator;
    //var allocator = std.heap.c_allocator;
    defer std.debug.assert(!gpa.deinit());

    var args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len != 2 or args[1].len == 0) {
        return stderr.writeAll("Usage: grapl [file]");
    }

    path = args[1];
    var source = readFile(allocator, path) catch {
        try stderr.print("Failed to open file: \"{}\"", .{path});
        return;
    };
    defer allocator.free(source);

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

    if (PRINT_AST) {
        std.debug.warn("AST: \n", .{});
        var parser = Parser.init(allocator);
        var ast = try parser.parse(source, .ShowErrors, path);
        try ast.print();
        ast.deinit();
    }

    if (PRINT_AST_TO_SOURCE) {
        std.debug.warn("AST to Source: \n", .{});
        var parser = Parser.init(allocator);
        var ast = try parser.parse(source, .SuppressErrors, path);
        try ast.render();
        ast.deinit();
    }
}
