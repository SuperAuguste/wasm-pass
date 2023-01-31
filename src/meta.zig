//! wasm-pass-meta

pub const StructOptions = struct {
    creatable: bool = false,
    snapshotable: bool = false,
};

const StructMark = opaque {};
pub fn Struct(comptime T: type, comptime options_: StructOptions) type {
    if (@typeInfo(T) != .Struct) @compileError("pass.Struct only supports struct types");
    return struct {
        const mark = StructMark;

        const @"type" = T;
        const options = options_;
    };
}

pub fn getStruct(comptime T: type) struct { type: type, options: StructOptions } {
    if (@hasDecl(T, "mark") and T.mark == StructMark) {
        return .{ .type = T.type, .options = T.options };
    } else {
        return .{ .type = T, .options = .{} };
    }
}

pub const AccessorOptions = union(enum) {
    no,
    yes: struct {
        name: ?[]const u8 = null,
        errors: ?type = null,
    },
};

pub const FieldOptions = struct {
    read_only: bool = false,
    get: AccessorOptions = .{ .yes = .{} },
    set: AccessorOptions = .{ .yes = .{} },
};

const FieldMark = opaque {};
pub fn Field(comptime T: type, comptime options_: FieldOptions) type {
    return struct {
        const mark = FieldMark;

        const @"type" = T;
        const options = options_;
    };
}

pub fn getField(comptime T: type) struct { type: type, options: FieldOptions } {
    if (@hasDecl(T, "mark") and T.mark == FieldMark) {
        return .{ .type = T.type, .options = T.options };
    } else {
        return .{ .type = T, .options = .{} };
    }
}
