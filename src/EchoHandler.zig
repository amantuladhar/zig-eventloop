const std = @import("std");
const posix = std.posix;
const EventData = @import("EventData.zig");

event_fd: i32,
allocator: std.mem.Allocator,
conn: std.net.Server.Connection,

const Self = @This();

fn deinit(self: *Self) void {
    self.conn.stream.close();
    self.allocator.destroy(self);
}

pub fn echo(event_data: *EventData) anyerror!void {
    const self: *Self = @ptrCast(@alignCast(event_data.data));

    const reader = self.conn.stream.reader();
    const writer = self.conn.stream.writer();
    std.log.info("Client: {any}, Waiting for user input", .{self.conn.stream.handle});
    std.log.info("Waiting for client message", .{});
    const msg = reader.readUntilDelimiterAlloc(self.allocator, '\n', 1024) catch |err| {
        if (err == error.EndOfStream) {
            defer {
                self.deinit();
                event_data.deinit();
            }
            const changelist: []const posix.Kevent = &[_]posix.Kevent{.{
                .ident = @intCast(self.conn.stream.handle),
                .filter = std.c.EVFILT_READ,
                .flags = std.c.EV_DELETE | std.c.EV_DISABLE,
                .fflags = 0,
                .data = 0,
                .udata = 0,
            }};
            var events: [1]posix.Kevent = undefined;
            const nev = try posix.kevent(self.event_fd, changelist, &events, null);
            _ = nev;
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
