const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

pub fn Stack(comptime T: type) type {
    return struct {
        const Self = @This();
        const GROW_FAC = 2;

        data: []T,

        top: [*]T = undefined,
        items: []T = undefined,

        size: usize = 0,

        allocator: *Allocator,

        pub fn init(allocator: *Allocator) Self {
            var stack = Self{
                .data = &[_]T{},
                .allocator = allocator,
            };
            stack.top = stack.data.ptr;
            stack.items = stack.data[0..0];
            return stack;
        }

        pub fn deinit(self: *Self) void {
            self.allocator.free(self.data);
        }

        pub fn clear(self: *Self) void {
            self.allocator.free(self.data);
            self.data = &[_]T{};
            self.top = self.data.ptr;
            self.items = self.data[0..0];
            self.size = 0;
        }

        pub fn capacity(self: *Self) usize {
            return self.data.len;
        }

        fn calcCapacity(oldCap: usize) usize {
            return if (oldCap >= 8) oldCap * GROW_FAC else 8;
        }

        fn realloc(self: *Self, newCap: usize) !void {
            self.data = try self.allocator.realloc(self.data, newCap);
            self.top = self.data.ptr + self.size;
            self.items.ptr = self.data.ptr;
        }

        pub fn push(self: *Self, val: T) !void {
            if (self.size >= self.data.len)
                try self.realloc(calcCapacity(self.data.len));

            self.top[0] = val;
            self.top += 1;
            self.size += 1;
            self.items.len += 1;
        }

        pub fn pop(self: *Self) !T {
            assert(self.size > 0);

            // Utilization drops below ~25%
            if (self.size < (self.capacity() >> 2)) {
                self.realloc(self.capacity() / 2) catch |err| switch (err) {
                    error.OutOfMemory => {},
                    else => return err,
                };
            }

            self.top -= 1;
            self.size -= 1;
            self.items.len -= 1;
            return self.top[0];
        }

        pub fn peek(self: *Self, dist: usize) T {
            return (self.top - (dist + 1))[0];
        }

        pub fn isEmpty(self: *Self) bool {
            return self.size == 0;
        }
    };
}

test "test stack" {
    var stack = Stack(i32).init(std.testing.allocator);
    defer stack.deinit();

    var i: i32 = 0;
    while (i <= 129) : (i += 1) {
        try stack.push(i);
    }

    for (stack.items) |item_value| assert(item_value >= 0);

    i = 129;
    while (i >= 0) : (i -= 1) {
        assert(stack.peek(0) == i);
        assert((try stack.pop()) == i);
    }

    stack.clear();

    i = 0;
    while (i <= 129) : (i += 1) {
        try stack.push(i);
    }

    for (stack.items) |item_value| assert(item_value >= 0);

    i = 129;
    while (i >= 0) : (i -= 1) {
        assert(stack.peek(0) == i);
        assert((try stack.pop()) == i);
    }
}
