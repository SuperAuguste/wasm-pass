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

pub const GenStep = struct {
    step: std.build.Step,
    builder: *std.build.Builder,
    source: std.build.FileSource,

    output_file: std.build.GeneratedFile,

    pub fn create(
        builder: *std.build.Builder,
        file: []const u8,
        target: std.zig.CrossTarget,
        build_mode: std.builtin.Mode,
    ) *GenStep {
        return createSource(builder, .{ .path = file }, target, build_mode);
    }

    pub fn createSource(
        builder: *std.build.Builder,
        source: std.build.FileSource,
        target: std.zig.CrossTarget,
        build_mode: std.builtin.Mode,
    ) *GenStep {
        const self = builder.allocator.create(GenStep) catch unreachable;
        self.* = GenStep{
            .step = std.build.Step.init(.custom, "build-template", builder.allocator, make),
            .builder = builder,
            .source = source,

            .output_file = std.build.GeneratedFile{ .step = &self.step },
        };
        source.addStepDependencies(&self.step);

        const exe = self.builder.addExecutable("wasm-pass-gen", "src/gen.zig");
        exe.setTarget(target);
        exe.setBuildMode(build_mode);
        exe.addPackage(.{
            .name = "@defs@",
            .source = .{ .path = self.source.getPath(self.builder) },
            .dependencies = &.{
                .{
                    .name = "wasm-pass-meta",
                    .source = .{ .path = "src/meta.zig" },
                    .dependencies = &.{},
                },
            },
        });

        var run_cmd = exe.run();
        run_cmd.step.dependOn(&exe.step);
        run_cmd.addArgs(&.{ "zig", "bruh.zig" });

        self.step.dependOn(&run_cmd.step);

        return self;
    }

    // pub fn transform(builder: *std.build.Builder, file: []const u8) std.build.FileSource {
    //     const step = create(builder, file);
    //     return step.getFileSource();
    // }

    // pub fn transformSource(builder: *std.build.Builder, source: std.build.FileSource) std.build.FileSource {
    //     const step = createSource(builder, source);
    //     return step.getFileSource();
    // }

    /// Returns the file source
    pub fn getFileSource(self: *const GenStep) std.build.FileSource {
        return std.build.FileSource{ .generated = &self.output_file };
    }

    fn make(step: *std.build.Step) !void {
        _ = step;
        std.debug.print("\n\nbruh!!\n\n", .{});
        // const self = @fieldParentPtr(GenStep, "step", step);

        // const source_file_name = self.source.getPath(self.builder);

        // const basename = std.fs.path.basename(source_file_name);

        // const output_name = blk: {
        //     if (std.mem.indexOf(u8, basename, ".")) |index| {
        //         break :blk try std.mem.join(self.builder.allocator, ".", &[_][]const u8{
        //             basename[0..index],
        //             "zig",
        //         });
        //     } else {
        //         break :blk try std.mem.join(self.builder.allocator, ".", &[_][]const u8{
        //             basename,
        //             "zig",
        //         });
        //     }
        // };
    }
};
