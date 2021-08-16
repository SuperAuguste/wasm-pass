const std = @import("std");

const AutoIndentingStream = @import("auto_indenting_stream.zig").AutoIndentingStream;

const Stream = AutoIndentingStream(std.fs.File.Writer);
const Writer = Stream.Writer;

pub const TypeStore = struct {
    const Entry = struct { T: type, path: []const u8, name: []const u8 };
    paths: []const Entry = &[_]Entry{},

    pub fn resolveType(comptime self: *TypeStore, comptime T: type) void {
        const path = @typeName(T);
        const name = path[0 .. std.mem.lastIndexOfScalar(u8, path, '.') orelse path.len];

        self.paths = self.paths ++ [_]Entry{.{ .T = T, .path = name, .name = name }};

        self.resolveTypeRecursive(name, T);
    }

    pub fn resolveTypeRecursive(comptime self: *TypeStore, comptime prefix: []const u8, comptime T: type) void {
        inline for (std.meta.declarations(T)) |decl| {
            if (decl.is_pub) {
                switch (decl.data) {
                    .Type => {
                        const path = prefix ++ "." ++ decl.name;
                        self.paths = self.paths ++ [_]Entry{.{ .T = @field(T, decl.name), .path = path, .name = decl.name }};

                        self.resolveTypeRecursive(path, @field(T, decl.name));
                    },
                    else => {},
                }
            }
        }
    }

    pub fn getTypePath(comptime self: TypeStore, comptime T: type) []const u8 {
        inline for (self.paths) |ts| {
            if (T == ts.T) return ts.path;
        }

        @compileError("Could not find type path for type " ++ @typeName(T));
    }

    pub fn getTypeName(comptime self: TypeStore, comptime T: type) []const u8 {
        inline for (self.paths) |ts| {
            if (T == ts.T) return ts.name;
        }

        @compileError("Could not find type path for type " ++ @typeName(T));
    }
};

const AssignmentState = struct {
    is_class: bool = false,
    is_object: bool = false,
};

pub const BindingGenerator = struct {
    stream: Stream,
    state: AssignmentState = .{},

    pub fn init(writer: std.fs.File.Writer) BindingGenerator {
        return .{
            .stream = .{
                .indent_delta = 4,
                .underlying_writer = writer,
            },
        };
    }

    pub fn generate(self: *BindingGenerator, comptime T: type) !void {
        comptime var store = TypeStore{};
        comptime store.resolveType(T);

        try self.emitDeclaration(store, comptime store.getTypeName(T), T);
        try self.stream.insertNewline();
    }

    fn jsTypeOf(comptime store: TypeStore, comptime T: type) []const u8 {
        return switch (T) {
            u8, i8, u16, i16, u32, i32, f32, f64 => "number",
            u64, i64 => "BigInt",
            bool => "boolean",
            else => store.getTypePath(T),
        };
    }

    fn emitAny(self: *BindingGenerator, comptime store: TypeStore, value: anytype) !void {
        const writer = self.stream.writer();

        const T = @TypeOf(value);
        const info = @typeInfo(T);

        switch (T) {
            type => try self.emitType(store, value),
            []const u8 => try self.emitString(value),
            else => switch (info) {
                .Int, .ComptimeInt, .Float, .ComptimeFloat => {
                    try self.emitNumber(value);
                },
                .Bool => {
                    try self.emitBoolean(value);
                },
                .Fn => try writer.writeAll("() => new Error('Functions not implemented')"),
                else => |e| @compileError("bindings for type " ++ @tagName(e) ++ " not implemented"),
            },
        }
    }

    fn emitType(self: *BindingGenerator, comptime store: TypeStore, comptime T: type) !void {
        const info = @typeInfo(T);

        switch (info) {
            .Struct => |s_info| {
                if (s_info.fields.len == 0) {
                    try self.emitNamespace(store, T);
                } else {
                    if (s_info.layout != .Extern) @compileError("cannot bind non-extern struct: " ++ @typeName(T));

                    try self.emitStruct(store, T);
                }
            },
            .Enum => try self.emitEnum(store, T),
            else => @compileError("cannot emit type: " ++ @typeName(T)),
        }
    }

    fn emitNumber(self: *BindingGenerator, value: anytype) !void {
        const writer = self.stream.writer();

        try writer.print("{d}", .{value});
    }

    fn emitBoolean(self: *BindingGenerator, value: bool) !void {
        const writer = self.stream.writer();

        try writer.print("{}", .{value});
    }

    fn emitString(self: *BindingGenerator, value: []const u8) !void {
        const writer = self.stream.writer();

        try writer.print("\"{}\"", .{std.zig.fmtEscapes(value)});
    }

    fn emitDeclaration(self: *BindingGenerator, comptime store: TypeStore, comptime name: []const u8, value: anytype) !void {
        const writer = self.stream.writer();

        std.log.debug("Generating declaration: {s}...", .{name});

        if (self.state.is_class) {
            try writer.writeAll("static " ++ name ++ " = ");
        } else if (self.state.is_object) {
            try writer.writeAll(name ++ ": ");
        } else {
            try writer.writeAll("const " ++ name ++ " = ");
        }

        try self.emitAny(store, value);

        if (self.state.is_object) {
            try writer.writeAll(",");
        } else {
            try writer.writeAll(";");
        }
    }

    fn emitDeclarations(self: *BindingGenerator, comptime store: TypeStore, comptime T: type) !void {
        inline for (std.meta.declarations(T)) |decl| {
            if (decl.is_pub) {
                try self.emitDeclaration(store, decl.name, @field(T, decl.name));
                try self.stream.insertNewline();
            }
        }
    }

    fn emitEnum(self: *BindingGenerator, comptime store: TypeStore, comptime T: type) !void {
        const writer = self.stream.writer();

        const name = comptime store.getTypeName(T);

        std.log.debug("Generating enum: {s}...", .{name});

        try self.stream.insertNewline();
        self.stream.pushIndent();

        try writer.writeAll("/** @alias " ++ store.getTypePath(T) ++ " */");
        try self.stream.insertNewline();

        try writer.writeAll("class " ++ name ++ " extends Enum {");
        try self.stream.insertNewline();
        self.stream.pushIndent();

        const previous_state = self.state;
        self.state = .{ .is_class = true };
        defer self.state = previous_state;

        try self.emitDeclaration(store, "__size", @sizeOf(T));
        try self.stream.insertNewline();

        try self.emitDeclarations(store, T);
        try self.stream.insertNewline();

        inline for (std.meta.fields(T)) |field| {
            try writer.print("static {s} = createEnumValue(" ++ name ++ ", {d});", .{ field.name, field.value });
            try self.stream.insertNewline();
        }

        try self.stream.insertNewline();
        try writer.print("/** @returns {{{s}}} */\n", .{name});
        _ = try writer.writeAll("static from(value) {\n");
        self.stream.pushIndent();
        _ = try writer.writeAll("return super.from(value);\n");
        self.stream.popIndent();
        _ = try writer.writeAll("}\n\n");

        _ = try writer.writeAll("static decode(view, offset = 0) {\n");
        self.stream.pushIndent();
        try writer.print("return this.from(view.getUint{d}(offset, true));\n", .{@sizeOf(T) * 8});
        self.stream.popIndent();
        _ = try writer.writeAll("}\n\n");

        _ = try writer.writeAll("encode(view, offset = 0) {\n");
        self.stream.pushIndent();
        try writer.print("view.setUint{d}(offset, this.value, true);\n", .{@sizeOf(T) * 8});
        self.stream.popIndent();
        _ = try writer.writeAll("}\n");

        self.stream.popIndent();
        try writer.writeAll("}");

        self.stream.popIndent();
    }

    fn emitStruct(self: *BindingGenerator, comptime store: TypeStore, comptime T: type) !void {
        const writer = self.stream.writer();

        const name = comptime store.getTypeName(T);

        std.log.debug("Generating struct: {s}...", .{name});

        try self.stream.insertNewline();
        self.stream.pushIndent();

        try writer.writeAll("/** @alias " ++ store.getTypePath(T) ++ " */");
        try self.stream.insertNewline();

        try writer.writeAll("class " ++ name ++ " extends Struct {");
        try self.stream.insertNewline();
        self.stream.pushIndent();

        const previous_state = self.state;
        self.state = .{ .is_class = true };
        defer self.state = previous_state;

        try self.emitDeclaration(store, "__size", @sizeOf(T));
        try self.stream.insertNewline();

        try self.emitDeclarations(store, T);
        try self.stream.insertNewline();

        inline for (std.meta.fields(T)) |field| {
            try writer.print("/** {s} */", .{@typeName(field.field_type)});
            try self.stream.insertNewline();

            try writer.print("{s} = ", .{field.name});
            try self.emitUndefinedInit(store, field.field_type);
            try writer.writeAll(";");
            try self.stream.insertNewline();
            try self.stream.insertNewline();
        }

        try self.emitStructDecode(store, T);
        try self.stream.insertNewline();

        try self.emitStructEncode(store, T);

        self.stream.popIndent();
        try writer.writeAll("}");

        self.stream.popIndent();
    }

    fn emitUndefinedInit(self: *BindingGenerator, comptime store: TypeStore, comptime T: type) !void {
        const writer = self.stream.writer();

        const Int = std.meta.Int(.unsigned, @sizeOf(T) * 8);
        const aaaa = @bitCast(Int, [1]u8{0xaa} ** @sizeOf(T));
        switch (@typeInfo(T)) {
            .Int, .Float => try writer.print("0x{x}", .{aaaa}),
            .Bool => try writer.writeAll("false"),
            .Enum => try writer.print(store.getTypePath(T) ++ ".from(0x{x})", .{aaaa}),
            .Struct => try writer.writeAll("new " ++ store.getTypePath(T) ++ "()"),
            else => |e| @compileError("initialization not implemented for: " ++ @tagName(e)),
        }
    }

    fn emitStructEncode(self: *BindingGenerator, comptime store: TypeStore, comptime T: type) !void {
        const writer = self.stream.writer();

        try writer.writeAll("/** Encodes a {@link " ++ store.getTypeName(T) ++ "}");
        try self.stream.insertNewline();

        try writer.writeAll(" * @param {DataView} view DataView representing WASM memory");
        try self.stream.insertNewline();

        try writer.writeAll(" * @param {number} offset The offset at which the struct starts");
        try self.stream.insertNewline();

        try writer.writeAll(" */");
        try self.stream.insertNewline();

        try writer.writeAll("encode(view, offset = 0) {");
        try self.stream.insertNewline();
        self.stream.pushIndent();

        inline for (std.meta.fields(T)) |field| {
            const field_info = @typeInfo(field.field_type);

            const offset = comptime blk: {
                if (@offsetOf(T, field.name) == 0) {
                    break :blk "offset";
                } else {
                    break :blk std.fmt.comptimePrint("offset + {d}", .{@offsetOf(T, field.name)});
                }
            };

            switch (field_info) {
                .Int => |info| {
                    // TODO: figure out how to calculate where padding will be
                    // const bits = getBitCount(int.bits);

                    switch (info.bits) {
                        0 => {},
                        8 => switch (info.signedness) {
                            .signed => try writer.print("view.setInt8(" ++ offset ++ ", this.{s});", .{field.name}),
                            .unsigned => try writer.print("view.setUint8(" ++ offset ++ ", this.{s});", .{field.name}),
                        },
                        16 => switch (info.signedness) {
                            .signed => try writer.print("view.setInt16(" ++ offset ++ ", this.{s}, true);", .{field.name}),
                            .unsigned => try writer.print("view.setUint16(" ++ offset ++ ", this.{s}, true);", .{field.name}),
                        },
                        32 => switch (info.signedness) {
                            .signed => try writer.print("view.setInt32(" ++ offset ++ ", this.{s}, true);", .{field.name}),
                            .unsigned => try writer.print("view.setUint32(" ++ offset ++ ", this.{s}, true);", .{field.name}),
                        },
                        64 => switch (info.signedness) {
                            .signed => try writer.print("view.setBigInt8(" ++ offset ++ ", this.{s}, true);", .{field.name}),
                            .unsigned => try writer.print("view.setBigUint64(" ++ offset ++ ", this.{s}, true);", .{field.name}),
                        },
                        else => @compileError("unsupported integer size"),
                    }
                },
                .Float => |info| {
                    switch (info.bits) {
                        32 => try writer.print("view.setFloat32(" ++ offset ++ ", this.{s});", .{field.name}),
                        64 => try writer.print("view.setFloat64(" ++ offset ++ ", this.{s});", .{field.name}),
                        else => @compileError("unsupported float size"),
                    }
                },
                .Bool => try writer.print("view.setUint8(" ++ offset ++ ", this.{s} === true ? 1 : 0);", .{field.name}),
                .Enum, .Struct => {
                    if (@bitSizeOf(T) > 0) try writer.print("this.{s}.encode(view, " ++ offset ++ ");", .{field.name});
                },
                else => @compileError("cannot encode: " ++ @typeName(T)),
            }

            try self.stream.insertNewline();
        }

        self.stream.popIndent();
        try writer.writeAll("}");
        try self.stream.insertNewline();
    }

    fn emitStructDecode(self: *BindingGenerator, comptime store: TypeStore, comptime T: type) !void {
        const writer = self.stream.writer();

        try writer.writeAll("/** Decodes a {@link " ++ store.getTypeName(T) ++ "}");
        try self.stream.insertNewline();

        try writer.writeAll(" * @param {DataView} view DataView representing WASM memory");
        try self.stream.insertNewline();

        try writer.writeAll(" * @param {number} offset The offset at which the struct starts");
        try self.stream.insertNewline();

        try writer.writeAll(" * @returns {" ++ store.getTypeName(T) ++ "}");
        try self.stream.insertNewline();

        try writer.writeAll(" */");
        try self.stream.insertNewline();

        try writer.writeAll("static decode(view, offset = 0) {");
        try self.stream.insertNewline();
        self.stream.pushIndent();

        try writer.writeAll("let obj = new this();");
        try self.stream.insertNewline();

        inline for (std.meta.fields(T)) |field| {
            const field_info = @typeInfo(field.field_type);

            const offset = comptime blk: {
                if (@offsetOf(T, field.name) == 0) {
                    break :blk "offset";
                } else {
                    break :blk std.fmt.comptimePrint("offset + {d}", .{@offsetOf(T, field.name)});
                }
            };

            try writer.print("obj.{s} = ", .{field.name});

            switch (field_info) {
                .Int => |info| {
                    // TODO: figure out how to calculate where padding will be
                    // const bits = getBitCount(int.bits);

                    switch (info.bits) {
                        0 => {},
                        8 => switch (info.signedness) {
                            .signed => try writer.writeAll("view.getInt8(" ++ offset ++ ");"),
                            .unsigned => try writer.writeAll("view.getUint8(" ++ offset ++ ");"),
                        },
                        16 => switch (info.signedness) {
                            .signed => try writer.writeAll("view.getInt16(" ++ offset ++ ", true);"),
                            .unsigned => try writer.writeAll("view.getUint16(" ++ offset ++ ", true);"),
                        },
                        32 => switch (info.signedness) {
                            .signed => try writer.writeAll("view.getInt32(" ++ offset ++ ", true);"),
                            .unsigned => try writer.writeAll("view.getUint32(" ++ offset ++ ", true);"),
                        },
                        64 => switch (info.signedness) {
                            .signed => try writer.writeAll("view.getBigInt8(" ++ offset ++ ", true);"),
                            .unsigned => try writer.writeAll("view.getBigUint64(" ++ offset ++ ", true);"),
                        },
                        else => @compileError("unsupported integer size"),
                    }
                },
                .Float => |info| {
                    switch (info.bits) {
                        32 => try writer.writeAll("view.getFloat32(" ++ offset ++ ");"),
                        64 => try writer.writeAll("view.getFloat64(" ++ offset ++ ");"),
                        else => @compileError("unsupported float size"),
                    }
                },
                .Bool => try writer.writeAll("view.getUint8(" ++ offset ++ ") !== 0;"),
                .Enum, .Struct => {
                    if (@bitSizeOf(T) > 0) try writer.print("{s}.decode(view, " ++ offset ++ ");", .{store.getTypePath(field.field_type)});
                },
                else => @compileError("cannot decode: " ++ @typeName(T)),
            }

            try self.stream.insertNewline();
        }

        try writer.writeAll("return obj;");
        try self.stream.insertNewline();

        self.stream.popIndent();
        try writer.writeAll("}");
        try self.stream.insertNewline();
    }

    fn emitNamespace(self: *BindingGenerator, comptime store: TypeStore, comptime T: type) !void {
        const writer = self.stream.writer();

        std.log.debug("Generating namespace: {s}...", .{comptime store.getTypeName(T)});

        try writer.writeAll("{");
        try self.stream.insertNewline();
        self.stream.pushIndent();

        const previous_state = self.state;
        self.state = .{ .is_object = true };
        defer self.state = previous_state;

        try self.emitDeclarations(store, T);

        self.stream.popIndent();
        try writer.writeAll("}");
    }
};
