const std = @import("std");
const pass = @import("wasm-pass");

pub fn main() void {
    std.log.info("{any}", .{pass});
}
