const std = @import("std");
const types = @import("wasm-types");

pub fn main() void {
    var ls = types.LocalStruct{ .id = "ab" ** 16 };
    std.log.info("{s}", .{ls.id});

    var rs = types.RemoteStruct.create(.{ .id = "ab" }) catch unreachable;
    std.log.info("{s}", .{rs.get_id()});
}
