const std = @import("std");

const azure = @cImport({
    @cDefine("USE_EDGE_MODULES", "1");
    @cInclude("azure_macro_utils/macro_utils.h");
    @cInclude("umock_c/umock_c_prod.h");
    @cInclude("azure_c_shared_utility/platform.h");
    @cInclude("azure_c_shared_utility/threadapi.h");
    @cInclude("azure_c_shared_utility/tickcounter.h");
    @cInclude("azure_c_shared_utility/xlogging.h");
    @cInclude("iothub.h");
    @cInclude("iothub_module_client.h");
    @cInclude("iothubtransportmqtt.h");
    @cInclude("iothub_client_options.h");
});

// Internal C bindings are intentionally not re-exported. Consumers should use
// the Zig-first API below so they don't deal with C strings/pointers.

pub const IoTError = error{
    OutOfMemory,
    IoTHubInitFailed,
    CreateClientFailed,
    SetOptionFailed,
    SetConnectionStatusCallbackFailed,
    SetTwinCallbackFailed,
    GetTwinAsyncFailed,
    SendReportedStateFailed,
};

// Zig-first enums and callback signatures
pub const ConnectionStatus = enum {
    authenticated,
    unauthenticated,
    unknown,
};

pub const TwinUpdateKind = enum {
    complete, // full twin snapshot
    partial, // desired-properties patch
};

pub const ConnectionStatusFn = *const fn (status: ConnectionStatus, reason_code: u32) void;
pub const TwinFn = *const fn (kind: TwinUpdateKind, payload: []const u8) void;
pub const TwinFnEx = *const fn (client: *ModuleClient, kind: TwinUpdateKind, payload: []const u8) void;

pub const ModuleClient = struct {
    handle: azure.IOTHUB_MODULE_CLIENT_HANDLE,
    // Stored Zig callbacks (optional)
    connection_cb: ?ConnectionStatusFn = null,
    twin_cb: ?TwinFn = null,
    twin_cb_ex: ?TwinFnEx = null,

    pub fn deinit(self: *ModuleClient) void {
        azure.IoTHubModuleClient_Destroy(self.handle);
        azure.IoTHub_Deinit();
    }

    // --- Options (Zig-first wrappers) ---
    pub fn enableLogTrace(self: *ModuleClient, enable: bool) IoTError!void {
        var value: u8 = if (enable) 1 else 0;
        if (azure.IoTHubModuleClient_SetOption(self.handle, azure.OPTION_LOG_TRACE, &value) != azure.IOTHUB_CLIENT_OK) {
            return IoTError.SetOptionFailed;
        }
    }

    pub fn setAutoUrlEncodeDecode(self: *ModuleClient, enable: bool) IoTError!void {
        var value: u8 = if (enable) 1 else 0;
        if (azure.IoTHubModuleClient_SetOption(self.handle, azure.OPTION_AUTO_URL_ENCODE_DECODE, &value) != azure.IOTHUB_CLIENT_OK) {
            return IoTError.SetOptionFailed;
        }
    }

    pub fn setDoWorkFrequencyMs(self: *ModuleClient, ms: u32) IoTError!void {
        var temp: azure.tickcounter_ms_t = @intCast(ms);
        if (azure.IoTHubModuleClient_SetOption(self.handle, azure.OPTION_DO_WORK_FREQUENCY_IN_MS, &temp) != azure.IOTHUB_CLIENT_OK) {
            return IoTError.SetOptionFailed;
        }
    }

    // --- Connection status callback (Zig-first) ---
    pub fn onConnectionStatus(self: *ModuleClient, cb: ConnectionStatusFn) IoTError!void {
        self.connection_cb = cb;
        if (azure.IoTHubModuleClient_SetConnectionStatusCallback(self.handle, connStatusTrampoline, self) != azure.IOTHUB_CLIENT_OK) {
            return IoTError.SetConnectionStatusCallbackFailed;
        }
    }

    // Trampoline from C callback to Zig callback
    fn connStatusTrampoline(
        status: azure.IOTHUB_CLIENT_CONNECTION_STATUS,
        reason: azure.IOTHUB_CLIENT_CONNECTION_STATUS_REASON,
        user_context: ?*anyopaque,
    ) callconv(.c) void {
        if (user_context) |ctx| {
            const self: *ModuleClient = @ptrCast(@alignCast(ctx));
            if (self.connection_cb) |cb| {
                const s: ConnectionStatus = switch (status) {
                    azure.IOTHUB_CLIENT_CONNECTION_AUTHENTICATED => .authenticated,
                    azure.IOTHUB_CLIENT_CONNECTION_UNAUTHENTICATED => .unauthenticated,
                    else => .unknown,
                };
                const code: u32 = @intCast(reason);
                cb(s, code);
            }
        }
    }

    // --- Twin callbacks (Zig-first) ---
    pub fn onTwin(self: *ModuleClient, cb: TwinFn) IoTError!void {
        self.twin_cb = cb;
        if (azure.IoTHubModuleClient_SetModuleTwinCallback(self.handle, twinTrampoline, self) != azure.IOTHUB_CLIENT_OK) {
            return IoTError.SetTwinCallbackFailed;
        }
    }

    pub fn onTwinEx(self: *ModuleClient, cb: TwinFnEx) IoTError!void {
        self.twin_cb_ex = cb;
        if (azure.IoTHubModuleClient_SetModuleTwinCallback(self.handle, twinTrampoline, self) != azure.IOTHUB_CLIENT_OK) {
            return IoTError.SetTwinCallbackFailed;
        }
    }

    pub fn requestTwinSnapshot(self: *ModuleClient) IoTError!void {
        if (azure.IoTHubModuleClient_GetTwinAsync(self.handle, twinTrampoline, self) != azure.IOTHUB_CLIENT_OK) {
            return IoTError.GetTwinAsyncFailed;
        }
    }

    fn twinTrampoline(
        update_state: azure.DEVICE_TWIN_UPDATE_STATE,
        payload: [*c]const u8,
        size: usize,
        user_context: ?*anyopaque,
    ) callconv(.c) void {
        if (user_context) |ctx| {
            const self: *ModuleClient = @ptrCast(@alignCast(ctx));
            if (size == 0) return;
            const kind: TwinUpdateKind = switch (update_state) {
                azure.DEVICE_TWIN_UPDATE_COMPLETE => .complete,
                azure.DEVICE_TWIN_UPDATE_PARTIAL => .partial,
                else => .partial,
            };
            const slice = @as([*]const u8, @ptrCast(payload))[0..size];
            if (self.twin_cb_ex) |cb_ex| {
                cb_ex(self, kind, slice);
                return;
            }
            if (self.twin_cb) |cb| cb(kind, slice);
        }
    }

    // --- Reported state (Zig-first) ---
    const ReportedStateBox = struct {
        cb: *const fn (status_code: u32) void,
    };

    pub fn sendReportedState(self: *ModuleClient, json: []const u8, cb: ?*const fn (status_code: u32) void) IoTError!void {
        var ctx_ptr: ?*anyopaque = null;
        // Match the C callback signature locally as a function pointer type
        const ReportedStateC = *const fn (c_int, ?*anyopaque) callconv(.c) void;
        var c_cb: ?ReportedStateC = null;
        if (cb) |user_cb| {
            // Allocate a tiny box to hold the Zig callback and free it after invocation
            const box = std.heap.c_allocator.create(ReportedStateBox) catch return IoTError.OutOfMemory;
            box.cb = user_cb;
            ctx_ptr = box;
            c_cb = reportedStateTrampoline;
        }
        if (azure.IoTHubModuleClient_SendReportedState(self.handle, json.ptr, json.len, c_cb, ctx_ptr) != azure.IOTHUB_CLIENT_OK) {
            if (ctx_ptr) |p| {
                const box_ptr: *ReportedStateBox = @ptrCast(@alignCast(p));
                std.heap.c_allocator.destroy(box_ptr);
            }
            return IoTError.SendReportedStateFailed;
        }
    }

    fn reportedStateTrampoline(status_code: c_int, user_context: ?*anyopaque) callconv(.c) void {
        if (user_context) |ctx| {
            const box: *ReportedStateBox = @ptrCast(@alignCast(ctx));
            const code: u32 = @intCast(status_code);
            box.cb(code);
            std.heap.c_allocator.destroy(box);
        }
    }
};

pub fn createModuleClientFromEnvironment() IoTError!ModuleClient {
    if (azure.IoTHub_Init() != 0) {
        return IoTError.IoTHubInitFailed;
    }

    const transport: azure.IOTHUB_CLIENT_TRANSPORT_PROVIDER = azure.MQTT_Protocol;
    const handle = azure.IoTHubModuleClient_CreateFromEnvironment(transport);
    if (handle == null) {
        azure.IoTHub_Deinit();
        return IoTError.CreateClientFailed;
    }

    return ModuleClient{ .handle = handle.? };
}

pub fn sleepMilliseconds(duration_ms: u32) void {
    _ = azure.ThreadAPI_Sleep(duration_ms);
}

/// Parse JSON from a C pointer + size into a caller-specified type T using std.json.parseFromSlice.
/// Returns a struct containing the parsed value and an arena deinit function to free allocations.
pub fn parseJsonFromCPayload(comptime T: type, c_ptr: [*c]const u8, size: usize) !struct {
    value: T,
    arena: std.heap.ArenaAllocator,
    pub fn deinit(self: *@This()) void {
        self.arena.deinit();
    }
} {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const alloc = arena.allocator();
    const slice = @as([*]const u8, @ptrCast(c_ptr))[0..size];
    const parsed = try std.json.parseFromSlice(T, alloc, slice, .{});
    return .{ .value = parsed.value, .arena = arena };
}

/// Parse JSON directly from a Zig slice (preferred for consumers)
pub fn parseJson(comptime T: type, bytes: []const u8) !struct {
    value: T,
    arena: std.heap.ArenaAllocator,
    pub fn deinit(self: *@This()) void {
        self.arena.deinit();
    }
} {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const alloc = arena.allocator();
    const parsed = try std.json.parseFromSlice(T, alloc, bytes, .{});
    return .{ .value = parsed.value, .arena = arena };
}
