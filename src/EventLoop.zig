const std = @import("std");
const builtin = @import("builtin");
const posix = std.posix;
const EventData = @import("EventData.zig").EventData;

pub const Interest = enum(comptime_int) {
    Read = switch (builtin.os.tag) {
        .macos => std.c.EVFILT_READ,
        .linux => std.os.linux.EPOLL.IN | std.os.linux.EPOLL.ET,
        else => @compileError("Unsupported OS: " ++ @tagName(builtin.os.tag)),
    },
};

eventfd: i32,
registered_fds: std.AutoHashMap(i32, *EventData(anyopaque)),

const Self = @This();

pub fn init(allocator: std.mem.Allocator) !Self {
    return .{
        .eventfd = try createQueue(),
        .registered_fds = std.AutoHashMap(i32, *EventData(anyopaque)).init(allocator),
    };
}

pub fn deinit(self: *Self) void {
    self.registered_fds.deinit();
    posix.close(self.eventfd);
}

pub fn subscribe(self: *Self, fd: i32, interest: Interest, comptime T: type, edata: *EventData(T)) !void {
    try registerEvent(self.eventfd, fd, interest, @intFromPtr(edata));
    _ = try self.registered_fds.put(fd, @ptrCast(edata));

    std.log.debug("registered fds size= {any}", .{self.registered_fds.count()});
    std.log.debug("subscribed -> type={s}, interest={s}, fd={d}", .{ @typeName(T), @tagName(interest), fd });
}

pub fn unsubscribe(self: *Self, fd: i32, interest: Interest) !void {
    try unregisterEvent(self.eventfd, fd, interest);

    var edata = self.registered_fds.fetchRemove(fd);
    edata.?.value.deinit();

    std.log.debug("registered fds size = {any}", .{self.registered_fds.count()});
    std.log.debug("unsubscribed -> interest={s}, fd={d}", .{ @tagName(interest), fd });
}

pub fn run(self: *Self) !void {
    std.log.info("running event loop...", .{});
    var events: [10]Event = undefined;
    main_loop: while (true) {
        const nev = try poll(self.eventfd, &events);
        std.log.info("received {d} events", .{nev});
        for (events[0..nev]) |event| {
            const edata: *EventData(anyopaque) = switch (builtin.os.tag) {
                .macos => @ptrFromInt(event.udata),
                .linux => @ptrFromInt(event.data.ptr),
                else => @compileError("Unsupported OS: " ++ @tagName(builtin.os.tag)),
            };
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

const Event = switch (builtin.os.tag) {
    .macos => posix.Kevent,
    .linux => std.os.linux.epoll_event,
    else => @compileError("Unsupported OS: " ++ @tagName(builtin.os.tag)),
};

fn poll(queuefd: i32, events: []Event) !usize {
    return switch (builtin.os.tag) {
        .macos => try posix.kevent(queuefd, &.{}, events, null),
        .linux => posix.epoll_wait(queuefd, events, -1),
        else => @compileError("Unsupported OS: " ++ @tagName(builtin.os.tag)),
    };
}

fn createQueue() !i32 {
    return switch (builtin.os.tag) {
        .macos => return try posix.kqueue(),
        .linux => return try posix.epoll_create1(0),
        else => @compileError("Unsupported OS: " ++ @tagName(builtin.os.tag)),
    };
}

fn unregisterEvent(queuefd: i32, fd: i32, interest: Interest) !void {
    switch (builtin.os.tag) {
        .macos => {
            const changelist: []const Event = &[_]Event{.{
                .ident = @intCast(fd),
                .filter = @intFromEnum(interest),
                .flags = std.c.EV_DELETE | std.c.EV_DISABLE,
                .fflags = 0,
                .data = 0,
                .udata = 0,
            }};
            var events: [0]Event = undefined;
            _ = try posix.kevent(queuefd, changelist, &events, null);
        },
        .linux => {
            _ = std.os.linux.epoll_ctl(queuefd, std.os.linux.EPOLL.CTL_DEL, @intCast(fd), null);
        },
        else => @compileError("Unsupported OS: " ++ @tagName(builtin.os.tag)),
    }
}

fn registerEvent(eventfd: i32, fd: i32, interest: Interest, data: usize) !void {
    return switch (builtin.os.tag) {
        .macos => {
            const changelist: []const Event = &[_]Event{.{
                .ident = @intCast(fd),
                .filter = @intFromEnum(interest),
                .flags = std.c.EV_ADD | std.c.EV_ENABLE,
                .fflags = 0,
                .data = 0,
                .udata = data,
            }};
            var events: [0]Event = undefined;
            _ = try posix.kevent(eventfd, changelist, &events, null);
        },
        .linux => {
            var event = Event{
                .events = @intFromEnum(interest),
                .data = .{ .ptr = data },
            };
            _ = std.os.linux.epoll_ctl(eventfd, std.os.linux.EPOLL.CTL_ADD, @intCast(fd), &event);
        },
        else => @compileError("Unsupported OS: " ++ @tagName(builtin.os.tag)),
    };
}
