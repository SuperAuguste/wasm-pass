const std = @import("std");
const defs = @import("@defs@");

const GenZig = @import("gen/GenZig.zig");

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    try GenZig.generate(allocator, defs, std.io.getStdOut().writer());
}
