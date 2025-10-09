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

pub const c = azure;

pub const IoTError = error{
    OutOfMemory,
    IoTHubInitFailed,
    CreateClientFailed,
    SetOptionFailed,
    SetConnectionStatusCallbackFailed,
};

pub const ConnectionStatusCallback = fn (
    status: azure.IOTHUB_CLIENT_CONNECTION_STATUS,
    reason: azure.IOTHUB_CLIENT_CONNECTION_STATUS_REASON,
    user_context: ?*anyopaque,
) callconv(.c) void;

pub const ModuleClient = struct {
    handle: azure.IOTHUB_MODULE_CLIENT_HANDLE,

    pub fn deinit(self: *ModuleClient) void {
        azure.IoTHubModuleClient_Destroy(self.handle);
        azure.IoTHub_Deinit();
    }

    pub fn setOptionBool(self: *ModuleClient, option_name: [*c]const u8, enable: bool) IoTError!void {
        var value: u8 = if (enable) 1 else 0;
        if (azure.IoTHubModuleClient_SetOption(self.handle, option_name, &value) != azure.IOTHUB_CLIENT_OK) {
            return IoTError.SetOptionFailed;
        }
    }

    pub fn setOptionTickcounterMs(self: *ModuleClient, option_name: [*c]const u8, value: azure.tickcounter_ms_t) IoTError!void {
        var temp = value;
        if (azure.IoTHubModuleClient_SetOption(self.handle, option_name, &temp) != azure.IOTHUB_CLIENT_OK) {
            return IoTError.SetOptionFailed;
        }
    }

    pub fn setConnectionStatusCallback(
        self: *ModuleClient,
        callback: ConnectionStatusCallback,
        user_context: ?*anyopaque,
    ) IoTError!void {
        if (azure.IoTHubModuleClient_SetConnectionStatusCallback(self.handle, callback, user_context) != azure.IOTHUB_CLIENT_OK) {
            return IoTError.SetConnectionStatusCallbackFailed;
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
