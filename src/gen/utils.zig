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
