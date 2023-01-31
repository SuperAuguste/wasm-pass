const pass = @import("wasm-pass-meta");

pub const Identity = pass.Struct(struct {
    id: pass.Field([32]u8, .{
        .set = .no,
    }),
    name: pass.Field([]const u8, .{
        .get = .{ .yes = .{
            .errors = error{ OutOfRange, OutOfMemory },
        } },
        .set = .{ .yes = .{
            .errors = error{ OutOfRange, NotOwner, NameTooLong },
        } },
    }),
}, .{
    .creatable = true,
    .snapshotable = true,
});
