const std = @import("std");

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

pub const NameGenerator = struct {
    pub const StructNameKind = enum { create };
    pub fn @"struct"(comptime kind: StructNameKind, comptime struct_name: []const u8) []const u8 {
        return switch (kind) {
            .create => "wasm_pass__" ++ struct_name ++ "_create",
        };
    }

    pub const StructFieldNameKind = enum { get, get_length, get_value, set };
    pub fn structField(comptime kind: StructFieldNameKind, comptime struct_name: []const u8, comptime field_name: []const u8) []const u8 {
        return switch (kind) {
            .get => "wasm_pass__" ++ struct_name ++ "_get_" ++ field_name,
            .get_length => "wasm_pass__" ++ struct_name ++ "_get_" ++ field_name ++ "_length",
            .get_value => "wasm_pass__" ++ struct_name ++ "_get_" ++ field_name ++ "_value",
            .set => "wasm_pass__" ++ struct_name ++ "_set_" ++ field_name,
        };
    }
};
