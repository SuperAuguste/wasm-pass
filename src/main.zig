const std = @import("std");

const Parser = @import("meta/Parser.zig");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    var file_data = try std.fs.cwd().readFileAllocOptions(allocator, "demo/types.pass", std.math.maxInt(usize), null, @alignOf(u8), 0);
    defer allocator.free(file_data);

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    std.debug.print("{any}", .{try Parser.parse(arena.allocator(), file_data)});
}
