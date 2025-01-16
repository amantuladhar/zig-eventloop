const std = @import("std");

const posix = std.posix;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const kq = try posix.kqueue();
    defer posix.close(kq);

    const addr = std.net.Address.initIp4(.{ 0, 0, 0, 0 }, 4200);
    var server = try addr.listen(.{ .reuse_address = true, .reuse_port = true, .force_nonblocking = true });
    defer server.deinit();

    var tcp_conn_acceptor: TcpConnectionAcceptor = .{
        .allocator = allocator,
        .event_fd = kq,
        .server = &server,
    };

    const event_data: EventData = .{
        .data = &tcp_conn_acceptor,
        .callback = TcpConnectionAcceptor.accept_tcp_connection,
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

const EchoHandler = struct {
    event_fd: i32,
    allocator: std.mem.Allocator,
    conn: std.net.Server.Connection,

    const Self = @This();

    fn deinit(self: *Self) void {
        self.conn.stream.close();
        self.allocator.destroy(self);
    }

    fn echo(event_data: *EventData) anyerror!void {
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
};

const EventCallback = *const fn (*EventData) anyerror!void;
const EventData = struct {
    // todo: Can this be comptime?
    data: ?*anyopaque,
    callback: EventCallback,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *@This()) void {
        self.allocator.destroy(self);
    }
};

const TcpConnectionAcceptor = struct {
    allocator: std.mem.Allocator,
    event_fd: i32,
    server: *std.net.Server,

    const Self = @This();

    fn accept_tcp_connection(event_data: *EventData) anyerror!void {
        const self: *Self = @ptrCast(@alignCast(event_data.data));

        const conn = try self.server.accept();

        // fixme: where this should be deallocated?
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
};
