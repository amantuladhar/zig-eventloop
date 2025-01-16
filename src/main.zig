const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const gpa_alloc = gpa.allocator();

    const addr = std.net.Address.initIp4(.{ 0, 0, 0, 0 }, 4200);
    var server = try addr.listen(.{});
    defer server.deinit();

    std.log.info("Server started on :4200", .{});

    var client = try server.accept();
    std.log.info("Client connected!! {any}", .{client.address});
    defer client.stream.close();

    const reader = client.stream.reader();
    const writer = client.stream.writer();
    while (true) {
        const msg = try reader.readUntilDelimiterAlloc(gpa_alloc, '\n', 1024);
        defer gpa_alloc.free(msg);

        const server_msg = try std.fmt.allocPrint(gpa_alloc, "[SERVER]: {s}\n", .{msg});
        defer gpa_alloc.free(server_msg);

        try writer.writeAll(server_msg);
    }
}
