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

pub const MyStruct = extern struct {
    a: u8,
    b: u32,
    c: bool,
    d: MyEnum,
    e: demo_import.MyOtherStruct,
    f: *i16,

    pub const ZABC = 12;
    pub const who_is_the_coolest: []const u8 = "matt!";
};

const Bindings = switch (std.builtin.target.cpu.arch) {
    .wasm32, .wasm64 => struct {
        extern "fun" fn decodeStruct(ptr: *MyStruct) void;
        extern "fun" fn decodeStruct2(ptr: *MyStruct) void;
    },
    else => struct {
        fn decodeStruct(ptr: *MyStruct) void {
            _ = ptr;
        }

        fn decodeStruct2(ptr: *MyStruct) void {
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

pub export fn joe() void {
    var z: i16 = 420;
    var t = MyStruct{
        .a = 69,
        .b = 56789,
        .c = false,
        .d = .other,
        .e = .{ .abc = 123 },
        .f = &z,
    };
    Bindings.decodeStruct(&t);
    Bindings.decodeStruct2(&t);
}

pub export fn joeManipulatesStructFromZig(st: *MyStruct) void {
    st.a += 1;
}
