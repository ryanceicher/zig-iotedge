const std = @import("std");
const zig_iotedge = @import("zig_iotedge");
const nats = @import("nats");

// TODO we need to remove option1,2,3 and replace it with parameters for connecting to our nats server
const TwinEnvelope = struct {
    desired: struct {
        @"$version": i64 = 0,
        // TODO REPLACE THESE OPTIONS
        option1: bool = false,
        option2: []const u8 = "",
        option3: i32 = 0,
    } = .{},
    reported: struct {
        @"$version": i64 = 0,
    } = .{},
};

pub fn main() !void {
    // TODO we need to check for IOTEDGE environment variables, if they arent present then
    // we should run without any of the iotedge related stuff and expect a json config file with how we need to connect to our nats server

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const env = try std.process.getEnvMap(arena.allocator());

    var iterator = env.iterator();

    while (iterator.next()) |next| {
        std.debug.print("Env Variables", .{});
        std.debug.print("   {s}:{s}", .{ &next.key_ptr, &next.value_ptr });
    }

    std.debug.print("Creating Azure IoT Edge module client from environment...\n", .{});

    const client_attempt = try zig_iotedge.createModuleClientFromEnvironment();

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

        if (client.onTwinEx(&twinHandlerEx)) |_| {} else |err| {
            std.debug.print("Failed to set twin callback ({s}).\n", .{@errorName(err)});
        }

        if (client.requestTwinSnapshot()) |_| {} else |err| {
            std.debug.print("Failed to get twin snapshot ({s}).\n", .{@errorName(err)});
        }

        std.debug.print("Module client configured. Waiting for work...\n", .{});
        keepAliveLoop();
    }
}

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

fn keepAliveLoop() void {
    while (true) {
        // Create a NATS jetstream connection
        const connectionOptions = nats.ConnectionOptions.create() catch {
            return;
        };
        const connection = nats.Connection.connect(connectionOptions) catch {
            return;
        };
        defer connection.close();
        defer connection.destroy();

        var userdataPtr = false;
        _ = connection.subscribe(*bool, "shit", callback, &userdataPtr) catch {
            return;
        };

        zig_iotedge.sleepMilliseconds(1000);
    }
}

fn callback(_: *bool, _: *nats.Connection, _: *nats.Subscription, msg: *nats.Message) void {
    const subject = msg.getSubject();
    const data = msg.getData() orelse "";
    std.debug.print("Received a message on subject {s}: {s}\n", .{ subject, data });
}
