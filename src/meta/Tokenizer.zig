const Tokenizer = @This();

const std = @import("std");

pub const Token = struct {
    tag: Tag,
    loc: Range,

    pub const Range = struct {
        start: usize,
        end: usize,
    };

    pub const keywords = std.ComptimeStringMap(Tag, .{
        .{ "struct", .keyword_struct },
    });

    pub fn getKeyword(bytes: []const u8) ?Tag {
        return keywords.get(bytes);
    }

    pub const Tag = enum {
        invalid,
        identifier,
        string_literal,
        eof,
        annotation,
        l_paren,
        r_paren,
        semicolon,
        comma,
        colon,
        l_brace,
        r_brace,
        l_bracket,
        r_bracket,
        number_literal,
        doc_comment,
        container_doc_comment,
        slash,

        keyword_struct,
    };
};

buffer: [:0]const u8,
index: usize,
pending_invalid_token: ?Token,

/// For debugging purposes
pub fn dump(self: *Tokenizer, token: *const Token) void {
    std.debug.print("{s} \"{s}\"\n", .{ @tagName(token.tag), self.buffer[token.loc.start..token.loc.end] });
}

pub fn init(buffer: [:0]const u8) Tokenizer {
    // Skip the UTF-8 BOM if present
    const src_start: usize = if (std.mem.startsWith(u8, buffer, "\xEF\xBB\xBF")) 3 else 0;
    return Tokenizer{
        .buffer = buffer,
        .index = src_start,
        .pending_invalid_token = null,
    };
}

const State = enum {
    start,
    identifier,
    annotation,
    string_literal,
    slash,
    line_comment_start,
    line_comment,
    doc_comment_start,
    doc_comment,
    int,
    int_exponent,
    int_period,
    float,
    float_exponent,
    saw_at_sign,
    string_literal_backslash,
};

pub fn next(self: *Tokenizer) Token {
    if (self.pending_invalid_token) |token| {
        self.pending_invalid_token = null;
        return token;
    }
    var state: State = .start;
    var result = Token{
        .tag = .eof,
        .loc = .{
            .start = self.index,
            .end = undefined,
        },
    };

    while (true) : (self.index += 1) {
        const c = self.buffer[self.index];
        switch (state) {
            .start => switch (c) {
                0 => {
                    if (self.index != self.buffer.len) {
                        result.tag = .invalid;
                        result.loc.start = self.index;
                        self.index += 1;
                        result.loc.end = self.index;
                        return result;
                    }
                    break;
                },
                ' ', '\n', '\t', '\r' => {
                    result.loc.start = self.index + 1;
                },
                '"' => {
                    state = .string_literal;
                    result.tag = .string_literal;
                },
                'a'...'z', 'A'...'Z', '_' => {
                    state = .identifier;
                    result.tag = .identifier;
                },
                '@' => {
                    state = .saw_at_sign;
                },
                '(' => {
                    result.tag = .l_paren;
                    self.index += 1;
                    break;
                },
                ')' => {
                    result.tag = .r_paren;
                    self.index += 1;
                    break;
                },
                '[' => {
                    result.tag = .l_bracket;
                    self.index += 1;
                    break;
                },
                ']' => {
                    result.tag = .r_bracket;
                    self.index += 1;
                    break;
                },
                ';' => {
                    result.tag = .semicolon;
                    self.index += 1;
                    break;
                },
                ',' => {
                    result.tag = .comma;
                    self.index += 1;
                    break;
                },
                ':' => {
                    result.tag = .colon;
                    self.index += 1;
                    break;
                },
                '{' => {
                    result.tag = .l_brace;
                    self.index += 1;
                    break;
                },
                '}' => {
                    result.tag = .r_brace;
                    self.index += 1;
                    break;
                },
                '/' => {
                    state = .slash;
                },
                '0'...'9' => {
                    state = .int;
                    result.tag = .number_literal;
                },
                else => {
                    result.tag = .invalid;
                    result.loc.end = self.index;
                    self.index += 1;
                    return result;
                },
            },

            .saw_at_sign => switch (c) {
                '"' => {
                    result.tag = .identifier;
                    state = .string_literal;
                },
                'a'...'z', 'A'...'Z', '_' => {
                    state = .annotation;
                    result.tag = .annotation;
                },
                else => {
                    result.tag = .invalid;
                    break;
                },
            },

            .identifier => switch (c) {
                'a'...'z', 'A'...'Z', '_', '0'...'9' => {},
                else => {
                    if (Token.getKeyword(self.buffer[result.loc.start..self.index])) |tag| {
                        result.tag = tag;
                    }
                    break;
                },
            },
            .annotation => switch (c) {
                'a'...'z', 'A'...'Z', '_', '0'...'9' => {},
                else => break,
            },
            .string_literal => switch (c) {
                '\\' => {
                    state = .string_literal_backslash;
                },
                '"' => {
                    self.index += 1;
                    break;
                },
                0 => {
                    if (self.index == self.buffer.len) {
                        break;
                    } else {
                        self.checkLiteralCharacter();
                    }
                },
                '\n' => {
                    result.tag = .invalid;
                    break;
                },
                else => self.checkLiteralCharacter(),
            },

            .string_literal_backslash => switch (c) {
                0, '\n' => {
                    result.tag = .invalid;
                    break;
                },
                else => {
                    state = .string_literal;
                },
            },

            .slash => switch (c) {
                '/' => {
                    state = .line_comment_start;
                },
                else => {
                    result.tag = .slash;
                    break;
                },
            },
            .line_comment_start => switch (c) {
                0 => {
                    if (self.index != self.buffer.len) {
                        result.tag = .invalid;
                        self.index += 1;
                    }
                    break;
                },
                '/' => {
                    state = .doc_comment_start;
                },
                '!' => {
                    result.tag = .container_doc_comment;
                    state = .doc_comment;
                },
                '\n' => {
                    state = .start;
                    result.loc.start = self.index + 1;
                },
                '\t', '\r' => state = .line_comment,
                else => {
                    state = .line_comment;
                    self.checkLiteralCharacter();
                },
            },
            .doc_comment_start => switch (c) {
                '/' => {
                    state = .line_comment;
                },
                0, '\n' => {
                    result.tag = .doc_comment;
                    break;
                },
                '\t', '\r' => {
                    state = .doc_comment;
                    result.tag = .doc_comment;
                },
                else => {
                    state = .doc_comment;
                    result.tag = .doc_comment;
                    self.checkLiteralCharacter();
                },
            },
            .line_comment => switch (c) {
                0 => {
                    if (self.index != self.buffer.len) {
                        result.tag = .invalid;
                        self.index += 1;
                    }
                    break;
                },
                '\n' => {
                    state = .start;
                    result.loc.start = self.index + 1;
                },
                '\t', '\r' => {},
                else => self.checkLiteralCharacter(),
            },
            .doc_comment => switch (c) {
                0, '\n' => break,
                '\t', '\r' => {},
                else => self.checkLiteralCharacter(),
            },
            .int => switch (c) {
                '.' => state = .int_period,
                '_', 'a'...'d', 'f'...'o', 'q'...'z', 'A'...'D', 'F'...'O', 'Q'...'Z', '0'...'9' => {},
                'e', 'E', 'p', 'P' => state = .int_exponent,
                else => break,
            },
            .int_exponent => switch (c) {
                '-', '+' => {
                    state = .float;
                },
                else => {
                    self.index -= 1;
                    state = .int;
                },
            },
            .int_period => switch (c) {
                '_', 'a'...'d', 'f'...'o', 'q'...'z', 'A'...'D', 'F'...'O', 'Q'...'Z', '0'...'9' => {
                    state = .float;
                },
                'e', 'E', 'p', 'P' => state = .float_exponent,
                else => {
                    self.index -= 1;
                    break;
                },
            },
            .float => switch (c) {
                '_', 'a'...'d', 'f'...'o', 'q'...'z', 'A'...'D', 'F'...'O', 'Q'...'Z', '0'...'9' => {},
                'e', 'E', 'p', 'P' => state = .float_exponent,
                else => break,
            },
            .float_exponent => switch (c) {
                '-', '+' => state = .float,
                else => {
                    self.index -= 1;
                    state = .float;
                },
            },
        }
    }

    if (result.tag == .eof) {
        if (self.pending_invalid_token) |token| {
            self.pending_invalid_token = null;
            return token;
        }
        result.loc.start = self.index;
    }

    result.loc.end = self.index;
    return result;
}

fn checkLiteralCharacter(self: *Tokenizer) void {
    if (self.pending_invalid_token != null) return;
    const invalid_length = self.getInvalidCharacterLength();
    if (invalid_length == 0) return;
    self.pending_invalid_token = .{
        .tag = .invalid,
        .loc = .{
            .start = self.index,
            .end = self.index + invalid_length,
        },
    };
}

fn getInvalidCharacterLength(self: *Tokenizer) u3 {
    const c0 = self.buffer[self.index];
    if (std.ascii.isASCII(c0)) {
        if (std.ascii.isControl(c0)) {
            // ascii control codes are never allowed
            // (note that \n was checked before we got here)
            return 1;
        }
        // looks fine to me.
        return 0;
    } else {
        // check utf8-encoded character.
        const length = std.unicode.utf8ByteSequenceLength(c0) catch return 1;
        if (self.index + length > self.buffer.len) {
            return @intCast(u3, self.buffer.len - self.index);
        }
        const bytes = self.buffer[self.index .. self.index + length];
        switch (length) {
            2 => {
                const value = std.unicode.utf8Decode2(bytes) catch return length;
                if (value == 0x85) return length; // U+0085 (NEL)
            },
            3 => {
                const value = std.unicode.utf8Decode3(bytes) catch return length;
                if (value == 0x2028) return length; // U+2028 (LS)
                if (value == 0x2029) return length; // U+2029 (PS)
            },
            4 => {
                _ = std.unicode.utf8Decode4(bytes) catch return length;
            },
            else => unreachable,
        }
        self.index += length - 1;
        return 0;
    }
}
