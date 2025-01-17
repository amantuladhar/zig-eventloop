const std = @import("std");

pub const EventCallback = *const fn (*@This()) anyerror!void;

// todo: Can this be comptime?
data: ?*anyopaque,
callback: EventCallback,
allocator: std.mem.Allocator,

pub fn deinit(self: *@This()) void {
    self.allocator.destroy(self);
}
