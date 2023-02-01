const std = @import("std");
const pass = @import("wasm-pass");

export fn init() void {
    // var iden = pass.Identity.create();

    // var name = iden.get_name(std.heap.page_allocator) catch unreachable;
    pass.console_log("Bruh");
}
