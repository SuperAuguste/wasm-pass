const std = @import("std");

pub fn add(
    b: *std.build.Builder,
    src: []const u8,
    target: std.zig.CrossTarget,
    build_mode: std.builtin.Mode,
) *std.build.LibExeObjStep {
    const exe = b.addExecutable("wasm-pass-gen", "src/gen.zig");
    exe.addPackage(.{
        .name = "@defs@",
        .source = .{ .path = src },
        .dependencies = &.{
            .{
                .name = "wasm-pass-meta",
                .source = .{ .path = "src/meta.zig" },
                .dependencies = &.{},
            },
        },
    });
    exe.setTarget(target);
    exe.setBuildMode(build_mode);
    exe.install();

    return exe;
}
