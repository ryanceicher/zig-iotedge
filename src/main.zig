const std = @import("std");
const zig_iotedge = @import("zig_iotedge");

const TwinEnvelope = struct {
    desired: struct {
        @"$version": i64 = 0,
        option1: bool = false,
        option2: []const u8 = "",
        option3: i32 = 0,
    } = .{},
    reported: struct {
        @"$version": i64 = 0,
    } = .{},
};

fn twinHandlerEx(client: *zig_iotedge.ModuleClient, kind: zig_iotedge.TwinUpdateKind, bytes: []const u8) void {
    const prefix = switch (kind) {
        .complete => "Twin snapshot",
        .partial => "Twin update",
    };
    var parsed = zig_iotedge.parseJson(TwinEnvelope, bytes) catch |err| {
        std.debug.print("{s}: raw twin payload = {s}\n", .{ prefix, bytes });
        std.debug.print("{s}: failed to parse twin payload ({s})\n", .{ prefix, @errorName(err) });
        return;
    };
    defer parsed.deinit();

    const envelope = parsed.value;
    const desired = envelope.desired;
    std.debug.print(
        "{s}: Option1={any}, Option2=\"{s}\", Option3={d} (desired.$version={d})\n",
        .{ prefix, desired.option1, desired.option2, desired.option3, desired.@"$version" },
    );

    const version = desired.@"$version";
    if (version > 0) {
        // Compose a minimal reported state ack
        var buf: [128]u8 = undefined;
        const ts_ms: u64 = @intCast(std.time.milliTimestamp());
        const json = std.fmt.bufPrint(&buf, "{{\"lastAckVersion\":{d},\"ackTimestampMs\":{d}}}", .{ version, ts_ms }) catch return;
        _ = client.sendReportedState(json, null) catch |err| {
            std.debug.print("Failed to send reported state ack ({s}).\n", .{@errorName(err)});
            return;
        };
    }
}

fn connectionStatusHandler(status: zig_iotedge.ConnectionStatus, reason_code: u32) void {
    const desc = switch (status) {
        .authenticated => "authenticated",
        .unauthenticated => "unauthenticated",
        .unknown => "unknown",
    };
    std.debug.print("Connection status update: {s} (reason={d})\n", .{ desc, reason_code });
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

        if (client.enableLogTrace(true)) |_| {} else |err| {
            std.debug.print("Failed to enable log tracing ({s}). Continuing without it.\n", .{@errorName(err)});
        }

        if (client.setAutoUrlEncodeDecode(true)) |_| {} else |err| {
            std.debug.print("Failed to enable auto URL encoding ({s}).\n", .{@errorName(err)});
        }

        if (client.setDoWorkFrequencyMs(10)) |_| {} else |err| {
            std.debug.print("Failed to set DoWork frequency ({s}).\n", .{@errorName(err)});
        }

        if (client.onConnectionStatus(&connectionStatusHandler)) |_| {} else |err| {
            std.debug.print("Failed to register connection status callback ({s}).\n", .{@errorName(err)});
        }

        // Register for desired property updates and request the full twin snapshot
        if (client.onTwinEx(&twinHandlerEx)) |_| {} else |err| {
            std.debug.print("Failed to set twin callback ({s}).\n", .{@errorName(err)});
        }

        if (client.requestTwinSnapshot()) |_| {} else |err| {
            std.debug.print("Failed to get twin snapshot ({s}).\n", .{@errorName(err)});
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
