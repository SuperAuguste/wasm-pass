const GenZig = @This();

const std = @import("std");
const meta = @import("../meta.zig");
const utils = @import("utils.zig");
const AutoIndentingStream = @import("../auto_indenting_stream.zig").AutoIndentingStream;

// pub const FieldTypeFormatter = struct {
//     type: type,

//     pub fn format(comptime value: FieldTypeFormatter, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
//         const T = value.type;

//         if (T == []const u8) {
//             try writer.writeAll("string");
//             return;
//         }

//         switch (@typeInfo(T)) {
//             .Array => |arr_info| {
//                 // TODO: Handle non-u8
//                 try writer.print("Uint8Array/*<{d}>*/", .{arr_info.len});
//             },
//             else => @compileError("Type not supported: " ++ @typeName(T)),
//         }
//     }
// };

/// Please feed in an arena
pub fn generate(allocator: std.mem.Allocator, comptime T: type, writer: anytype) anyerror!void {
    try writer.writeAll(@embedFile("prelude.ts"));
    try writer.writeAll("\n");

    var manager_buf = std.ArrayListUnmanaged(u8){};
    var func_buf = std.ArrayListUnmanaged(u8){};

    var aiw = AutoIndentingStream(@TypeOf(writer)){ .underlying_writer = writer, .indent_delta = 4 };
    var func_aiw = AutoIndentingStream(@TypeOf(func_buf.writer(allocator))){ .underlying_writer = func_buf.writer(allocator), .indent_delta = 4 };

    func_aiw.pushIndent();

    inline for (comptime std.meta.declarations(T)) |decl| {
        if (decl.is_pub) {
            try generateDecl(allocator, decl.name, @field(T, decl.name), aiw.writer(), func_aiw.writer(), manager_buf.writer(allocator));
        }
    }

    try writer.writeAll("export interface Manager extends HandleManager {\n");
    try writer.writeAll(manager_buf.items);
    try writer.writeAll("\n};\n\n");

    try aiw.writer().writeAll("export function create(manager: Manager, memory: WebAssembly.Memory, extras: any = {}) {");
    aiw.pushIndent();
    try aiw.writer().writeAll("\nreturn {env: {memory,\n");

    try writer.writeAll(func_buf.items);

    aiw.popIndent();
    try aiw.writer().writeAll("...extras,}};\n");
    try aiw.writer().writeAll("}");
}

fn generateDecl(
    allocator: std.mem.Allocator,
    comptime name: []const u8,
    comptime T: type,
    writer: anytype,
    func_writer: anytype,
    manager_writer: anytype,
) anyerror!void {
    return switch (@typeInfo(T)) {
        .Struct => try generateStruct(allocator, name, T, writer, func_writer, manager_writer),
        .Fn => try generateFunction(allocator, name, T, writer, func_writer, manager_writer),
        else => @compileError("Type not supported: " ++ @typeName(T)),
    };
}

fn fieldTypeName(comptime T: type) []const u8 {
    if (T == []const u8) {
        return "string";
    }

    switch (@typeInfo(T)) {
        .Array => |arr_info| {
            // TODO: Handle non-u8
            return std.fmt.comptimePrint("Uint8Array/*<{d}>*/", .{arr_info.len});
        },
        else => return @typeName(T),
    }
}

pub fn generateStruct(
    _: std.mem.Allocator,
    comptime name: []const u8,
    comptime T: type,
    writer: anytype,
    func_writer: anytype,
    manager_writer: anytype,
) !void {
    const info = meta.getStruct(T);

    if (info.options.creatable) {
        try manager_writer.print(
            \\    create{[name]s}(handle: Handle): void;
        , .{ .name = name });

        try func_writer.print(
            \\{[create]s}(): Handle {{
            \\    const handle = manager.createHandle();
            \\    manager.create{[name]s}(handle);
            \\    return handle;
            \\}},
            \\
        , .{
            .name = name,
            .create = utils.NameGenerator.@"struct"(.create, name),
        });
    }

    try writer.print("export interface {s} {{\n", .{name});

    writer.context.pushIndent();

    inline for (comptime std.meta.fields(info.type)) |field| {
        const field_info = meta.getField(field.type);

        try writer.print("{s}: {s};", .{ field.name, fieldTypeName(field_info.type) });
        try writer.writeAll("\n");
    }

    writer.context.popIndent();

    try writer.writeAll("};\n");

    inline for (comptime std.meta.fields(info.type)) |field| {
        const field_info = meta.getField(field.type);

        switch (field_info.options.get) {
            .yes => |_| {
                switch (@typeInfo(field_info.type)) {
                    .Pointer => |_| {
                        if (field_info.type == []const u8) {
                            try func_writer.print(
                                \\{[get_length]s}(handle: Handle): number {{
                                \\    return manager.getHandle<{s}>(handle)!.{s}.length;
                                \\}},
                                \\{[get_value]s}(handle: Handle, ptr: number): void {{
                                \\    new Uint8Array(memory.buffer).set(new TextEncoder().encode(manager.getHandle<{[name]s}>(handle)!.{[field_name]s}), ptr);
                                \\}},
                            , .{
                                .name = name,
                                .field_name = field.name,
                                .get_length = utils.NameGenerator.structField(.get_length, name, field.name),
                                .get_value = utils.NameGenerator.structField(.get_value, name, field.name),
                            });
                        }
                    },
                    .Array => |_| {
                        try func_writer.print(
                            \\{[get]s}(handle: Handle, ptr: number): void {{
                            \\    new Uint8Array(memory.buffer).set(manager.getHandle<{[name]s}>(handle)!.{[field_name]s}, ptr);
                            \\}},
                        , .{
                            .name = name,
                            .field_name = field.name,
                            .get = utils.NameGenerator.structField(.get, name, field.name),
                        });
                    },
                    else => @panic("no"),
                }

                try func_writer.writeAll("\n");
            },
            .no => {},
        }
    }
}

pub fn generateFunction(
    _: std.mem.Allocator,
    comptime name: []const u8,
    comptime T: type,
    _: anytype,
    func_writer: anytype,
    manager_writer: anytype,
) !void {
    const fn_info = @typeInfo(T).Fn;

    try func_writer.print(
        \\{[name]s}(
    , .{
        .name = utils.NameGenerator.function(name),
    });

    inline for (fn_info.params) |param, index| {
        if (param.type.? == []const u8) {
            try func_writer.print("arg{[index]d}_ptr: number, arg{[index]d}_len: number,", .{ .index = index });
            continue;
        }

        switch (param.type.?) {
            else => @compileError("Type not supported: " ++ @typeName(param.type.?)),
        }
    }

    // TODO: Support other return types properly
    try func_writer.print("): {s}", .{fieldTypeName(fn_info.return_type.?)});

    try func_writer.writeAll("{\n");

    try func_writer.print(
        \\return manager.{[name]s}(
    , .{
        .name = name,
    });

    inline for (fn_info.params) |param, index| {
        if (param.type.? == []const u8) {
            try func_writer.print("new TextDecoder().decode(memory.buffer.slice(arg{[index]d}_ptr, arg{[index]d}_ptr + arg{[index]d}_len))", .{ .index = index });
            continue;
        }

        switch (param.type.?) {
            else => @compileError("Type not supported: " ++ @typeName(param.type.?)),
        }
    }

    try func_writer.writeAll(");},\n");

    // Manager
    try manager_writer.print(
        \\{[name]s}(
    , .{
        .name = name,
    });

    inline for (fn_info.params) |param, index| {
        try manager_writer.print("arg{d}: {s},", .{ index, fieldTypeName(param.type.?) });
    }

    try manager_writer.print("): {s};\n", .{fieldTypeName(fn_info.return_type.?)});
}
