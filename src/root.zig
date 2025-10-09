const std = @import("std");

const azure = @cImport({
    @cInclude("azure_macro_utils/macro_utils.h");
    @cInclude("umock_c/umock_c_prod.h");
    @cInclude("azure_c_shared_utility/platform.h");
    @cInclude("azure_c_shared_utility/threadapi.h");
    @cInclude("azure_c_shared_utility/tickcounter.h");
    @cInclude("azure_c_shared_utility/xlogging.h");
    @cInclude("iothub.h");
    @cInclude("iothub_client_core_ll.h");
    @cInclude("iothub_module_client_ll.h");
    @cInclude("iothubtransportmqtt.h");
    @cInclude("iothub_client_core_common.h");
    @cInclude("iothub_client_options.h");
});

pub const IoTError = error{
    OutOfMemory,
    IoTHubInitFailed,
    CreateClientFailed,
};

pub fn initializeModule(allocator: std.mem.Allocator, connection_string: []const u8) IoTError!void {
    const connection_z = try allocator.dupeZ(u8, connection_string);
    defer allocator.free(connection_z);

    if (azure.IoTHub_Init() != 0) {
        return IoTError.IoTHubInitFailed;
    }
    defer azure.IoTHub_Deinit();

    const transport: azure.IOTHUB_CLIENT_TRANSPORT_PROVIDER = azure.MQTT_Protocol;
    const module_handle = azure.IoTHubModuleClient_LL_CreateFromConnectionString(connection_z.ptr, transport);
    if (module_handle == null) {
        return IoTError.CreateClientFailed;
    }
    defer azure.IoTHubModuleClient_LL_Destroy(module_handle);
    std.debug.print("WE DID THINGS WITHOUT GETTING AN ERROR WHAAAAAAAAAAAAAAAT", .{});
}
