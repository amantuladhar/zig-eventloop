const std = @import("std");
const posix = std.posix;
const Allocator = std.mem.Allocator;
const EventData = @import("EventData.zig").EventData;
const EventLoop = @import("EventLoop.zig");
const Self = @This();

allocator: Allocator,
evloop: *EventLoop,

pub fn init(allocator: Allocator, evloop: *EventLoop) !*Self {
    const self = try allocator.create(Self);
    self.* = .{ .allocator = allocator, .evloop = evloop };
    return self;
}
pub fn deinit(self: *Self) void {
    self.allocator.destroy(self);
}

pub fn callback(edata: *EventData(Self)) anyerror!void {
    const self: *Self = @ptrCast(@alignCast(edata.data));
    const stdin = std.io.getStdIn();
    var buf: [10]u8 = undefined;
    const read_count = try stdin.reader().read(&buf);
    if (!std.mem.eql(u8, "exit", buf[0 .. read_count - 1])) {
        return;
    }
    try self.evloop.unsubscribe(stdin.handle, .Read);
    return error.StopServer;
}
