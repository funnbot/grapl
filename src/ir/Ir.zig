const std = @import("std");
const TypeInfo = std.builtin.TypeInfo;

const Ir = @This();

pub const Tag = enum {
    VarDefine,


    pub fn Type(comptime self: Tag) type {
        inline for (meta.declarations(Ir)) |decl| {
            // All node structs will be:
            // public, of type Struct, have a base field of Node
            if (decl.is_pub and
                @as(@TagType(TypeInfo.Declaration.Data), decl.data) == .Type and
                @hasField(decl.data.Type, "base") and
                decl.name.len == @tagName(self).len and
                std.mem.eql(u8, decl.name, @tagName(self)))
                return decl.data.Type;
        }
        @compileLog("unmatched type tag", self);
    }
};

tag: Tag,

pub fn create(allocator: *Allocator, comptime tag: Tag, init_args: anytype) !*Ir {
    var ir = try allocator.create(tag.Type());
    ir.* = init_args;
    ir.base = Ir{ .tag = tag };
    return &ir.base;
}

pub fn as(self: *Ir, comptime tag: Tag) *(tag.Type()) {
    assert(self.tag == tag);
    return self.asType(tag.Type());
}

pub fn asType(self: *Ir, comptime T: type) *T {
    return @fieldParentPtr(T, "base", self);
}

pub fn is(self: *Ir, comptime tag: Tag) bool {
    return self.tag == tag;
}

pub const VarDefine {

};