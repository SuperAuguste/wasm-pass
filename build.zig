const std = @import("std");
const Sdk = @import("Sdk.zig");

pub fn build(b: *std.build.Builder) !void {
    const mode = b.standardReleaseOptions();

    // const exe = Sdk.add(b, "demo/types.zig", target, mode);

    var gen_step = try Sdk.GenStep.create(b, "demo/types.zig", b.standardTargetOptions(.{}), mode);

    const lib = b.addSharedLibrary("demo", "demo/demo.zig", .unversioned);
    lib.addPackage(.{
        .name = "wasm-pass",
        .source = .{ .generated = &gen_step.zig_output_file },
    });
    lib.import_memory = true;
    lib.rdynamic = true;
    lib.setTarget(try std.zig.CrossTarget.parse(.{ .arch_os_abi = "wasm32-freestanding" }));
    lib.setBuildMode(mode);
    lib.install();

    lib.step.dependOn(&gen_step.step);
    b.getInstallStep().dependOn(&lib.step);
}
