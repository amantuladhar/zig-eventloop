const std = @import("std");
const posix = std.posix;
const EventData = @import("EventData.zig").EventData;

pub const Interest = enum(comptime_int) { Read = std.c.EVFILT_READ };

eventfd: i32,

const Self = @This();

pub fn init() !Self {
    return .{ .eventfd = try posix.kqueue() };
}

pub fn deinit(self: *const Self) void {
    posix.close(self.eventfd);
}

pub fn subscribe(self: *const Self, fd: i32, interest: Interest, comptime T: type, edata: *EventData(T)) !void {
    const changelist: []const posix.Kevent = &[_]posix.Kevent{.{
        .ident = @intCast(fd),
        .filter = @intFromEnum(interest),
        .flags = std.c.EV_ADD | std.c.EV_ENABLE,
        .fflags = 0,
        .data = 0,
        .udata = @intFromPtr(edata),
    }};
    var events: [0]posix.Kevent = undefined;
    _ = try posix.kevent(self.eventfd, changelist, &events, null);
    std.log.debug("Finished subscribe::: fd {d}", .{fd});
}

pub fn unsubscribe(self: *const Self, fd: i32, interest: Interest) !void {
    const changelist: []const posix.Kevent = &[_]posix.Kevent{.{
        .ident = @intCast(fd),
        .filter = @intFromEnum(interest),
        .flags = std.c.EV_DELETE | std.c.EV_DISABLE,
        .fflags = 0,
        .data = 0,
        .udata = 0,
    }};
    var events: [0]posix.Kevent = undefined;
    _ = try posix.kevent(self.eventfd, changelist, &events, null);
    std.log.debug("Finished unsubscribe::: fd {d}", .{fd});
}
