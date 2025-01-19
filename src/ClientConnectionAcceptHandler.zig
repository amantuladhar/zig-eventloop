const std = @import("std");
const posix = std.posix;
const EventData = @import("EventData.zig").EventData;
const EchoHandler = @import("EchoHandler.zig");
const EventLoop = @import("EventLoop.zig");
const Allocator = std.mem.Allocator;

allocator: Allocator,
evloop: *const EventLoop,
server: *std.net.Server,

const Self = @This();

pub fn init(alloc: Allocator, evloop: *const EventLoop, server: *std.net.Server) !*Self {
    const self = try alloc.create(Self);
    self.* = .{ .allocator = alloc, .evloop = evloop, .server = server };
    return self;
}

pub fn deinit(self: *Self) void {
    self.allocator.destroy(self);
}

pub fn callback(event_data: *EventData(Self)) anyerror!void {
    const self: *Self = @ptrCast(@alignCast(event_data.data));
    const conn = try self.server.accept();

    // fixme: doesn't free when server itself closes
    // when server closes, we need a way to deallocate this
    // when client disconnects, echo handler is handling deallocation and unsubscribing business
    const edata = try EventData(EchoHandler).init(self.allocator, .{
        .allocator = self.allocator,
        .evloop = self.evloop,
        .conn = conn,
    });
    errdefer edata.deinit();
    try self.evloop.subscribe(conn.stream.handle, .Read, EchoHandler, edata);
}
