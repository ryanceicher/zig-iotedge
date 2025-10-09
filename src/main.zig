const std = @import("std");
const zig_iotedge = @import("zig_iotedge");

const c = zig_iotedge.c;

fn connectionStatusCallback(
    status: c.IOTHUB_CLIENT_CONNECTION_STATUS,
    reason: c.IOTHUB_CLIENT_CONNECTION_STATUS_REASON,
    user_context: ?*anyopaque,
) callconv(.c) void {
    _ = user_context;

    const status_desc = switch (status) {
        c.IOTHUB_CLIENT_CONNECTION_AUTHENTICATED => "authenticated",
        c.IOTHUB_CLIENT_CONNECTION_UNAUTHENTICATED => "unauthenticated",
        else => "unknown",
    };

    const reason_code: u32 = reason;
    std.debug.print("Connection status update: {s} (reason={d})\n", .{ status_desc, reason_code });
}

fn keepAliveLoop() noreturn {
    while (true) {
        zig_iotedge.sleepMilliseconds(1000);
    }
}

pub fn main() !void {
    std.debug.print("Creating Azure IoT Edge module client from environment...\n", .{});

    const client_attempt = zig_iotedge.createModuleClientFromEnvironment();

    if (client_attempt) |client_value| {
        var client = client_value;
        defer client.deinit();

        if (client.setOptionBool(c.OPTION_LOG_TRACE, true)) |_| {} else |err| {
            std.debug.print("Failed to enable log tracing ({s}). Continuing without it.\n", .{@errorName(err)});
        }

        if (client.setOptionBool(c.OPTION_AUTO_URL_ENCODE_DECODE, true)) |_| {} else |err| {
            std.debug.print("Failed to enable auto URL encoding ({s}).\n", .{@errorName(err)});
        }

        const do_work_delay: c.tickcounter_ms_t = 10;
        if (client.setOptionTickcounterMs(c.OPTION_DO_WORK_FREQUENCY_IN_MS, do_work_delay)) |_| {} else |err| {
            std.debug.print("Failed to set DoWork frequency ({s}).\n", .{@errorName(err)});
        }

        if (client.setConnectionStatusCallback(connectionStatusCallback, null)) |_| {} else |err| {
            std.debug.print("Failed to register connection status callback ({s}).\n", .{@errorName(err)});
        }

        std.debug.print("Module client configured. Waiting for work...\n", .{});
        keepAliveLoop();
    } else |err| {
        std.debug.print(
            "Module client creation failed ({s}). Staying alive for baseline observation.\n",
            .{@errorName(err)},
        );
        keepAliveLoop();
    }
}
