const std = @import("std");
const wasm_pass = @import("wasm-pass");
const build_options = @import("build_options");

pub const demo_import = @import("demo_import.zig");

pub const MyEnum = enum(u8) {
    joe,
    mama,
    other,

    pub const ZABCD = 12;
};

pub const MyStruct = struct {
    a: u8,
    b: u32,
    c: bool,
    d: MyEnum,
    e: demo_import.MyOtherStruct,

    pub const ZABC = 12;
    pub const who_is_the_coolest: []const u8 = "matt!";
};

const Bindings = switch (std.builtin.target.cpu.arch) {
    .wasm32, .wasm64 => struct {
        extern "fun" fn decodeStruct(ptr: i32) void;
        extern "fun" fn decodeStruct2(ptr: i32) void;
    },
    else => struct {
        fn decodeStruct(ptr: i32) void {
            _ = ptr;
        }

        fn decodeStruct2(ptr: i32) void {
            _ = ptr;
        }
    },
};

usingnamespace if (build_options.bindings) struct {} else wasm_pass.wasmExports(@This());

pub fn main() anyerror!void {
    if (build_options.bindings) {
        var file = try std.fs.cwd().createFile("demo/bindings.js", .{});
        defer file.close();

        try wasm_pass.bind(@This(), file.writer());
        return;
    } else unreachable;
}

export fn joe() void {
    var t = MyStruct{
        .a = 69,
        .b = 56789,
        .c = false,
        .d = .other,
        .e = .{ .abc = 123 },
    };
    Bindings.decodeStruct(@intCast(i32, @ptrToInt(&t)));
    Bindings.decodeStruct2(@intCast(i32, @ptrToInt(&t)));
}
