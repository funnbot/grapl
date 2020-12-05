const std = @import("std");
const meta = std.meta;
const TypeInfo = std.builtin.TypeInfo;

pub fn GenTagType(comptime Base: type, comptime Namespace: type, comptime buffer_max: usize) type {
    return struct {
        const Self = @This();
        TagType: type = undefined,
        count: usize = 0,
        enumFieldBuffer: [buffer_max]TypeInfo.EnumField = [_]TypeInfo.EnumField{.{ .name = "", .value = 0 }} ** buffer_max,
        typeMapBuffer: [buffer_max]type = [_]type{void} ** buffer_max,

        pub fn init() Self {
            var self = Self{};
            inline for (meta.declarations(Namespace)) |decl| {
                if (self.count == buffer_max) @compileError("Field buffer max reached.");

                const enumField = TypeInfo.EnumField{
                    .name = decl.name,
                    .value = self.count,
                };

                self.enumFieldBuffer[self.count] = enumField;
                self.typeMapBuffer[self.count] = decl.data.Type;
                self.count += 1;
            }
            self.TagType = @Type(TypeInfo{
                .Enum = .{
                    .layout = .Auto,
                    .tag_type = meta.Int(.unsigned, std.math.ceil(std.math.log2(@intToFloat(f32, self.count)))),
                    .fields = self.enumFieldBuffer[0..self.count],
                    .decls = &[_]TypeInfo.Declaration{},
                    .is_exhaustive = true,
                },
            });
            return self;
        }

        pub fn Type(comptime self: *const Self, comptime tag: self.TagType) type {
            return self.typeMapBuffer[@enumToInt(tag)];
        }
    };
}