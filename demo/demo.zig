const pass = @import("wasm-pass-meta");

pub const Identity = pass.Struct(
    .{
        .creatable = true,
        .snapshotable = true,
    },
    struct {
        id: pass.Field(
            .{
                .set = .no,
            },
            [32]u8,
        ),
        name: pass.Field(
            .{
                .get = .{ .yes = .{
                    .errors = error{ OutOfRange, OutOfMemory },
                } },
                .set = .{ .yes = .{
                    .errors = error{ OutOfRange, NotOwner, NameTooLong },
                } },
            },
            []const u8,
        ),
    },
);
