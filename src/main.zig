const std = @import("std");
const zig_iotedge = @import("zig_iotedge");

pub fn main() !void {
    std.debug.print("Creating Azure IoT Edge module client from environment...\n", .{});

    var client = try zig_iotedge.createModuleClientFromEnvironment();
    defer client.deinit();

    std.debug.print("Module client ready. Waiting for work...\n", .{});

    // TODO: Keep process alive once callbacks and work scheduling are in place.
}
