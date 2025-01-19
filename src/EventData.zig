const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn EventData(comptime T: type) type {
    return struct {
        const Self = @This();
        data: *T,
        data_deinit: ?*const fn (*T) void = null,
        callback: *const fn (*Self) anyerror!void,
        allocator: Allocator,

        pub fn init(alloc: Allocator, data: T) !*Self {
            const t = try alloc.create(T);
            errdefer alloc.destroy(t);
            t.* = data;

            const self = try alloc.create(Self);
            const cb = @field(T, "callback");
            self.* = .{ .allocator = alloc, .data = t, .callback = cb };
            if (@hasDecl(T, "deinit")) {
                self.*.data_deinit = @field(T, "deinit");
            }
            return self;
        }

        /// No need to deinit this yourself
        /// When event is unsubscribed, or if event loop is stopped
        /// we call deinit automatically
        pub fn deinit(self: *Self) void {
            if (self.data_deinit != null) {
                self.data_deinit.?(self.data);
            }
            self.allocator.destroy(self);
        }
    };
}
