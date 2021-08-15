//! wasm-pass source!
// TODO: Remove pesky anyerrors, blocked by https://github.com/ziglang/zig/issues/5149

const std = @import("std");

const pre = @embedFile("pre.js");
const post = @embedFile("post.js");

fn getByteCount(bits: u16) u16 {
    return @floatToInt(u16, std.math.pow(f64, 2, std.math.ceil(std.math.log(f64, 2, @intToFloat(f64, bits) / 8))));
}

pub fn printLiteral(comptime tp_store: *TPStore, writer: anytype, value: anytype) anyerror!void {
    const T = @TypeOf(value);
    switch (T) {
        type => try printType(tp_store, writer, value),
        []const u8 => try writer.print("\"{any}\"", .{std.zig.fmtEscapes(value)}),
        else => switch (@typeInfo(T)) {
            .Int, .ComptimeInt => try writer.print("{d}", .{value}),
            .Fn => _ = try writer.writeAll(
                \\() => new Error("Functions not implemented!")
            ),
            else => @compileError("printLiteral not implemented for: " ++ @typeName(T)),
        },
    }
}

pub fn printConst(comptime tp_store: *TPStore, writer: anytype, comptime name: []const u8, value: anytype) anyerror!void {
    std.log.debug("Generating constant {s} ({any})...", .{ name, value });
    try writer.print("static {s} = ", .{name});
    try printLiteral(tp_store, writer, value);
    _ = try writer.writeAll(";\n");
}

fn printMeta(comptime T: type, writer: anytype) !void {
    try writer.print("static meta = {{size: {d}}};\n", .{@sizeOf(T)});
}

fn printTypeJS(comptime T: type, writer: anytype) !void {
    const info = @typeInfo(T);

    switch (info) {
        .Int => _ = try writer.writeAll("number"),
        .Bool => _ = try writer.writeAll("boolean"),
        else => _ = try writer.writeAll(@typeName(T)),
    }
}

fn printDecode(comptime tp_store: *TPStore, comptime T: type, writer: anytype, offset: usize) !void {
    const info = @typeInfo(T);

    switch (info) {
        .Int => |int| {
            switch (int.signedness) {
                .signed => try writer.print("dataView.getInt{d}(offset + {d}, true)", .{ getByteCount(int.bits) * 8, offset }),
                .unsigned => try writer.print("dataView.getUint{d}(offset + {d}, true)", .{ getByteCount(int.bits) * 8, offset }),
            }
        },
        .Bool => try writer.print("dataView.getUint8(offset + {d}) != 0", .{offset}),
        .Enum => try writer.print("{s}.decode(dataView, offset + {d})", .{ tp_store.getTypePath(T), offset }),
        else => @compileError("Unimplemented: " ++ @typeName(T)),
    }
}

fn printEncode(comptime T: type, comptime field_name: []const u8, writer: anytype, offset: usize) !void {
    const info = @typeInfo(T);

    switch (info) {
        .Int => |int| {
            switch (int.signedness) {
                .signed => try writer.print("dataView.setInt{d}(offset + {d}, this.{s}, true)", .{ getByteCount(int.bits) * 8, offset, field_name }),
                .unsigned => try writer.print("dataView.setUint{d}(offset + {d}, this.{s}, true)", .{ getByteCount(int.bits) * 8, offset, field_name }),
            }
        },
        .Bool => try writer.print("dataView.setUint8(offset + {d}, this.{s} === true ? 1 : 0)", .{ offset, field_name }),
        .Enum => try writer.print("this.{s}.encode(dataView, offset + {d})", .{ field_name, offset }),
        else => @compileError("Unimplemented: " ++ @typeName(T)),
    }
}

fn printEnum(comptime tp_store: *TPStore, writer: anytype, comptime T: type, comptime info: std.builtin.TypeInfo.Enum) !void {
    try writer.print("class {s} extends Enum {{\n", .{@typeName(T)});
    try printMeta(T, writer);
    try printChildren(tp_store, writer, T);
    inline for (info.fields) |field| {
        try writer.print("static {s} = ce({s}, {d});\n", .{ field.name, @typeName(T), field.value });
    }
    try writer.print(
        \\
        \\/**
        \\ * Decodes a `{s}`
        \\ * @param {{DataView}} dataView DataView representing WASM memory
        \\ * @param {{number}} offset The offset at which the struct starts
        \\ * @returns {{{s}}}
        \\ */
        \\static decode(dataView, offset = 0) {{
        \\return this.from(
    , .{ @typeName(T), @typeName(T) });
    try printDecode(tp_store, info.tag_type, writer, 0);
    try writer.print(
        \\);
        \\}}
        \\
        \\/**
        \\ * Encodes a `{s}`
        \\ * @param {{DataView}} dataView DataView representing WASM memory
        \\ * @param {{number}} offset The offset at which the struct starts
        \\ * @returns {{{s}}}
        \\ */
        \\encode(dataView, offset = 0) {{
        \\
    , .{ @typeName(T), @typeName(T) });
    try printEncode(info.tag_type, "value", writer, 0);
    _ = try writer.writeAll(
        \\
        \\}
        \\}
        \\
    );
}

fn printStruct(comptime tp_store: *TPStore, writer: anytype, comptime T: type, comptime info: std.builtin.TypeInfo.Struct) !void {
    try writer.print("class {s} extends Struct {{\n", .{@typeName(T)});
    try printMeta(T, writer);
    try printChildren(tp_store, writer, T);
    inline for (info.fields) |field| {
        try writer.print("/**\n * @type {{", .{});
        try printTypeJS(field.field_type, writer);
        try writer.print("}} {s}\n */\n{s};", .{ @typeName(field.field_type), field.name });
        _ = try writer.writeAll("\n");
    }
    _ = try writer.print(
        \\/**
        \\ * Decodes a `{s}`
        \\ * @param {{DataView}} dataView DataView representing WASM memory
        \\ * @param {{number}} offset The offset at which the struct starts
        \\ * @returns {{{s}}}
        \\ */
        \\static decode(dataView, offset = 0) {{
        \\const obj = new this();
        \\
    , .{ @typeName(T), @typeName(T) });
    inline for (info.fields) |field| {
        try writer.print("obj.{s} = ", .{field.name});
        try printDecode(tp_store, field.field_type, writer, @offsetOf(T, field.name));
        _ = try writer.writeAll(";\n");
    }
    _ = try writer.writeAll("return obj;\n}\n");
    _ = try writer.print(
        \\
        \\/**
        \\ * Encodes a `{s}`
        \\ * @param {{DataView}} dataView DataView representing WASM memory
        \\ * @param {{number}} offset The offset at which the struct starts
        \\ * @returns {{{s}}}
        \\ */
        \\encode(dataView, offset = 0) {{
        \\
    , .{ @typeName(T), @typeName(T) });
    inline for (info.fields) |field| {
        try printEncode(field.field_type, field.name, writer, @offsetOf(T, field.name));
        _ = try writer.writeAll(";\n");
    }
    _ = try writer.writeAll(
        \\
        \\}
        \\}
        \\
    );
}

/// Generate constants within type
pub fn printChildren(comptime tp_store: *TPStore, writer: anytype, comptime T: type) anyerror!void {
    inline for (std.meta.declarations(T)) |decl| {
        if (decl.is_pub) {
            try printConst(tp_store, writer, decl.name, @field(T, decl.name));
        }
    }
}

pub fn printType(comptime tp_store: *TPStore, writer: anytype, comptime T: type) anyerror!void {
    std.log.debug("Generating type {s}...", .{@typeName(T)});

    switch (@typeInfo(T)) {
        .Struct => |struct_info| try printStruct(tp_store, writer, T, struct_info),
        .Enum => |enum_info| try printEnum(tp_store, writer, T, enum_info),
        else => {},
    }
}

// Type "absolute path" resolution
const TPEntry = struct { T: type, path: []const u8 };
const TPStore = struct {
    type_paths: anytype,

    pub fn resolveTypes(comptime self: *TPStore, comptime prefix: []const u8, comptime T: type) void {
        comptime for (std.meta.declarations(T)) |decl| {
            if (decl.is_pub) {
                switch (decl.data) {
                    .Type => {
                        var z = [1]TPEntry{.{ .T = @field(T, decl.name), .path = prefix ++ "." ++ decl.name }};
                        self.type_paths = self.type_paths ++ z;
                        self.resolveTypes(prefix ++ "." ++ decl.name, @field(T, decl.name));
                    },
                    else => {},
                }
            }
        };
    }

    pub fn getTypePath(comptime self: *TPStore, comptime T: type) []const u8 {
        const z = self.type_paths;
        comptime for (z) |ts| {
            if (T == ts.T)
                return ts.path;
        };

        @compileError("Could not find type path for type " ++ @typeName(T));
    }
};

pub fn bind(namespace: anytype, writer: anytype) anyerror!void {
    comptime var type_paths = [0]TPEntry{};
    comptime var tp_store = TPStore{ .type_paths = type_paths };
    comptime tp_store.resolveTypes(@typeName(namespace), namespace);

    _ = try writer.writeAll(pre);
    try printType(tp_store, writer, namespace);
    try writer.print("module.exports = {s};\n", .{@typeName(namespace)});
    _ = try writer.writeAll(post);
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
