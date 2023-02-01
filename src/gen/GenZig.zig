const GenZig = @This();

const std = @import("std");
const meta = @import("../meta.zig");
const utils = @import("utils.zig");

/// Please feed in an arena
pub fn generate(allocator: std.mem.Allocator, comptime T: type, writer: anytype) anyerror!void {
    var buf = std.ArrayListUnmanaged(u8){};

    inline for (comptime std.meta.declarations(T)) |decl| {
        if (decl.is_pub) {
            try generateDecl(allocator, decl.name, @field(T, decl.name), buf.writer(allocator));
        }
    }

    try buf.append(allocator, 0);

    const parsed = try std.zig.parse(allocator, @ptrCast([:0]const u8, buf.items[0 .. buf.items.len - 1]));

    if (parsed.errors.len != 0) {
        try writer.print("{s}\n", .{buf.items});

        for (parsed.errors) |err| {
            try parsed.renderError(err, writer);
            try writer.writeAll("\n");
        }
        return;
    }

    try writer.writeAll(@embedFile("prelude.zig"));
    try writer.writeAll("\n");
    try writer.writeAll(try parsed.render(allocator));
}

fn generateDecl(allocator: std.mem.Allocator, comptime name: []const u8, comptime T: type, writer: anytype) anyerror!void {
    return switch (@typeInfo(T)) {
        .Struct => try generateStruct(allocator, name, T, writer),
        .Fn => try generateFunction(allocator, name, T, writer),
        else => @compileError("Type not supported: " ++ @typeName(T)),
    };
}

fn generateFieldType(_: std.mem.Allocator, comptime T: type, writer: anytype) anyerror!void {
    switch (@typeInfo(T)) {
        else => try writer.writeAll(@typeName(T)),
    }
}

pub fn requiresAllocator(comptime @"type": type) bool {
    if (@"type" == []const u8) return true;
    return false;
}

pub fn generateStruct(
    allocator: std.mem.Allocator,
    comptime name: []const u8,
    comptime T: type,
    writer: anytype,
) !void {
    const info = meta.getStruct(T);

    try writer.print("pub const {s} = struct {{handle: Handle,\n\n", .{std.zig.fmtId(name)});

    if (info.options.creatable) {
        // TODO: Make createable have error set
        try writer.print(
            \\pub fn create() {[name]s} {{
            \\    const B = struct {{
            \\        extern fn {[create]s}() i32;
            \\    }}; 
            \\    return .{{ .handle = @intToEnum(Handle, B.{[create]s}()) }};
            \\}}
        , .{
            .name = name,
            .create = utils.NameGenerator.@"struct"(.create, name),
        });
    }

    inline for (comptime std.meta.fields(info.type)) |field| {
        const field_info = meta.getField(field.type);

        switch (field_info.options.get) {
            .yes => |get_opts| {
                if (get_opts.errors) |errs| {
                    try writer.print("pub const Get{s}Error = error{{", .{utils.SnakeToPascal{ .str = field.name }});
                    inline for (comptime std.meta.fields(errs)) |err| {
                        try writer.print("{s},", .{std.zig.fmtId(err.name)});
                    }
                    try writer.writeAll("};");
                }

                try writer.print("pub fn get_{s}(self: {s} ", .{ field.name, std.zig.fmtId(name) });
                if (requiresAllocator(field_info.type)) try writer.writeAll(", allocator: std.mem.Allocator");
                try writer.writeAll(")");
                if (get_opts.errors) |_| {
                    try writer.print("Get{s}Error", .{utils.SnakeToPascal{ .str = field.name }});
                    try writer.writeAll("!");
                }
                try generateFieldType(allocator, field_info.type, writer);
                try writer.writeAll("{");

                switch (@typeInfo(field_info.type)) {
                    .Pointer => |_| {
                        if (field_info.type == []const u8) {
                            try writer.print(
                                \\const B = struct {{
                                \\    extern fn {[get_length]s}(handle: Handle) i32;
                                \\    extern fn {[get_value]s}(handle: Handle, ptr: i32) void;
                                \\}};
                                \\
                                \\const data = try allocator.alloc(u8, @intCast(usize, B.{[get_length]s}(self.handle)));
                                \\B.{[get_value]s}(self.handle, @intCast(i32, @ptrToInt(data.ptr)));
                                \\return data;
                            , .{
                                .get_length = std.zig.fmtId(utils.NameGenerator.structField(.get_length, name, field.name)),
                                .get_value = std.zig.fmtId(utils.NameGenerator.structField(.get_value, name, field.name)),
                            });
                        }
                    },
                    .Array => |_| {
                        try writer.print(
                            \\const B = struct {{
                            \\    extern fn {[get]s}(handle: Handle, ptr: i32) void;
                            \\}};
                            \\
                            \\const data: {[arr]s} = undefined;
                            \\B.{[get]s}(self.handle, @intCast(i32, @ptrToInt(data)));
                            \\return data;
                        , .{
                            .arr = @typeName(field_info.type),
                            .get = std.zig.fmtId(utils.NameGenerator.structField(.get, name, field.name)),
                        });
                    },
                    else => @panic("no"),
                }

                try writer.writeAll("}");
            },
            .no => {},
        }

        // SET

        switch (field_info.options.set) {
            .yes => |set_opts| {
                if (set_opts.errors) |errs| {
                    try writer.print("pub const Set{s}Error = error{{", .{utils.SnakeToPascal{ .str = field.name }});
                    inline for (comptime std.meta.fields(errs)) |err| {
                        try writer.print("{s},", .{std.zig.fmtId(err.name)});
                    }
                    try writer.writeAll("};");
                }

                try writer.print("pub fn set_{s}(self: {s}, value: ", .{ field.name, std.zig.fmtId(name) });
                try generateFieldType(allocator, field_info.type, writer);
                try writer.writeAll(")");
                if (set_opts.errors) |_| {
                    try writer.print("Set{s}Error", .{utils.SnakeToPascal{ .str = field.name }});
                    try writer.writeAll("!void");
                }
                try writer.writeAll("{");

                switch (@typeInfo(field_info.type)) {
                    .Pointer => |_| {
                        if (field_info.type == []const u8) {
                            try writer.print(
                                \\const B = struct {{
                                \\    extern fn {[set]s}(handle: Handle, ptr: i32, len: i32) void;
                                \\}};
                                \\
                                \\B.{[set]s}(self.handle, @intCast(i32, @ptrToInt(value)), @intCast(i32, value.len));
                                \\return value;
                            , .{
                                .set = std.zig.fmtId(utils.NameGenerator.structField(.set, name, field.name)),
                            });
                        }
                    },
                    .Array => |_| {
                        try writer.print(
                            \\const B = struct {{
                            \\    extern fn {[set]s}(handle: Handle, ptr: i32) void;
                            \\}};
                            \\
                            \\B.{[set]s}(self.handle, @intCast(i32, @ptrToInt(&value)));
                        , .{
                            .arr = @typeName(field_info.type),
                            .set = std.zig.fmtId(utils.NameGenerator.structField(.set, name, field.name)),
                        });
                    },
                    else => @panic("no"),
                }

                try writer.writeAll("}");
            },
            .no => {},
        }
    }

    try writer.writeAll("};\n");
}

pub fn generateFunction(
    allocator: std.mem.Allocator,
    comptime name: []const u8,
    comptime T: type,
    writer: anytype,
) !void {
    const fn_info = @typeInfo(T).Fn;

    try writer.print(
        \\pub fn {[name]s}(
    , .{
        .name = name,
    });

    // _ = allocator;
    inline for (fn_info.params) |param, index| {
        try writer.print("@\"{d}\": ", .{index});
        try generateFieldType(allocator, param.type.?, writer);
        try writer.writeByte(',');
    }

    try writer.writeByte(')');
    try generateFieldType(allocator, fn_info.return_type.?, writer);

    try writer.print(
        \\{{
        \\    const B = struct {{
        \\        extern fn {[name]s}(
    , .{
        .name = utils.NameGenerator.function(name),
    });

    inline for (fn_info.params) |param| {
        if (param.type.? == []const u8) {
            try writer.writeAll("i32, i32,");
            continue;
        }

        switch (param.type.?) {
            else => @compileError("Type not supported: " ++ @typeName(param.type.?)),
        }
    }

    // TODO: Support others
    try writer.writeAll(") void;");

    try writer.print(
        \\
        \\}};
        \\
        \\return B.{[name]s}(
    , .{
        .name = utils.NameGenerator.function(name),
    });

    inline for (fn_info.params) |param, index| {
        if (param.type.? == []const u8) {
            try writer.print("@intCast(i32, @ptrToInt(@\"{[index]d}\".ptr)), @intCast(i32, @\"{[index]d}\".len),", .{ .index = index });
            continue;
        }

        switch (param.type.?) {
            else => @compileError("Type not supported: " ++ @typeName(param.type.?)),
        }
    }

    try writer.writeAll(");}");
}
