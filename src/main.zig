//! wasm-pass source!
// TODO: Remove pesky anyerrors, blocked by https://github.com/ziglang/zig/issues/5149

const std = @import("std");

const AutoIndentingStream = @import("auto_indenting_stream.zig").AutoIndentingStream;

const pre = @embedFile("pre.js");
const post = @embedFile("post.js");

const Stream = AutoIndentingStream(std.fs.File.Writer);
const Writer = Stream.Writer;

fn getBitCount(bits: u16) u16 {
    return std.math.ceilPowerOfTwo(u16, bits) catch unreachable;
}

const AssignmentState = struct {
    is_object: bool = false,
    is_class: bool = false,
};

pub fn printConst(comptime tp_store: *TPStore, writer: Writer, value: anytype, comptime name: []const u8, state: AssignmentState) anyerror!void {
    const T = @TypeOf(value);

    std.log.debug("Generating constant {s} ({s})...", .{ name, @typeName(T) });

    if (state.is_class) {
        try writer.print("static {s} = ", .{name});
    } else if (state.is_object) {
        try writer.print("{s}: ", .{name});
    } else {
        try writer.print("const {s} = ", .{name});
    }

    switch (T) {
        type => try printType(tp_store, writer, value),
        []const u8 => try writer.print("\"{}\"", .{std.zig.fmtEscapes(value)}),
        else => switch (@typeInfo(T)) {
            .Int, .ComptimeInt, .Float, .ComptimeFloat => try writer.print("{d}", .{value}),
            .Fn => _ = try writer.writeAll(
                \\() => new Error("Functions not implemented!")
            ),
            else => @compileError("printConst not implemented for: " ++ @typeName(T)),
        },
    }

    if (state.is_object) {
        try writer.writeAll(",");
    } else {
        try writer.writeAll(";");
    }
}

fn printMeta(comptime T: type, writer: Writer) !void {
    try writer.print("static meta = {{size: {d}}};\n", .{@sizeOf(T)});
}

fn typeNameJs(comptime tp_store: *TPStore, comptime T: type) []const u8 {
    const info = @typeInfo(T);

    return switch (info) {
        .Int, .ComptimeInt, .Float, .ComptimeFloat => "number",
        .Bool => "boolean",
        else => tp_store.getTypePath(T),
    };
}

fn printDecode(comptime tp_store: *TPStore, comptime T: type, writer: Writer, offset: usize) !void {
    const info = @typeInfo(T);

    switch (info) {
        .Int => |int| {
            const bits = getBitCount(int.bits);
            const endian = if (bits == 8) "" else ", true";

            switch (int.signedness) {
                .signed => try writer.print("dataView.getInt{d}(offset + {d}{s})", .{ bits, offset, endian }),
                .unsigned => try writer.print("dataView.getUint{d}(offset + {d}{s})", .{ bits, offset, endian }),
            }
        },
        .Bool => try writer.print("dataView.getUint8(offset + {d}) != 0", .{offset}),
        .Enum, .Struct => try writer.print("{s}.decode(dataView, offset + {d})", .{ tp_store.getTypePath(T), offset }),
        // .Struct => try writer.print("{s}.decode(dataView, offset + {d})", .{ tp_store.getTypePath(T), offset }),
        else => @compileError("Unimplemented: " ++ @typeName(T)),
    }
}

fn printEncode(comptime T: type, comptime field_name: []const u8, writer: Writer, offset: usize) !void {
    const info = @typeInfo(T);

    switch (info) {
        .Int => |int| {
            const bits = getBitCount(int.bits);
            const endian = if (bits == 8) "" else ", true";

            switch (int.signedness) {
                .signed => try writer.print("dataView.setInt{d}(offset + {d}, this.{s}{s})", .{ bits, offset, field_name, endian }),
                .unsigned => try writer.print("dataView.setUint{d}(offset + {d}, this.{s}{s})", .{ bits, offset, field_name, endian }),
            }
        },
        .Bool => try writer.print("dataView.setUint8(offset + {d}, this.{s} === true ? 1 : 0)", .{ offset, field_name }),
        .Enum, .Struct => try writer.print("this.{s}.encode(dataView, offset + {d})", .{ field_name, offset }),
        else => @compileError("Unimplemented: " ++ @typeName(T)),
    }
}

fn printEnum(comptime tp_store: *TPStore, writer: Writer, comptime T: type) !void {
    const info = @typeInfo(T).Enum;

    writer.context.pushIndent();

    try writer.context.insertNewline();

    try writer.print("class {s} extends Enum {{\n", .{@typeName(T)});
    writer.context.pushIndent();

    try printMeta(T, writer);
    try printDeclarations(tp_store, writer, T, .{ .is_class = true });

    try writer.context.insertNewline();

    inline for (info.fields) |field| {
        try writer.print("static {s} = createEnumValue({s}, {d});\n", .{ field.name, @typeName(T), field.value });
    }

    try writer.context.insertNewline();

    try writer.writeAll("/**\n");
    try writer.print(" * Decodes a {{@link {s}}}\n", .{@typeName(T)});
    try writer.writeAll(" * @param {DataView} dataView DataView representing WASM memory\n");
    try writer.writeAll(" * @param {number} offset The offset at which the struct starts\n");
    try writer.print(" * @returns {{{s}}}\n", .{@typeName(T)});
    try writer.writeAll(" */\n");
    try writer.writeAll("static decode(dataView, offset = 0) {\n");
    writer.context.pushIndent();

    try writer.writeAll("return this.from(");
    try printDecode(tp_store, info.tag_type, writer, 0);
    try writer.writeAll(");\n");

    writer.context.popIndent();
    try writer.writeAll("}\n");

    try writer.context.insertNewline();

    try writer.writeAll("/**\n");
    try writer.print(" * Encodes a {{@link {s}}}\n", .{@typeName(T)});
    try writer.writeAll(" * @param {DataView} dataView DataView representing WASM memory\n");
    try writer.writeAll(" * @param {number} offset The offset at which the struct starts\n");
    try writer.writeAll(" */\n");
    try writer.writeAll("encode(dataView, offset = 0) {\n");
    writer.context.pushIndent();

    try printEncode(info.tag_type, "value", writer, 0);
    try writer.context.insertNewline();

    writer.context.popIndent();
    try writer.writeAll("}\n");

    writer.context.popIndent();
    _ = try writer.writeAll("}");

    writer.context.popIndent();
}

fn printUndefined(comptime tp_store: *TPStore, writer: Writer, field: std.builtin.TypeInfo.StructField) !void {
    switch (@typeInfo(field.field_type)) {
        .Int, .Float => try writer.print("0x{x}", .{
            @bitCast(field.field_type, [1]u8{0xAA} ** @sizeOf(field.field_type)),
        }),
        .Bool => _ = try writer.writeAll("false"),
        .Enum => |e| try writer.print("{s}.from(0x{x})", .{
            tp_store.getTypePath(field.field_type),
            @bitCast(e.tag_type, [1]u8{0xAA} ** @sizeOf(field.field_type)),
        }),
        .Struct => try writer.print("new {s}()", .{tp_store.getTypePath(field.field_type)}),
        else => @compileError("printUndefined not implemented for " ++ @typeName(field.field_type)),
    }
}

fn printStruct(comptime tp_store: *TPStore, writer: Writer, comptime T: type) !void {
    const info = @typeInfo(T).Struct;

    writer.context.pushIndent();
    if (info.fields.len > 0) {
        try writer.context.insertNewline();
        try writer.writeAll("/**\n");
        try writer.print(" * @alias {s}\n", .{tp_store.getTypePath(T)});
        try writer.writeAll(" */\n");

        try writer.print("class {s} extends Struct {{\n", .{@typeName(T)});
        writer.context.pushIndent();

        try printMeta(T, writer);
        try printDeclarations(tp_store, writer, T, .{ .is_class = true });

        try writer.context.insertNewline();

        inline for (info.fields) |field| {
            try writer.print("/** Zig type: {s} */\n", .{@typeName(field.field_type)});
            try writer.print("{s} = ", .{field.name});
            try printUndefined(tp_store, writer, field);
            _ = try writer.writeAll(";\n");
            try writer.context.insertNewline();
        }

        try writer.writeAll("/**\n");
        try writer.print(" * Decodes a {{@link {s}}}\n", .{@typeName(T)});
        try writer.writeAll(" * @param {DataView} dataView DataView representing WASM memory\n");
        try writer.writeAll(" * @param {number} offset The offset at which the struct starts\n");
        try writer.print(" * @returns {{{s}}}\n", .{@typeName(T)});
        try writer.writeAll(" */\n");
        try writer.writeAll("static decode(dataView, offset = 0) {\n");
        writer.context.pushIndent();

        try writer.writeAll("const obj = new this();\n");

        inline for (info.fields) |field| {
            try writer.print("obj.{s} = ", .{field.name});
            try printDecode(tp_store, field.field_type, writer, @offsetOf(T, field.name));
            _ = try writer.writeAll(";\n");
        }

        _ = try writer.writeAll("return obj;\n");

        writer.context.popIndent();
        _ = try writer.writeAll("}\n");

        try writer.context.insertNewline();

        try writer.writeAll("/**\n");
        try writer.print(" * Encodes a {{@link {s}}}\n", .{@typeName(T)});
        try writer.writeAll(" * @param {DataView} dataView DataView representing WASM memory\n");
        try writer.writeAll(" * @param {number} offset The offset at which the struct starts\n");
        try writer.writeAll(" */\n");
        try writer.writeAll("encode(dataView, offset = 0) {\n");
        writer.context.pushIndent();

        inline for (info.fields) |field| {
            try printEncode(field.field_type, field.name, writer, @offsetOf(T, field.name));
            _ = try writer.writeAll(";\n");
        }

        writer.context.popIndent();
        _ = try writer.writeAll("}\n");
    } else {
        try writer.context.insertNewline();
        try writer.writeAll("{\n");
        writer.context.pushIndent();

        try printDeclarations(tp_store, writer, T, .{ .is_object = true });
    }

    writer.context.popIndent();
    _ = try writer.writeAll("}");

    writer.context.popIndent();
}

/// Generate constants within type
pub fn printDeclarations(comptime tp_store: *TPStore, writer: Writer, comptime T: type, state: AssignmentState) anyerror!void {
    inline for (std.meta.declarations(T)) |decl| {
        if (decl.is_pub) {
            try printConst(tp_store, writer, @field(T, decl.name), decl.name, state);
            try writer.context.insertNewline();
        }
    }
}

pub fn printType(comptime tp_store: *TPStore, writer: Writer, comptime T: type) anyerror!void {
    std.log.debug("Generating type {s}...", .{@typeName(T)});

    switch (@typeInfo(T)) {
        .Struct => try printStruct(tp_store, writer, T),
        .Enum => try printEnum(tp_store, writer, T),
        else => {},
    }
}

// Type "absolute path" resolution
const TPEntry = struct { T: type, path: []const u8 };
const TPStore = struct {
    type_paths: []const TPEntry = &[_]TPEntry{},

    pub fn resolveType(comptime self: *TPStore, comptime T: type) void {
        const path = @typeName(T);
        const name = path[0 .. std.mem.lastIndexOfScalar(u8, path, '.') orelse path.len];

        self.type_paths = self.type_paths ++ &[_]TPEntry{.{ .T = T, .path = name }};

        self.resolveTypeRecursive(name, T);
    }

    pub fn resolveTypeRecursive(comptime self: *TPStore, comptime prefix: []const u8, comptime T: type) void {
        comptime for (std.meta.declarations(T)) |decl| {
            if (decl.is_pub) {
                switch (decl.data) {
                    .Type => {
                        const path = prefix ++ "." ++ decl.name;
                        self.type_paths = self.type_paths ++ &[_]TPEntry{.{ .T = @field(T, decl.name), .path = path }};

                        self.resolveTypeRecursive(path, @field(T, decl.name));
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

pub fn bind(namespace: anytype, writer: std.fs.File.Writer) anyerror!void {
    comptime var tp_store = TPStore{};
    comptime tp_store.resolveType(namespace);

    var ais = Stream{
        .indent_delta = 4,
        .underlying_writer = writer,
    };
    const writer2 = ais.writer();

    _ = try writer2.writeAll(pre);
    try printConst(&tp_store, writer2, namespace, @typeName(namespace), .{});
    try ais.insertNewline();
    try ais.insertNewline();

    try writer2.print("module.exports = {s};\n", .{@typeName(namespace)});
    _ = try writer2.writeAll(post);
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
