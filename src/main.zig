const std = @import("std");
const posix = std.posix;
const Allocator = std.mem.Allocator;
const ClientConnAcceptHandler = @import("ClientConnAcceptHandler.zig");
const StdinReaderHandler = @import("StdinReaderHandler.zig");
const EventLoop = @import("EventLoop.zig");
const EventData = @import("EventData.zig").EventData;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var evloop = try EventLoop.init(allocator);
    defer evloop.deinit();

    var server = try startNonblockingServer(4200);

    _ = try setupClientConnAccept(allocator, &evloop, &server);
    _ = try setupStdinReader(allocator, &evloop);

    try evloop.run();
}

fn setupStdinReader(allocator: Allocator, evloop: *EventLoop) !*EventData(StdinReaderHandler) {
    const edata = try EventData(StdinReaderHandler).init(allocator, .{ .allocator = allocator, .evloop = evloop });
    try evloop.subscribe(std.io.getStdIn().handle, .Read, StdinReaderHandler, edata);
    return edata;
}

fn setupClientConnAccept(allocator: Allocator, evloop: *EventLoop, server: *std.net.Server) !*EventData(ClientConnAcceptHandler) {
    const edata = try EventData(ClientConnAcceptHandler).init(allocator, .{ .allocator = allocator, .evloop = evloop, .server = server });
    try evloop.subscribe(server.stream.handle, .Read, ClientConnAcceptHandler, edata);
    return edata;
}

fn startNonblockingServer(port: u16) !std.net.Server {
    const addr = std.net.Address.initIp4(.{ 0, 0, 0, 0 }, port);
    const server = try addr.listen(.{ .reuse_address = true, .reuse_port = true, .force_nonblocking = true });
    std.log.info("server started on :4200", .{});
    return server;
}
