const std = @import("std");
const zig_iotedge = @import("zig_iotedge");

const Options = struct {
    option1: bool = false,
    option2: []const u8 = "",
    option3: i32 = 0,
};

fn logOptions(prefix: []const u8, payload: []const u8) void {
    var parsed = zig_iotedge.parseJson(Options, payload) catch |err| {
        std.debug.print("{s}: failed to parse options ({s})\n", .{ prefix, @errorName(err) });
        return;
    };
    defer parsed.deinit();
    const opts = parsed.value;
    std.debug.print("{s}: Option1={any}, Option2=\"{s}\", Option3={d}\n", .{ prefix, opts.option1, opts.option2, opts.option3 });
}

fn twinHandlerEx(client: *zig_iotedge.ModuleClient, kind: zig_iotedge.TwinUpdateKind, bytes: []const u8) void {
    const prefix = switch (kind) {
        .complete => "Twin snapshot",
        .partial => "Twin update",
    };
    logOptions(prefix, bytes);

    // Try to extract desired.$version if present for ack
    const DesiredEnvelope = struct {
        properties: ?struct { desired: ?struct { @"$version": ?i64 = null } = null } = null,
        desired: ?struct { @"$version": ?i64 = null } = null,
    };
    var parsed = zig_iotedge.parseJson(DesiredEnvelope, bytes) catch {
        return;
    };
    defer parsed.deinit();

    var version_opt: ?i64 = null;
    if (parsed.value.properties) |p| {
        if (p.desired) |d| version_opt = d.@"$version";
    }
    if (version_opt == null) {
        if (parsed.value.desired) |d2| version_opt = d2.@"$version";
    }
    if (version_opt) |ver| {
        // Compose a minimal reported state ack
        var buf: [128]u8 = undefined;
        const ts_ms: u64 = @intCast(std.time.milliTimestamp());
        const json = std.fmt.bufPrint(&buf, "{{\"lastAckVersion\":{d},\"ackTimestampMs\":{d}}}", .{ ver, ts_ms }) catch return;
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
