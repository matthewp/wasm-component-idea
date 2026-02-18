const std = @import("std");

// Host imports — only needed for reading DOM state back into WASM.
const host = struct {
    extern "host" fn event_target_value(buf: [*]u8, buf_len: u32) u32;
};

// --- Comptime HTML parser ---

const Tag = enum { open, close, attr, event, txt, slot_marker, component };

const Inst = struct {
    tag: Tag,
    a: []const u8 = "",
    b: []const u8 = "",
};

fn isWs(c: u8) bool {
    return c == ' ' or c == '\n' or c == '\r' or c == '\t';
}

fn containsHyphen(comptime s: []const u8) bool {
    for (s) |c| {
        if (c == '-') return true;
    }
    return false;
}

fn parseHtml(comptime src: []const u8) []const Inst {
    comptime {
        var out: []const Inst = &.{};
        var i: usize = 0;

        while (i < src.len) {
            // Close tag: </...>
            if (i + 1 < src.len and src[i] == '<' and src[i + 1] == '/') {
                i += 2;
                while (i < src.len and src[i] != '>') i += 1;
                i += 1;
                out = out ++ &[_]Inst{.{ .tag = .close }};
            }
            // Open tag: <tag ...> or <tag .../>
            else if (src[i] == '<') {
                i += 1;
                const ts = i;
                while (i < src.len and src[i] != ' ' and src[i] != '>' and src[i] != '/') i += 1;
                const tag_name = src[ts..i];

                // Custom elements (hyphenated tags) are components
                if (containsHyphen(tag_name)) {
                    out = out ++ &[_]Inst{.{ .tag = .component, .a = tag_name }};
                    // Skip to end of tag
                    while (i < src.len and src[i] != '>') i += 1;
                    if (i < src.len) i += 1;
                } else {
                    out = out ++ &[_]Inst{.{ .tag = .open, .a = tag_name }};

                    // Attributes
                    while (i < src.len and src[i] != '>' and src[i] != '/') {
                        while (i < src.len and isWs(src[i])) i += 1;
                        if (i < src.len and (src[i] == '>' or src[i] == '/')) break;

                        const ns = i;
                        while (i < src.len and src[i] != '=') i += 1;
                        const name = src[ns..i];
                        i += 1; // skip '='
                        const q = src[i]; // opening quote (' or ")
                        i += 1;
                        const vs = i;
                        while (i < src.len and src[i] != q) i += 1;
                        const val = src[vs..i];
                        i += 1; // closing quote

                        if (std.mem.startsWith(u8, name, "on:")) {
                            out = out ++ &[_]Inst{.{ .tag = .event, .a = name[3..], .b = val }};
                        } else {
                            out = out ++ &[_]Inst{.{ .tag = .attr, .a = name, .b = val }};
                        }
                    }

                    // Self-closing tag? (<input .../>)
                    var self_closing = false;
                    if (i < src.len and src[i] == '/') {
                        self_closing = true;
                        i += 1;
                    }
                    if (i < src.len and src[i] == '>') i += 1;
                    if (self_closing) {
                        out = out ++ &[_]Inst{.{ .tag = .close }};
                    }
                }
            }
            // Dynamic slot: {}
            else if (i + 1 < src.len and src[i] == '{' and src[i + 1] == '}') {
                out = out ++ &[_]Inst{.{ .tag = .slot_marker }};
                i += 2;
            }
            // Text content
            else {
                const s = i;
                while (i < src.len and src[i] != '<' and
                    !(i + 1 < src.len and src[i] == '{' and src[i + 1] == '}')) i += 1;
                const trimmed = std.mem.trim(u8, src[s..i], " \n\r\t");
                if (trimmed.len > 0) {
                    out = out ++ &[_]Inst{.{ .tag = .txt, .a = trimmed }};
                }
            }
        }
        return out;
    }
}

// --- Opcodes ---
// All values are u32 for alignment. Format: opcode followed by arguments.

const OP_OPEN: u32 = 1; // ptr, len
const OP_CLOSE: u32 = 2; // (no args)
const OP_ATTR: u32 = 3; // name_ptr, name_len, val_ptr, val_len
const OP_TEXT: u32 = 4; // ptr, len
const OP_SLOT: u32 = 5; // ptr, len (current value)
const OP_EVENT: u32 = 6; // type_ptr, type_len, handler_ptr, handler_len
const OP_COMPONENT: u32 = 7; // name_ptr, name_len
// 0 = END

const STR_BUF_SIZE = 20;

fn instrSize(tag: Tag) usize {
    return switch (tag) {
        .open => 3,
        .close => 1,
        .attr => 5,
        .txt => 3,
        .slot_marker => 3,
        .event => 5,
        .component => 3,
    };
}

// --- Public API ---

/// Read the current event's target.value into the provided buffer.
/// Returns the number of bytes written.
pub fn eventTargetValue(buf: [*]u8, len: u32) u32 {
    return host.event_target_value(buf, len);
}

/// Parse an HTML template at compile time. Returns a type with an `update`
/// method that writes an opcode buffer and returns a pointer to it.
pub fn html(comptime template: []const u8) type {
    const instrs = comptime parseHtml(template);

    const buf_size = comptime blk: {
        var size: usize = 0;
        for (instrs) |ins| {
            size += instrSize(ins.tag);
        }
        break :blk size + 1; // +1 for END sentinel
    };

    const slot_count = comptime blk: {
        var count: usize = 0;
        for (instrs) |ins| {
            if (ins.tag == .slot_marker) count += 1;
        }
        break :blk count;
    };

    // Precompute the u32 index in buf where each slot's ptr field lives.
    const slot_offsets = comptime blk: {
        var offsets: [slot_count]usize = undefined;
        var pos: usize = 0;
        var si: usize = 0;
        for (instrs) |ins| {
            if (ins.tag == .slot_marker) {
                offsets[si] = pos + 1; // +1 skips the opcode
                si += 1;
            }
            pos += instrSize(ins.tag);
        }
        break :blk offsets;
    };

    return struct {
        var defined: bool = false;
        var buf: [buf_size]u32 = [_]u32{0} ** buf_size;
        var str_bufs: [slot_count][STR_BUF_SIZE]u8 = undefined;

        pub fn update(values: anytype) u32 {
            const fields = @typeInfo(@TypeOf(values)).@"struct".fields;

            if (!defined) {
                defined = true;
                var pos: usize = 0;
                inline for (instrs) |ins| {
                    switch (ins.tag) {
                        .open => {
                            buf[pos] = OP_OPEN;
                            buf[pos + 1] = @intFromPtr(ins.a.ptr);
                            buf[pos + 2] = @intCast(ins.a.len);
                            pos += 3;
                        },
                        .close => {
                            buf[pos] = OP_CLOSE;
                            pos += 1;
                        },
                        .attr => {
                            buf[pos] = OP_ATTR;
                            buf[pos + 1] = @intFromPtr(ins.a.ptr);
                            buf[pos + 2] = @intCast(ins.a.len);
                            buf[pos + 3] = @intFromPtr(ins.b.ptr);
                            buf[pos + 4] = @intCast(ins.b.len);
                            pos += 5;
                        },
                        .txt => {
                            buf[pos] = OP_TEXT;
                            buf[pos + 1] = @intFromPtr(ins.a.ptr);
                            buf[pos + 2] = @intCast(ins.a.len);
                            pos += 3;
                        },
                        .slot_marker => {
                            buf[pos] = OP_SLOT;
                            pos += 3; // ptr and len filled below
                        },
                        .event => {
                            buf[pos] = OP_EVENT;
                            buf[pos + 1] = @intFromPtr(ins.a.ptr);
                            buf[pos + 2] = @intCast(ins.a.len);
                            buf[pos + 3] = @intFromPtr(ins.b.ptr);
                            buf[pos + 4] = @intCast(ins.b.len);
                            pos += 5;
                        },
                        .component => {
                            buf[pos] = OP_COMPONENT;
                            buf[pos + 1] = @intFromPtr(ins.a.ptr);
                            buf[pos + 2] = @intCast(ins.a.len);
                            pos += 3;
                        },
                    }
                }
                // Fill slot values
                var idx: u32 = 0;
                inline for (fields) |field| {
                    writeSlot(slot_offsets[idx], idx, @field(values, field.name));
                    idx += 1;
                }
                buf[pos] = 0; // END
                return @intFromPtr(&buf);
            }

            // Subsequent renders: SLOT and COMPONENT opcodes only
            var pos: usize = 0;
            var idx: u32 = 0;
            inline for (fields) |field| {
                buf[pos] = OP_SLOT;
                writeSlot(pos + 1, idx, @field(values, field.name));
                pos += 3;
                idx += 1;
            }
            inline for (instrs) |ins| {
                if (ins.tag == .component) {
                    buf[pos] = OP_COMPONENT;
                    buf[pos + 1] = @intFromPtr(ins.a.ptr);
                    buf[pos + 2] = @intCast(ins.a.len);
                    pos += 3;
                }
            }
            buf[pos] = 0; // END
            return @intFromPtr(&buf);
        }

        fn writeSlot(off: usize, idx: u32, val: anytype) void {
            const T = @TypeOf(val);
            if (T == i32) {
                const len = formatInt(&str_bufs[idx], val);
                buf[off] = @intFromPtr(&str_bufs[idx]);
                buf[off + 1] = len;
            } else if (T == []const u8 or T == []u8) {
                buf[off] = @intFromPtr(val.ptr);
                buf[off + 1] = @intCast(val.len);
            } else {
                @compileError("unsupported slot value type");
            }
        }

        fn formatInt(b: *[STR_BUF_SIZE]u8, n: i32) u32 {
            var v: u32 = if (n < 0) @intCast(-n) else @intCast(n);
            var start: u32 = 0;
            if (n < 0) {
                b[0] = '-';
                start = 1;
            }
            if (v == 0) {
                b[start] = '0';
                return start + 1;
            }
            var temp = v;
            var digits: u32 = 0;
            while (temp > 0) {
                digits += 1;
                temp /= 10;
            }
            var pos = start + digits;
            while (v > 0) {
                pos -= 1;
                b[pos] = '0' + @as(u8, @intCast(v % 10));
                v /= 10;
            }
            return start + digits;
        }
    };
}
