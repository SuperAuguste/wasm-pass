//! wasm-pass source!
// TODO: Remove pesky anyerrors, blocked by https://github.com/ziglang/zig/issues/5149

const std = @import("std");

const AutoIndentingStream = @import("auto_indenting_stream.zig").AutoIndentingStream;
const js = @import("javascript.zig");

const pre = @embedFile("pre.js");
const post = @embedFile("post.js");

pub fn bind(namespace: anytype, writer: std.fs.File.Writer) anyerror!void {
    var bindgen = js.BindingGenerator.init(writer);

    try writer.writeAll(pre);

    try bindgen.generate(namespace);

    try writer.print("module.exports = {s};\n", .{@typeName(namespace)});
    try writer.writeAll(post);
}

pub fn wasmExports(namespace: anytype) type {
    return struct {
        const N = namespace;
        const allocator: *std.mem.Allocator = std.heap.page_allocator;

        pub export fn allocBytes(len: i32) i32 {
            return @intCast(i32, @ptrToInt((allocator.alloc(u8, @intCast(usize, len)) catch unreachable).ptr));
        }

        pub export fn freeBytes(ptr: i32, len: i32) void {
            allocator.free(@intToPtr([*]u8, @intCast(usize, ptr))[0..@intCast(usize, len)]);
        }
    };
}
