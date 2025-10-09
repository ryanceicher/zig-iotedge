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

pub const IoTError = error{
    OutOfMemory,
    IoTHubInitFailed,
    CreateClientFailed,
};

pub const ModuleClient = struct {
    handle: azure.IOTHUB_MODULE_CLIENT_HANDLE,

    pub fn deinit(self: *ModuleClient) void {
        azure.IoTHubModuleClient_Destroy(self.handle);
        azure.IoTHub_Deinit();
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
