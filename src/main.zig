const std = @import("std");

const Parser = @import("meta/Parser.zig");
const GenZig = @import("gen/GenZig.zig");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    var file_data = try std.fs.cwd().readFileAllocOptions(allocator, "demo/types.pass", std.math.maxInt(usize), null, @alignOf(u8), 0);
    defer allocator.free(file_data);

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    try GenZig.generate(arena.allocator(), try Parser.parse(arena.allocator(), file_data), std.io.getStdOut().writer());
}
