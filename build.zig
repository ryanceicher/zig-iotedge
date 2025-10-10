const std = @import("std");
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const azure_dep = b.dependency("azure_iot_sdk_c", .{
        .target = target,
        .optimize = optimize,
        .linkage = std.builtin.LinkMode.static,
        .enable_http = true,
        .enable_amqp = false,
        .enable_mqtt = true,
    });
    const azure_module = azure_dep.module("azure_iot_sdk_c");

    const zig_module = b.addModule("zig_iotedge", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "azure_iot_sdk_c", .module = azure_module }},
    });

    const exe_root = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "zig_iotedge", .module = zig_module },
            .{ .name = "azure_iot_sdk_c", .module = azure_module },
        },
    });

    const exe = b.addExecutable(.{
        .name = "zig_iotedge",
        .root_module = exe_root,
    });
    exe.linkLibC();
    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);

    const mod_tests = b.addTest(.{ .root_module = zig_module });
    mod_tests.linkLibC();
    const run_mod_tests = b.addRunArtifact(mod_tests);

    const exe_tests = b.addTest(.{ .root_module = exe_root });
    exe_tests.linkLibC();
    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);
}
