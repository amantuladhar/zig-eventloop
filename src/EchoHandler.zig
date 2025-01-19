const std = @import("std");
const posix = std.posix;
const Allocator = std.mem.Allocator;
const EventData = @import("EventData.zig").EventData;
const EventLoop = @import("EventLoop.zig");
const Connection = std.net.Server.Connection;

evloop: *EventLoop,
allocator: std.mem.Allocator,
conn: Connection,

const Self = @This();

pub fn init(allocator: Allocator, evloop: *EventLoop, conn: Connection) !*Self {
    const self = try allocator.create(Self);
    self.* = .{ .allocator = allocator, .evloop = evloop, .conn = conn };
    return self;
}

pub fn deinit(self: *Self) void {
    self.conn.stream.close();
    self.allocator.destroy(self);
}

pub fn callback(event_data: *EventData(Self)) anyerror!void {
    // const self: *Self = @ptrCast(@alignCast(event_data.data));
    const self: *Self = event_data.data;

    const reader = self.conn.stream.reader();
    const writer = self.conn.stream.writer();
    std.log.info("Client: {any}, Waiting for user input", .{self.conn.stream.handle});
    std.log.info("Waiting for client message", .{});
    const msg = reader.readUntilDelimiterAlloc(self.allocator, '\n', 1024) catch |err| {
        if (err == error.EndOfStream) {
            std.log.info("Client {d} connection closed", .{self.conn.stream.handle});
            try self.evloop.unsubscribe(self.conn.stream.handle, .Read);
            return;
        }
        return err;
    };
    defer self.allocator.free(msg);

    const server_msg = try std.fmt.allocPrint(self.allocator, "[SERVER]: {s}\n", .{msg});
    defer self.allocator.free(server_msg);

    std.log.info("Client: {any}, Reply to server", .{self.conn.stream.handle});
    try writer.writeAll(server_msg);
    std.log.info("Write finished", .{});
}
