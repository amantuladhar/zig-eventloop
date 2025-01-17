const std = @import("std");
const posix = std.posix;
const ClientConnectionAcceptHandler = @import("ClientConnectionAcceptHandler.zig");
const StdinReader = @import("StdinReader.zig");
const EventLoop = @import("EventLoop.zig");
const EventData = @import("EventData.zig").EventData;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const evloop = try EventLoop.init();
    defer evloop.deinit();

    const addr = std.net.Address.initIp4(.{ 0, 0, 0, 0 }, 4200);
    var server = try addr.listen(.{ .reuse_address = true, .reuse_port = true, .force_nonblocking = true });
    defer server.deinit();
    std.log.info("Server started on :4200", .{});

    var event_data = try EventData(ClientConnectionAcceptHandler).init(allocator, .{ .allocator = allocator, .evloop = &evloop, .server = &server });
    defer event_data.deinit();
    try evloop.subscribe(server.stream.handle, .Read, ClientConnectionAcceptHandler, event_data);

    var stdin_edata = try EventData(StdinReader).init(allocator, .{ .allocator = allocator, .evloop = &evloop });
    defer stdin_edata.deinit();
    try evloop.subscribe(std.io.getStdIn().handle, .Read, StdinReader, stdin_edata);

    var events: [10]posix.Kevent = undefined;
    std.log.info("Server started on :4200", .{});
    main_loop: while (true) {
        const nev = try posix.kevent(evloop.eventfd, &.{}, &events, null);
        std.log.info("Number of event received: {d}", .{nev});
        for (events[0..nev]) |event| {
            const r_event_data: *EventData(anyopaque) = @ptrFromInt(event.udata);
            r_event_data.callback(r_event_data) catch |e| {
                if (e == error.StopServer) {
                    std.log.err("STOP SERVER received", .{});
                    break :main_loop;
                }
                std.log.err("Something went wrong when calling event callback: {any}", .{e});
            };
        }
    }
}
