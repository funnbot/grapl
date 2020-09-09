const std = @import("std");

const Ast = @import("../Ast.zig");
const Node = Ast.Node;

const Scope = @This();

const Key = []const u8;
const Value = *Node;

pub const Error = error{HashmapPut};

outer: ?*Scope,
decls: std.StringHashMap(*Node),

pub fn init(allocator: *Allocator, outer: ?*Scope) Scope {
    return Scope{
        .outer = outer,
        .decls = std.StringHashMap(*Node).init(allocator),
    };
}

pub inline fn get(self: *const Scope, key: Key) ?Value {
    return self.decls.get(key);
}

pub inline fn put(self: *Scope, key: Key, value: Value) Error!void {
    self.decls.put(key, value) catch return Error.HashmapPut;
}

pub fn putDistinct(self: *Scope, key: Key, value: Value) Error!bool {
    const res = self.decls.getOrPut(key) catch return Error.HashmapPut;
    if (res.found_existing) return false;
    res.entry.value = value;
    return true;
}

pub inline fn hasKey(self: *const Scope, key: Key) bool {
    return self.decls.contains(key);
}

pub fn getInScope(self: *const Scope, key: Key) ?Value {
    var temp: ?*const Scope = self;
    return while (temp) |scope| : (temp = temp.?.outer) {
        if (temp.?.hasKey(key))
            break temp.?.get(key);
    } else null;
}

pub fn inScope(self: *const Scope, key: Key) bool {
    var temp: ?*const Scope = self;
    return while (temp != null) : (temp = temp.?.outer) {
        if (temp.?.hasKey(key)) break true;
    } else false;
}
