const std = @import("std");

pub fn build(b: *std.build.Builder) !void {
    const target = b.standardTargetOptions(.{});

    const mode = b.standardReleaseOptions();

    const pass_exe = b.addExecutable("bindings", "demo/demo.zig");
    pass_exe.addPackagePath("wasm-pass", "src/main.zig");
    pass_exe.addBuildOption(bool, "bindings", true);
    pass_exe.setTarget(target);
    pass_exe.setBuildMode(mode);
    pass_exe.install();

    const bindings_cmd = pass_exe.run();
    bindings_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        bindings_cmd.addArgs(args);
    }

    const bindings_step = b.step("bindings", "Run demo");
    bindings_step.dependOn(&bindings_cmd.step);

    // wasm
    const demo_exe = b.addSharedLibrary("demo", "demo/demo.zig", .unversioned);
    demo_exe.addPackagePath("wasm-pass", "src/main.zig");
    demo_exe.addBuildOption(bool, "bindings", false);
    demo_exe.setTarget(try std.zig.CrossTarget.parse(.{ .arch_os_abi = "wasm32-freestanding" }));
    demo_exe.setBuildMode(mode);
    demo_exe.install();
}
