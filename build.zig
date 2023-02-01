const std = @import("std");
const Sdk = @import("Sdk.zig");

pub fn build(b: *std.build.Builder) !void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();

    // const exe = Sdk.add(b, "demo/types.zig", target, mode);

    var gen_step = Sdk.GenStep.create(b, "demo/types.zig", target, mode);
    // _ = gen_step;
    b.getInstallStep().dependOn(&gen_step.step);

    // const run_cmd = exe.run();
    // run_cmd.step.dependOn(b.getInstallStep());
    // if (b.args) |args| {
    //     run_cmd.addArgs(args);
    // }

    // const real_exe = b.addExecutable("demo", "");

    // const run_step = b.step("run", "Run the app");
    // run_step.dependOn(&run_cmd.step);
}
