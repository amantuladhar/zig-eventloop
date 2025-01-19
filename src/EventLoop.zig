const std = @import("std");
const posix = std.posix;
const EventData = @import("EventData.zig").EventData;

pub const Interest = enum(comptime_int) { Read = std.c.EVFILT_READ };

eventfd: i32,
registered_fds: std.AutoHashMap(i32, *EventData(anyopaque)),

const Self = @This();

pub fn init(allocator: std.mem.Allocator) !Self {
    return .{
        .eventfd = try posix.kqueue(),
        .registered_fds = std.AutoHashMap(i32, *EventData(anyopaque)).init(allocator),
    };
}

pub fn deinit(self: *Self) void {
    self.registered_fds.deinit();
    posix.close(self.eventfd);
}

pub fn subscribe(self: *Self, fd: i32, interest: Interest, comptime T: type, edata: *EventData(T)) !void {
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
    _ = try self.registered_fds.put(fd, @ptrCast(edata));
    std.log.debug("registered fds size= {any}", .{self.registered_fds.count()});
    std.log.debug("subscribed -> type={s}, interest={s}, fd={d}", .{ @typeName(T), @tagName(interest), fd });
}

pub fn unsubscribe(self: *Self, fd: i32, interest: Interest) !void {
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

    var edata = self.registered_fds.fetchRemove(fd);
    edata.?.value.deinit();

    std.log.debug("registered fds size = {any}", .{self.registered_fds.count()});
    std.log.debug("unsubscribed -> interest={s}, fd={d}", .{ @tagName(interest), fd });
}

pub fn run(self: *Self) !void {
    std.log.info("running event loop...", .{});
    var events: [10]posix.Kevent = undefined;
    main_loop: while (true) {
        const nev = try posix.kevent(self.eventfd, &.{}, &events, null);
        std.log.info("received {d} events", .{nev});
        for (events[0..nev]) |event| {
            const edata: *EventData(anyopaque) = @ptrFromInt(event.udata);
            edata.callback(edata) catch |e| {
                // fixme: maybe error is not right way to solve this?
                // should we always return a typed result from callback instead of void?
                if (e == error.StopServer) {
                    std.log.info("bummmmmerrrrr... I was just ordered to kill myself :(", .{});
                    break :main_loop;
                }
                std.log.err("error occurred while processing event. Err = {any}", .{e});
            };
        }
    }
    // Making sure we close all existing file descriptor and cleaning up the resources
    var it = self.registered_fds.iterator();
    while (it.next()) |entry| {
        std.log.info("closing fd {d}", .{entry.key_ptr.*});
        entry.value_ptr.*.deinit();
    }
}
