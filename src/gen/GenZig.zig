const GenZig = @This();

const std = @import("std");
const Parser = @import("../meta/Parser.zig");
const Node = Parser.Node;

pub const SnakeToPascal = struct {
    str: []const u8,

    pub fn format(value: SnakeToPascal, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.writeByte(std.ascii.toUpper(value.str[0]));

        var index: usize = 1;
        while (index < value.str.len) : (index += 1) {
            const char = value.str[index];
            if (char == '_') {
                index += 1;
                try writer.writeByte(std.ascii.toUpper(value.str[index]));
            } else {
                try writer.writeByte(std.ascii.toLower(value.str[index]));
            }
        }
    }
};

pub const StructExternFuncNameFormatter = struct {
    pub const Kind = enum {
        get,
        get_length,
        get_value,
        set,
    };

    @"struct": Node.Struct,
    field: Node.Struct.Field,
    kind: Kind,

    pub fn get(@"struct": Node.Struct, field: Node.Struct.Field) StructExternFuncNameFormatter {
        return .{ .@"struct" = @"struct", .field = field, .kind = .get };
    }

    pub fn getLength(@"struct": Node.Struct, field: Node.Struct.Field) StructExternFuncNameFormatter {
        return .{ .@"struct" = @"struct", .field = field, .kind = .get_length };
    }

    pub fn getValue(@"struct": Node.Struct, field: Node.Struct.Field) StructExternFuncNameFormatter {
        return .{ .@"struct" = @"struct", .field = field, .kind = .get_value };
    }

    pub fn set(@"struct": Node.Struct, field: Node.Struct.Field) StructExternFuncNameFormatter {
        return .{ .@"struct" = @"struct", .field = field, .kind = .set };
    }

    pub fn format(value: StructExternFuncNameFormatter, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        switch (value.kind) {
            .get => try writer.print("wasm_pass__{s}_get_{s}", .{ std.zig.fmtId(value.@"struct".name), std.zig.fmtId(value.field.name) }),
            .get_length => try writer.print("wasm_pass__{s}_get_{s}_length", .{ std.zig.fmtId(value.@"struct".name), std.zig.fmtId(value.field.name) }),
            .get_value => try writer.print("wasm_pass__{s}_get_{s}_value", .{ std.zig.fmtId(value.@"struct".name), std.zig.fmtId(value.field.name) }),
            .set => try writer.print("wasm_pass__{s}_set_{s}", .{ std.zig.fmtId(value.@"struct".name), std.zig.fmtId(value.field.name) }),
        }
    }
};

/// Please feed in an arena
pub fn generate(allocator: std.mem.Allocator, node: Node, writer: anytype) anyerror!void {
    switch (node) {
        .root => |root| {
            var buf = std.ArrayListUnmanaged(u8){};
            for (root.children) |child| {
                try generate(allocator, child, buf.writer(allocator));
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
        },
        .@"struct" => |@"struct"| try generateStruct(allocator, @"struct", writer),
        .identifier => |id| {
            const zig_map = std.ComptimeStringMap([]const u8, .{
                .{ "string", "[]const u8" },
            });
            try writer.writeAll(zig_map.get(id.value) orelse id.value);
        },
        .array => |arr| {
            try writer.print("[{d}]", .{arr.size});
            try generate(allocator, arr.type.*, writer);
        },
        else => @panic("a"),
    }
}

pub fn requiresAllocator(@"type": Node) bool {
    switch (@"type") {
        .identifier => |id| {
            if (std.mem.eql(u8, id.value, "string")) {
                return true;
            }
        },
        else => {},
    }

    return false;
}

pub fn generateStruct(allocator: std.mem.Allocator, @"struct": Node.Struct, writer: anytype) !void {
    try writer.print("pub const {s} = struct {{handle: Handle,\n\n", .{std.zig.fmtId(@"struct".name)});

    for (@"struct".fields) |field| {
        // GET

        if (field.get_errors.len != 0) {
            try writer.print("pub const Get{s}Error = error{{", .{SnakeToPascal{ .str = field.name }});
            for (field.get_errors) |err| {
                try writer.print("{s},", .{std.zig.fmtId(err)});
            }
            try writer.writeAll("};");
        }

        try writer.print("pub fn get_{s}(self: {s} ", .{ field.name, std.zig.fmtId(@"struct".name) });
        if (requiresAllocator(field.type)) try writer.writeAll(", allocator: std.mem.Allocator");
        try writer.writeAll(")");
        if (field.get_errors.len != 0) {
            try writer.print("Get{s}Error", .{SnakeToPascal{ .str = field.name }});
            try writer.writeAll("!");
        }
        try generate(allocator, field.type, writer);
        try writer.writeAll("{");

        switch (field.type) {
            .identifier => |id| {
                if (std.mem.eql(u8, id.value, "string")) {
                    // try writer.print("const B = struct {{extern fn wasm_pass__{s}_get_{s}_length(handle: Handle) i32;\n", .{ std.zig.fmtId(@"struct".name), std.zig.fmtId(field.name) });
                    try writer.print("const B = struct {{extern fn {s}() i32;\n", .{StructExternFuncNameFormatter.getLength(@"struct", field)});
                    try writer.print("extern fn {s}(handle: Handle, ptr: i32) void;\n}};\n", .{ std.zig.fmtId(@"struct".name), std.zig.fmtId(field.name) });
                    try writer.print("const data = try allocator.alloc(u8, B.wasm_pass__{s}_get_{s}_length(self.handle));\n", .{ std.zig.fmtId(@"struct".name), std.zig.fmtId(field.name) });
                    try writer.print("B.wasm_pass__{s}_get_{s}_value(self.handle, @intCast(i32, @ptrToInt(data)));", .{ std.zig.fmtId(@"struct".name), std.zig.fmtId(field.name) });
                    try writer.writeAll("return data;");
                }
            },
            .array => {
                // try writer.print("extern fn wasm_pass__{s}_get_{s}(handle: Handle, ptr: i32) void;\n", .{ std.zig.fmtId(@"struct".name), std.zig.fmtId(field.name) });
            },
            else => @panic("no"),
        }

        try writer.writeAll("}");

        // SET

        if (field.set_errors.len != 0) {
            try writer.print("pub const Set{s}Error = error{{", .{SnakeToPascal{ .str = field.name }});
            for (field.set_errors) |err| {
                try writer.print("{s},", .{std.zig.fmtId(err)});
            }
            try writer.writeAll("};");
        }

        if (!field.is_read_only) {
            try writer.print("pub fn set_{s}(self: {s}, value:  ", .{ field.name, std.zig.fmtId(@"struct".name) });
            try generate(allocator, field.type, writer);
            try writer.writeAll(")  ");

            if (field.set_errors.len != 0) {
                try writer.print("Set{s}Error", .{SnakeToPascal{ .str = field.name }});
                try writer.writeAll("!void");
            } else {
                try writer.writeAll("void");
            }

            try writer.writeAll("{}\n\n");
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

    try writer.writeAll("};\n");
}
