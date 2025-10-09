const std = @import("std");
const fs = std.fs;

const vcpkg_static_libs = [_][]const u8{
    "aziotsharedutil",
    "parson",
    "iothub_client",
    "iothub_client_mqtt_transport",
    "iothub_client_mqtt_ws_transport",
    "umock_c",
    "umqtt",
};

const AzureLibEntry = struct {
    rel_dir: []const u8,
    name: []const u8,
};

const azure_build_static_libs = [_]AzureLibEntry{
    .{ .rel_dir = "c-utility", .name = "aziotsharedutil" },
    .{ .rel_dir = "deps/parson", .name = "parson" },
    .{ .rel_dir = "deps/umock-c", .name = "umock_c" },
    .{ .rel_dir = "deps/uhttp", .name = "uhttp" },
    .{ .rel_dir = "umqtt", .name = "umqtt" },
    .{ .rel_dir = "iothub_client", .name = "iothub_client" },
    .{ .rel_dir = "iothub_client", .name = "iothub_client_mqtt_transport" },
    .{ .rel_dir = "iothub_client", .name = "iothub_client_mqtt_ws_transport" },
    .{ .rel_dir = "provisioning_client", .name = "prov_auth_client" },
    .{ .rel_dir = "provisioning_client", .name = "hsm_security_client" },
};

const system_libs_windows = [_][]const u8{
    "advapi32",
    "bcrypt",
    "crypt32",
    "ncrypt",
    "ole32",
    "oleaut32",
    "schannel",
    "secur32",
    "user32",
    "Rpcrt4",
    "winhttp",
    "ws2_32",
};

const system_libs_linux = [_][]const u8{
    "pthread",
    "m",
    "ssl",
    "crypto",
    "curl",
    "uuid",
    "rt",
    "z",
    "dl",
};

fn detectVcpkgRoot(b: *std.Build) []const u8 {
    if (b.option([]const u8, "vcpkg-root", "Override the vcpkg root path")) |opt| {
        return opt;
    }

    if (std.process.getEnvVarOwned(b.allocator, "VCPKG_ROOT")) |env| {
        return env;
    } else |_| {}

    return "lib/vcpkg_new";
}

fn lazyPath(b: *std.Build, path: []const u8) std.Build.LazyPath {
    if (fs.path.isAbsolute(path)) {
        return .{ .cwd_relative = path };
    }

    return .{ .src_path = .{ .owner = b, .sub_path = path } };
}

const AzureConfig = struct {
    const Kind = enum { azure_build, vcpkg };

    kind: Kind,
    source_root: []const u8,
    include_root: []const u8,
    lib_root: []const u8,
    debug_lib_root: []const u8,
    lib_prefix: []const u8,
    lib_suffix: []const u8,
    system_libs: []const []const u8,

    fn init(b: *std.Build, target: std.Build.ResolvedTarget) AzureConfig {
        const target_os = target.result.os.tag;

        var build_root_opt = b.option([]const u8, "azure-sdk-build-root", "Path to the azure-iot-sdk-c build directory");
        if (build_root_opt == null) {
            if (std.process.getEnvVarOwned(b.allocator, "AZURE_IOT_SDK_BUILD_DIR")) |env| {
                build_root_opt = env;
            } else |_| {}
        }

        const default_build_dir = "build/azure-sdk";
        if (build_root_opt == null) {
            if (std.fs.cwd().openDir(default_build_dir, .{}) catch null) |dir_val| {
                var dir = dir_val;
                defer dir.close();
                build_root_opt = default_build_dir;
            }
        }

        if (build_root_opt) |build_root| {
            var source_root_opt = b.option([]const u8, "azure-sdk-source-root", "Path to the azure-iot-sdk-c source directory");
            if (source_root_opt == null) {
                if (std.process.getEnvVarOwned(b.allocator, "AZURE_IOT_SDK_SOURCE_DIR")) |env| {
                    source_root_opt = env;
                } else |_| {}
            }

            const source_root = source_root_opt orelse "lib/azure-iot-sdk-c";

            const lib_suffix = switch (target_os) {
                .windows => ".lib",
                else => ".a",
            };

            const lib_prefix = switch (target_os) {
                .windows => "",
                else => "lib",
            };

            const system_libs = switch (target_os) {
                .windows => system_libs_windows[0..],
                .linux => system_libs_linux[0..],
                else => @panic("Azure IoT SDK linking is only configured for Windows and Linux targets"),
            };

            return .{
                .kind = .azure_build,
                .source_root = source_root,
                .include_root = source_root,
                .lib_root = build_root,
                .debug_lib_root = build_root,
                .lib_prefix = lib_prefix,
                .lib_suffix = lib_suffix,
                .system_libs = system_libs,
            };
        }

        const triplet = switch (target_os) {
            .linux => "x64-linux",
            .windows => "x64-windows",
            else => @panic("Azure IoT SDK linking is only configured for Windows and Linux targets"),
        };

        const vcpkg_root = detectVcpkgRoot(b);
        const install_root = b.pathJoin(&.{ vcpkg_root, "installed", triplet });

        return .{
            .kind = .vcpkg,
            .source_root = b.pathJoin(&.{ install_root, "include" }),
            .include_root = b.pathJoin(&.{ install_root, "include" }),
            .lib_root = b.pathJoin(&.{ install_root, "lib" }),
            .debug_lib_root = b.pathJoin(&.{ install_root, "debug", "lib" }),
            .lib_prefix = if (target_os == .windows) "" else "lib",
            .lib_suffix = if (target_os == .windows) ".lib" else ".a",
            .system_libs = switch (target_os) {
                .linux => system_libs_linux[0..],
                .windows => system_libs_windows[0..],
                else => unreachable,
            },
        };
    }

    fn addIncludes(self: *const AzureConfig, mod: *std.Build.Module, b: *std.Build) void {
        mod.addIncludePath(lazyPath(b, "src"));

        switch (self.kind) {
            .azure_build => {
                const src = self.source_root;
                const include_dirs = [_][]const u8{
                    src,
                    b.pathJoin(&.{ src, "iothub_client", "inc" }),
                    b.pathJoin(&.{ src, "c-utility", "inc" }),
                    b.pathJoin(&.{ src, "deps", "azure-c-shared-utility", "inc" }),
                    b.pathJoin(&.{ src, "deps", "azure-macro-utils-c", "inc" }),
                    b.pathJoin(&.{ src, "deps", "umock-c", "inc" }),
                    b.pathJoin(&.{ src, "umqtt", "inc" }),
                    b.pathJoin(&.{ src, "deps", "azure-iot-sdk-c-utility", "inc" }),
                    b.pathJoin(&.{ src, "deps", "azure-uamqp-c", "inc" }),
                    b.pathJoin(&.{ src, "deps", "azure-uhttp-c", "inc" }),
                    b.pathJoin(&.{ src, "deps", "azure-c-shared-utility", "inc", "azureiot" }),
                    b.pathJoin(&.{ src, "iothub_client", "inc", "internal" }),
                };

                for (include_dirs) |dir| {
                    mod.addIncludePath(lazyPath(b, dir));
                }
            },
            .vcpkg => {
                mod.addIncludePath(lazyPath(b, self.include_root));
                mod.addIncludePath(lazyPath(b, b.pathJoin(&.{ self.include_root, "azureiot" })));
                mod.addIncludePath(lazyPath(b, b.pathJoin(&.{ self.include_root, "azure_macro_utils" })));
                mod.addIncludePath(lazyPath(b, b.pathJoin(&.{ self.include_root, "umock_c" })));
            },
        }
    }

    fn linkCore(self: *const AzureConfig, step: *std.Build.Step.Compile, b: *std.Build, optimize: std.builtin.OptimizeMode) void {
        switch (self.kind) {
            .azure_build => {
                for (azure_build_static_libs) |lib| {
                    const filename = b.fmt("{s}{s}{s}", .{ self.lib_prefix, lib.name, self.lib_suffix });
                    const lib_path = b.pathJoin(&.{ self.lib_root, lib.rel_dir, filename });
                    step.addObjectFile(lazyPath(b, lib_path));
                }
            },
            .vcpkg => {
                const lib_dir = switch (optimize) {
                    .Debug => self.debug_lib_root,
                    else => self.lib_root,
                };

                for (vcpkg_static_libs) |base| {
                    const filename = b.fmt("{s}{s}{s}", .{ self.lib_prefix, base, self.lib_suffix });
                    const lib_path = b.pathJoin(&.{ lib_dir, filename });
                    step.addObjectFile(lazyPath(b, lib_path));
                }
            },
        }

        for (self.system_libs) |name| {
            step.linkSystemLibrary(name);
        }
    }
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const azure_config = AzureConfig.init(b, target);

    const mod = b.addModule("zig_iotedge", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
    });
    azure_config.addIncludes(mod, b);

    const exe = b.addExecutable(.{
        .name = "zig_iotedge",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "zig_iotedge", .module = mod }},
        }),
    });

    azure_config.addIncludes(exe.root_module, b);
    exe.linkLibC();
    azure_config.linkCore(exe, b, optimize);
    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const mod_tests = b.addTest(.{ .root_module = mod });
    azure_config.linkCore(mod_tests, b, optimize);
    mod_tests.linkLibC();
    const run_mod_tests = b.addRunArtifact(mod_tests);

    const exe_tests = b.addTest(.{ .root_module = exe.root_module });
    azure_config.linkCore(exe_tests, b, optimize);
    exe_tests.linkLibC();
    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);
}
