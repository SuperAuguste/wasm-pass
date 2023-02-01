const std = @import("std");
const defs = @import("@defs@");

const GenZig = @import("gen/GenZig.zig");
const GenTs = @import("gen/GenTs.zig");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    var arena = std.heap.ArenaAllocator.init(allocator);

    var args = try std.process.argsAlloc(arena.allocator());

    if (args.len < 2) {
        std.debug.print(
            \\ts or zig
        , .{});
        return;
    }

    // "gen ts cache-path/index.ts zig cache-path/index.zig"

    const Kind = enum { ts, zig };

    var index: usize = 1;
    while (index < args.len) : (index += 2) {
        const kind = std.meta.stringToEnum(Kind, args[index]) orelse @panic("Invalid arguments");
        const path = args[index + 1];

        var file = try std.fs.cwd().createFile(path, .{});
        defer file.close();

        switch (kind) {
            .ts => try GenTs.generate(arena.allocator(), defs, file.writer()),
            .zig => try GenZig.generate(arena.allocator(), defs, file.writer()),
        }
    }
}
