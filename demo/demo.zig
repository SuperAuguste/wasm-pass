const std = @import("std");
const pass = @import("wasm-pass");

export fn init() void {
    var iden = pass.Identity.create();

    var name = iden.get_name(std.heap.page_allocator) catch unreachable;
    logThis(@intCast(i32, @ptrToInt(name.ptr)), @intCast(i32, name.len));
}

extern fn logThis(ptr: i32, len: i32) void;
