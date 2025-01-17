const std = @import("std");
const posix = std.posix;
const ClientConnectionAcceptHandler = @import("ClientConnectionAcceptHandler.zig");
const EventData = @import("EventData.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const kq = try posix.kqueue();
    defer posix.close(kq);

    const addr = std.net.Address.initIp4(.{ 0, 0, 0, 0 }, 4200);
    var server = try addr.listen(.{ .reuse_address = true, .reuse_port = true, .force_nonblocking = true });
    defer server.deinit();

    var tcp_conn_acceptor: ClientConnectionAcceptHandler = .{
        .allocator = allocator,
        .event_fd = kq,
        .server = &server,
    };

    const event_data: EventData = .{
        .data = &tcp_conn_acceptor,
        .callback = ClientConnectionAcceptHandler.accept_tcp_connection,
        .allocator = allocator,
    };
    const stdin = std.io.getStdIn();
    std.log.debug("STDIN Handle == {d}", .{stdin.handle});

    const changelist: []const posix.Kevent = &[_]posix.Kevent{ .{
        .ident = @intCast(server.stream.handle),
        .filter = std.c.EVFILT_READ,
        .flags = std.c.EV_ADD | std.c.EV_ENABLE,
        .fflags = 0,
        .data = 0,
        .udata = @intFromPtr(&event_data),
    }, .{
        .ident = @intCast(stdin.handle),
        .filter = std.c.EVFILT_READ,
        .flags = std.c.EV_ADD | std.c.EV_ENABLE,
        .fflags = 0,
        .data = 0,
        .udata = 0,
    } };
    var events: [1]posix.Kevent = undefined;

    std.log.info("Server started on :4200", .{});
    main_loop: {
        while (true) {
            const nev = try posix.kevent(kq, changelist, &events, null);
            std.log.info("Number of event received: {d}", .{nev});
            std.log.debug("RECV::: {any}", .{events});
            for (events[0..nev]) |event| {
                if (event.ident == stdin.handle) {
                    var buf: [10]u8 = undefined;
                    const read_count = stdin.reader().read(&buf) catch continue;
                    std.log.debug("readcount = {d}, value = \"{any}\"", .{ read_count, buf });
                    if (std.mem.eql(u8, "exit", buf[0 .. read_count - 1])) {
                        std.log.debug("Breaking main loop", .{});
                        const stdin_clist: []const posix.Kevent = &[_]posix.Kevent{.{
                            .ident = @intCast(stdin.handle),
                            .filter = std.c.EVFILT_READ,
                            .flags = std.c.EV_DELETE | std.c.EV_DISABLE,
                            .fflags = 0,
                            .data = 0,
                            .udata = 0,
                        }};
                        var empty_ev: [0]posix.Kevent = undefined;
                        _ = try posix.kevent(kq, stdin_clist, &empty_ev, null);
                        break :main_loop;
                    }
                    continue;
                }
                const r_event_data: *EventData = @ptrFromInt(event.udata);
                r_event_data.callback(r_event_data) catch |e| {
                    std.log.err("Something went wrong when calling event callback: {any}", .{e});
                };
            }
        }
    }
}
