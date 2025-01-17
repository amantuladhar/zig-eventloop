const std = @import("std");
const posix = std.posix;
const EventData = @import("EventData.zig");
const EchoHandler = @import("EchoHandler.zig");

allocator: std.mem.Allocator,
event_fd: i32,
server: *std.net.Server,

const Self = @This();

pub fn accept_tcp_connection(event_data: *EventData) anyerror!void {
    const self: *Self = @ptrCast(@alignCast(event_data.data));

    const conn = try self.server.accept();

    // fixme: doesn't free when server itself closes
    // when server closes, we need a way to deallocate this
    const conn_data = try self.allocator.create(EventData);
    errdefer self.allocator.destroy(conn_data);

    const echo_handler_data = try self.allocator.create(EchoHandler);
    errdefer self.allocator.destroy(echo_handler_data);
    echo_handler_data.* = .{ .conn = conn, .allocator = self.allocator, .event_fd = self.event_fd };

    conn_data.* = .{
        .data = echo_handler_data,
        .callback = EchoHandler.echo,
        .allocator = self.allocator,
    };

    const changelist: []const posix.Kevent = &[_]posix.Kevent{.{
        .ident = @intCast(conn.stream.handle),
        .filter = std.c.EVFILT_READ,
        .flags = std.c.EV_ADD | std.c.EV_ENABLE,
        .fflags = 0,
        .data = 0,
        .udata = @intFromPtr(conn_data),
    }};
    std.log.debug("ADDING::: {any}", .{changelist});
    var events: [0]posix.Kevent = undefined;
    const nev = try posix.kevent(self.event_fd, changelist, &events, null);
    _ = nev;
}
