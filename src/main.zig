const std = @import("std");
const posix = std.posix;
const Allocator = std.mem.Allocator;
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

    var server = try startNonblockingServer(4200);

    var client_connect_edata = try subscribeToServerSocketRead(allocator, &evloop, &server);
    defer client_connect_edata.deinit();
    var stdin_edata = try subscribeToStdinRead(allocator, &evloop);
    defer stdin_edata.deinit();

    try evloop.run();
}

fn subscribeToStdinRead(allocator: Allocator, evloop: *const EventLoop) !*EventData(StdinReader) {
    const edata = try EventData(StdinReader).init(allocator, .{ .allocator = allocator, .evloop = evloop });
    try evloop.subscribe(std.io.getStdIn().handle, .Read, StdinReader, edata);
    return edata;
}

fn subscribeToServerSocketRead(allocator: Allocator, evloop: *const EventLoop, server: *std.net.Server) !*EventData(ClientConnectionAcceptHandler) {
    const edata = try EventData(ClientConnectionAcceptHandler).init(allocator, .{ .allocator = allocator, .evloop = evloop, .server = server });
    try evloop.subscribe(server.stream.handle, .Read, ClientConnectionAcceptHandler, edata);
    return edata;
}

fn startNonblockingServer(port: u16) !std.net.Server {
    const addr = std.net.Address.initIp4(.{ 0, 0, 0, 0 }, port);
    const server = try addr.listen(.{ .reuse_address = true, .reuse_port = true, .force_nonblocking = true });
    std.log.info("server started on :4200", .{});
    return server;
}
