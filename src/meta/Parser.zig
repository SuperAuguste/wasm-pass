//! Parser for wasm-pass language

const Parser = @This();

const std = @import("std");
const Tokenizer = @import("Tokenizer.zig");
const Token = Tokenizer.Token;

// TODO: proper error handling

allocator: std.mem.Allocator,
buffer: [:0]const u8,
tokens: Tokens,

pub const Node = union(enum) {
    root: Root,
    identifier: Identifier,
    annotation: Annotation,
    @"struct": Struct,

    // complex types
    array: Array,

    pub fn parseType(parser: *Parser) !Node {
        return switch (parser.tokens.peek().tag) {
            .identifier => Identifier.parse(parser),
            .l_bracket => Array.parse(parser),
            else => error.Invalid,
        };
    }

    pub const Root = struct {
        children: []const Node,

        pub fn parse(parser: *Parser) !Node {
            var children = std.ArrayListUnmanaged(Node){};

            while (parser.tokens.peek().tag != .eof) {
                var annotations = try Annotation.parseAny(parser);

                try children.append(parser.allocator, switch (parser.tokens.peek().tag) {
                    .keyword_struct => try Struct.parse(parser, annotations),
                    else => {
                        std.log.err("{any}", .{parser.tokens.peek().tag});
                        @panic("bruh");
                    },
                });
            }

            return .{
                .root = .{
                    .children = try children.toOwnedSlice(parser.allocator),
                },
            };
        }
    };

    pub const Identifier = struct {
        value: []const u8,

        pub fn parse(parser: *Parser) !Node {
            const id_tok = parser.tokens.next();
            if (id_tok.tag != .identifier) return error.Invalid;
            return .{
                .identifier = .{
                    .value = parser.slice(id_tok),
                },
            };
        }
    };

    pub const Annotation = struct {
        kind: Kind,
        arguments: []const Node,

        pub const Kind = enum {
            creatable,
            snapshot,
            read_only,
            get_errors,
            set_errors,
        };

        pub fn parseAny(parser: *Parser) ![]const Annotation {
            var annotations = std.ArrayListUnmanaged(Annotation){};

            while (parser.tokens.peek().tag == .annotation) {
                const anno_tok = parser.tokens.next();
                const kind = std.meta.stringToEnum(Kind, parser.getName(anno_tok).?) orelse return error.UnknownAnnotation;

                if (parser.tokens.next().tag != .l_paren) return error.Invalid;

                switch (kind) {
                    .creatable, .snapshot, .read_only => {
                        // Args should be empty
                        try annotations.append(parser.allocator, .{
                            .kind = kind,
                            .arguments = &.{},
                        });
                    },
                    .get_errors, .set_errors => {
                        var errors = std.ArrayListUnmanaged(Node){};

                        while (parser.tokens.peek().tag != .r_paren) {
                            try errors.append(parser.allocator, try Identifier.parse(parser));
                            if (parser.tokens.peek().tag == .comma) _ = parser.tokens.next();
                        }

                        try annotations.append(parser.allocator, .{
                            .kind = kind,
                            .arguments = try errors.toOwnedSlice(parser.allocator),
                        });
                    },
                }

                if (parser.tokens.next().tag != .r_paren) return error.Invalid;
                if (parser.tokens.next().tag != .semicolon) return error.Invalid;
            }

            return annotations.toOwnedSlice(parser.allocator);
        }
    };

    pub const Struct = struct {
        name: []const u8,
        annotations: []const Annotation,
        fields: []const Field,

        pub const Field = struct {
            name: []const u8,
            annotations: []const Annotation,
            type: Node,
        };

        pub fn parse(parser: *Parser, annotations: []const Annotation) !Node {
            if (parser.tokens.next().tag != .keyword_struct) return error.Invalid;

            const name_tok = parser.tokens.next();
            if (name_tok.tag != .identifier) return error.Invalid;
            const name = parser.slice(name_tok);

            if (parser.tokens.next().tag != .l_brace) return error.Invalid;

            var fields = std.ArrayListUnmanaged(Field){};

            while (parser.tokens.peek().tag != .r_brace) {
                var field_annotations = try Annotation.parseAny(parser);

                const field_name_tok = parser.tokens.next();
                if (field_name_tok.tag != .identifier) return error.Invalid;
                const field_name = parser.slice(field_name_tok);

                if (parser.tokens.next().tag != .colon) return error.Invalid;

                try fields.append(parser.allocator, .{
                    .name = field_name,
                    .annotations = field_annotations,
                    .type = try Node.parseType(parser),
                });

                if (parser.tokens.next().tag != .comma) return error.Invalid;
            }

            _ = parser.tokens.next();
            if (parser.tokens.next().tag != .semicolon) return error.Invalid;

            return .{
                .@"struct" = .{
                    .name = name,
                    .annotations = annotations,
                    .fields = try fields.toOwnedSlice(parser.allocator),
                },
            };
        }
    };

    pub const Array = struct {
        size: u16,
        type: *Node,

        pub fn parse(parser: *Parser) !Node {
            if (parser.tokens.next().tag != .l_bracket) return error.Invalid;
            var size_tok = parser.tokens.next();
            if (size_tok.tag != .number_literal) return error.Invalid;
            if (parser.tokens.next().tag != .r_bracket) return error.Invalid;

            return .{
                .array = .{
                    .size = std.fmt.parseInt(u16, parser.slice(size_tok), 10) catch return error.Invalid,
                    .type = t: {
                        var node = try parser.allocator.create(Node);
                        node.* = try Node.parseType(parser);
                        break :t node;
                    },
                },
            };
        }
    };

    pub fn writeName(node: Node, writer: anytype) !void {
        switch (node) {
            .identifier => |id| try writer.writeAll(id.value),
            .array => |arr| {
                try writer.print("[{d}]", .{arr.size});
                try arr.type.writeName(writer);
            },
            else => @panic("no"),
        }
    }

    pub fn format(value: Node, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        return formatInternal(value, writer, 0);
    }

    pub fn formatInternal(value: Node, writer: anytype, indent: usize) !void {
        switch (value) {
            .root => |root| {
                try writer.writeByteNTimes(' ', indent * 4);
                try writer.writeAll("root\n");

                for (root.children) |child| {
                    try child.formatInternal(writer, indent + 1);
                }
            },
            .identifier => |id| {
                try writer.writeByteNTimes(' ', indent * 4);
                try writer.print("identifier {s}\n", .{id.value});
            },
            .annotation => |anno| {
                try writer.writeByteNTimes(' ', indent * 4);
                if (anno.arguments.len == 0)
                    try writer.print("@{s}(", .{@tagName(anno.kind)})
                else
                    try writer.print("@{s}(\n", .{@tagName(anno.kind)});

                for (anno.arguments) |arg| {
                    try arg.formatInternal(writer, indent + 1);
                }

                if (anno.arguments.len != 0)
                    try writer.writeByteNTimes(' ', indent * 4);
                try writer.writeAll(")\n");
            },
            .@"struct" => |@"struct"| {
                try writer.writeByteNTimes(' ', indent * 4);
                try writer.print("struct {s}\n", .{@"struct".name});

                for (@"struct".annotations) |anno| {
                    try formatInternal(.{ .annotation = anno }, writer, indent + 1);
                }

                for (@"struct".fields) |field| {
                    try writer.writeByteNTimes(' ', (indent + 1) * 4);
                    try writer.print("{s}: ", .{field.name});
                    try field.type.writeName(writer);
                    try writer.writeAll("\n");

                    for (field.annotations) |anno| {
                        try formatInternal(.{ .annotation = anno }, writer, indent + 2);
                    }
                }
            },
            else => try value.writeName(writer),
        }
    }
};

pub const Tokens = struct {
    index: usize,
    items: []const Token,

    pub fn peek(tokens: Tokens) Token {
        return tokens.items[tokens.index];
    }

    pub fn next(tokens: *Tokens) Token {
        const curr = tokens.items[tokens.index];
        tokens.index += 1;
        return curr;
    }
};

pub const Save = struct {
    tokens: *Tokens,
    index: usize,

    pub fn restore(s: Save) void {
        s.tokens.index = s.index;
    }
};

pub fn save(parser: Parser) Save {
    return Save{ .tokens = parser.tokens, .index = parser.tokens.index };
}

pub fn parse(allocator: std.mem.Allocator, buffer: [:0]const u8) !Node {
    var tokenizer = Tokenizer.init(buffer);

    var tokens_list = std.ArrayListUnmanaged(Token){};

    while (true) {
        const token = tokenizer.next();
        try tokens_list.append(allocator, token);

        if (token.tag == .eof) break;
    }

    var tokens = Tokens{ .index = 0, .items = try tokens_list.toOwnedSlice(allocator) };
    var parser = Parser{
        .allocator = allocator,
        .buffer = buffer,
        .tokens = tokens,
    };

    return Node.Root.parse(&parser);
}

fn slice(parser: Parser, token: Token) []const u8 {
    return parser.buffer[token.loc.start..token.loc.end];
}

fn getName(parser: Parser, token: Token) ?[]const u8 {
    return switch (token.tag) {
        .annotation => parser.buffer[token.loc.start + 1 .. token.loc.end],
        else => null,
    };
}
