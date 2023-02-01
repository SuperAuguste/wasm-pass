const std = @import("std");
const defs = @import("@defs@");

const GenZig = @import("gen/GenZig.zig");
const GenTs = @import("gen/GenTs.zig");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    var arena = std.heap.ArenaAllocator.init(allocator);

    var args = try std.process.argsAlloc(arena.allocator());

    if (args.len != 2) {
        std.debug.print(
            \\ts or zig
        , .{});
        return;
    }

    if (std.mem.eql(u8, args[1], "ts")) {
        try GenTs.generate(arena.allocator(), defs, std.io.getStdOut().writer());
    } else if (std.mem.eql(u8, args[1], "zig")) {
        try GenZig.generate(arena.allocator(), defs, std.io.getStdOut().writer());
    }
}
