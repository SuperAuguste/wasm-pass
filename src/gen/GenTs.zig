const GenZig = @This();

const std = @import("std");
const meta = @import("../meta.zig");
const AutoIndentingStream = @import("../auto_indenting_stream.zig").AutoIndentingStream;

pub const FieldTypeFormatter = struct {
    type: type,

    pub fn format(comptime value: FieldTypeFormatter, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        const T = value.type;

        if (T == []const u8) {
            try writer.writeAll("string");
            return;
        }

        switch (@typeInfo(T)) {
            .Array => |arr_info| {
                // TODO: Handle non-u8
                try writer.print("Uint8Array/*<{d}>*/", .{arr_info.len});
            },
            else => @compileError("Type not supported: " ++ @typeName(T)),
        }
    }
};

pub const FieldNameFormatter = struct {
    pub const Kind = enum { get, get_length, get_value, set };
    pub fn structField(comptime kind: Kind, comptime struct_name: []const u8, comptime field_name: []const u8) []const u8 {
        return std.fmt.comptimePrint("{}", .{comptime std.zig.fmtId(switch (kind) {
            .get => "wasm_pass__" ++ struct_name ++ "_get_" ++ field_name,
            .get_length => "wasm_pass__" ++ struct_name ++ "_get_" ++ field_name ++ "_length",
            .get_value => "wasm_pass__" ++ struct_name ++ "_get_" ++ field_name ++ "_value",
            .set => "wasm_pass__" ++ struct_name ++ "_set_" ++ field_name,
        })});
    }
};

/// Please feed in an arena
pub fn generate(allocator: std.mem.Allocator, comptime T: type, writer: anytype) anyerror!void {
    try writer.writeAll(@embedFile("prelude.ts"));
    try writer.writeAll("\n");

    var buf = std.ArrayListUnmanaged(u8){};
    var aiw = AutoIndentingStream(@TypeOf(writer)){ .underlying_writer = writer, .indent_delta = 4 };
    var func_aiw = AutoIndentingStream(@TypeOf(buf.writer(allocator))){ .underlying_writer = buf.writer(allocator), .indent_delta = 4 };

    func_aiw.pushIndent();

    inline for (comptime std.meta.declarations(T)) |decl| {
        if (decl.is_pub) {
            try generateDecl(allocator, decl.name, @field(T, decl.name), aiw.writer(), func_aiw.writer());
        }
    }

    try aiw.writer().writeAll("function create(manager: HandleManager, memory: WebAssembly.Memory) {");
    aiw.pushIndent();
    try aiw.writer().writeAll("\nreturn {env: {\n");

    try writer.writeAll(buf.items);

    aiw.popIndent();
    try aiw.writer().writeAll("}};\n");
    try aiw.writer().writeAll("}");
}

fn generateDecl(
    allocator: std.mem.Allocator,
    comptime name: []const u8,
    comptime T: type,
    writer: anytype,
    func_writer: anytype,
) anyerror!void {
    return switch (@typeInfo(T)) {
        .Struct => try generateStruct(allocator, name, T, writer, func_writer),
        else => @compileError("Type not supported: " ++ @typeName(T)),
    };
}

fn generateFieldType(_: std.mem.Allocator, comptime T: type, writer: anytype) anyerror!void {
    switch (@typeInfo(T)) {
        else => try writer.writeAll(@typeName(T)),
    }
}

pub fn generateStruct(
    _: std.mem.Allocator,
    comptime name: []const u8,
    comptime T: type,
    writer: anytype,
    func_writer: anytype,
) !void {
    const info = meta.getStruct(T);

    try writer.print("export interface {s} {{\n", .{name});

    writer.context.pushIndent();

    inline for (comptime std.meta.fields(info.type)) |field| {
        const field_info = meta.getField(field.type);

        try writer.print("{s}: {s};", .{ field.name, FieldTypeFormatter{ .type = field_info.type } });
        try writer.writeAll("\n");
    }

    writer.context.popIndent();

    try writer.writeAll("};\n");

    inline for (comptime std.meta.fields(info.type)) |field| {
        const field_info = meta.getField(field.type);

        switch (field_info.options.get) {
            .yes => |_| {
                // if (get_opts.errors) |errs| {
                //     try writer.print("pub const Get{s}Error = error{{", .{utils.SnakeToPascal{ .str = field.name }});
                //     inline for (comptime std.meta.fields(errs)) |err| {
                //         try writer.print("{s},", .{std.zig.fmtId(err.name)});
                //     }
                //     try writer.writeAll("};");
                // }

                switch (@typeInfo(field_info.type)) {
                    .Pointer => |_| {
                        if (field_info.type == []const u8) {
                            try func_writer.print(
                                \\{[get_length]s}(handle: Handle): number {{
                                \\    return manager.get<{s}>(handle)!.{s}.length;
                                \\}},
                                \\{[get_value]s}(handle: Handle, ptr: number): void {{
                                \\    new Uint8Array(memory.buffer).set(manager.get<{s}>(handle)!.{s}, ptr);
                                \\}},
                            , .{
                                .get_length = FieldNameFormatter.structField(.get_length, name, field.name),
                                .get_value = FieldNameFormatter.structField(.get_value, name, field.name),
                            });
                        }
                    },
                    .Array => |_| {
                        try func_writer.print(
                            \\{[get]s}(handle: Handle, ptr: number): void {{
                            \\    new Uint8Array(memory.buffer).set(manager.get<{s}>(handle)!.{s}, ptr);
                            \\}},
                        , .{
                            // .arr = @typeName(field_info.type),
                            .get = FieldNameFormatter.structField(.get, name, field.name),
                        });
                    },
                    else => @panic("no"),
                }

                try func_writer.writeAll("\n");
            },
            .no => {},
        }
    }

    // for (@"struct".fields) |field| {
    //     switch (field.type) {
    //         .identifier => |id| {
    //             if (std.mem.eql(u8, id.value, "string")) {
    //                 try writer.print("extern fn wasm_pass__{s}_get_{s}_length(handle: Handle) i32;\n", .{ std.zig.fmtId(@"struct".name), std.zig.fmtId(field.name) });
    //                 try writer.print("extern fn wasm_pass__{s}_get_{s}_value(handle: Handle, ptr: i32) void;\n", .{ std.zig.fmtId(@"struct".name), std.zig.fmtId(field.name) });

    //                 if (!field.is_read_only) try writer.print("extern fn wasm_pass__{s}_set_{s}(handle: Handle, ptr: i32, len: i32) void;\n", .{ std.zig.fmtId(@"struct".name), std.zig.fmtId(field.name) });
    //             }
    //         },
    //         .array => {
    //             try writer.print("extern fn wasm_pass__{s}_get_{s}(handle: Handle, ptr: i32) void;\n", .{ std.zig.fmtId(@"struct".name), std.zig.fmtId(field.name) });

    //             if (!field.is_read_only) try writer.print("extern fn wasm_pass__{s}_set_{s}(handle: Handle, ptr: i32) void;\n", .{ std.zig.fmtId(@"struct".name), std.zig.fmtId(field.name) });
    //         },
    //         else => @panic("no"),
    //     }
    // }
}
