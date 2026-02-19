const std = @import("std");

// --- Canonical ABI opcode layout ---
// Each opcode is 20 bytes (5 x u32), matching the WIT variant:
//   variant opcode { open(string), close, attr(tuple<string,string>),
//                    text(string), slot(string), event(tuple<string,string>) }
//
// Layout: [tag:u8][pad:3][f0_ptr:u32][f0_len:u32][f1_ptr:u32][f1_len:u32]

pub const Opcode = extern struct {
    tag: u8,
    _pad1: u8 = 0,
    _pad2: u8 = 0,
    _pad3: u8 = 0,
    f0_ptr: u32 = 0,
    f0_len: u32 = 0,
    f1_ptr: u32 = 0,
    f1_len: u32 = 0,
};

pub const OP_OPEN: u8 = 0;
pub const OP_CLOSE: u8 = 1;
pub const OP_ATTR: u8 = 2;
pub const OP_TEXT: u8 = 3;
pub const OP_SLOT: u8 = 4;
pub const OP_EVENT: u8 = 5;
pub const OP_CHILD: u8 = 6;

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

// --- Public API ---

const STR_BUF_SIZE = 20;

/// Parse an HTML template at compile time. Returns a type with an `update`
/// method that fills an opcode array and returns a pointer + length.
pub fn html(comptime template: []const u8) type {
    const instrs = comptime parseHtml(template);

    const opcode_count = comptime blk: {
        var count: usize = 0;
        for (instrs) |_| {
            count += 1;
        }
        break :blk count;
    };

    const slot_count = comptime blk: {
        var count: usize = 0;
        for (instrs) |ins| {
            if (ins.tag == .slot_marker) count += 1;
        }
        break :blk count;
    };

    // Map from slot index to opcode array index
    const slot_positions = comptime blk: {
        var positions: [slot_count]usize = undefined;
        var si: usize = 0;
        for (instrs, 0..) |ins, i| {
            if (ins.tag == .slot_marker) {
                positions[si] = i;
                si += 1;
            }
        }
        break :blk positions;
    };

    return struct {
        var opcodes: [opcode_count]Opcode = undefined;
        var initialized: bool = false;
        var str_bufs: [if (slot_count == 0) 1 else slot_count][STR_BUF_SIZE]u8 = undefined;

        pub fn update(values: anytype) OpcodeList {
            if (!initialized) {
                initialized = true;
                comptime var idx: usize = 0;
                inline for (instrs) |ins| {
                    opcodes[idx] = switch (ins.tag) {
                        .open => Opcode{
                            .tag = OP_OPEN,
                            .f0_ptr = @intFromPtr(ins.a.ptr),
                            .f0_len = @intCast(ins.a.len),
                        },
                        .close => Opcode{ .tag = OP_CLOSE },
                        .attr => Opcode{
                            .tag = OP_ATTR,
                            .f0_ptr = @intFromPtr(ins.a.ptr),
                            .f0_len = @intCast(ins.a.len),
                            .f1_ptr = @intFromPtr(ins.b.ptr),
                            .f1_len = @intCast(ins.b.len),
                        },
                        .txt => Opcode{
                            .tag = OP_TEXT,
                            .f0_ptr = @intFromPtr(ins.a.ptr),
                            .f0_len = @intCast(ins.a.len),
                        },
                        .slot_marker => Opcode{ .tag = OP_SLOT },
                        .event => Opcode{
                            .tag = OP_EVENT,
                            .f0_ptr = @intFromPtr(ins.a.ptr),
                            .f0_len = @intCast(ins.a.len),
                            .f1_ptr = @intFromPtr(ins.b.ptr),
                            .f1_len = @intCast(ins.b.len),
                        },
                        .component => Opcode{
                            .tag = OP_CHILD,
                            .f0_ptr = @intFromPtr(ins.a.ptr),
                            .f0_len = @intCast(ins.a.len),
                        },
                    };
                    idx += 1;
                }
            }

            // Update slot values
            const fields = @typeInfo(@TypeOf(values)).@"struct".fields;
            comptime var si: u32 = 0;
            inline for (fields) |field| {
                writeSlot(slot_positions[si], si, @field(values, field.name));
                si += 1;
            }

            return .{ .ptr = &opcodes, .len = opcode_count };
        }

        fn writeSlot(opcode_idx: usize, slot_idx: u32, val: anytype) void {
            const T = @TypeOf(val);
            if (T == i32) {
                const len = formatInt(&str_bufs[slot_idx], val);
                opcodes[opcode_idx].f0_ptr = @intFromPtr(&str_bufs[slot_idx]);
                opcodes[opcode_idx].f0_len = len;
            } else if (T == []const u8 or T == []u8) {
                opcodes[opcode_idx].f0_ptr = @intFromPtr(val.ptr);
                opcodes[opcode_idx].f0_len = @intCast(val.len);
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

pub const OpcodeList = struct {
    ptr: [*]const Opcode,
    len: usize,
};

// --- Canonical ABI helpers ---

var ret_area: [2]u32 align(4) = undefined;

/// Wrap a render function for canonical ABI export.
/// Returns a pointer to ret_area containing [list_ptr, list_len].
pub fn renderExport(result: OpcodeList) [*]u8 {
    ret_area[0] = @intFromPtr(result.ptr);
    ret_area[1] = @intCast(result.len);
    return @ptrCast(&ret_area);
}

// Bump allocator for cabi_realloc (host-provided string parameters)
var heap: [4096]u8 = undefined;
var heap_pos: usize = 0;

pub fn resetHeap() void {
    heap_pos = 0;
}

export fn cabi_realloc(_: ?[*]u8, _: usize, alignment: usize, new_size: usize) [*]u8 {
    if (new_size == 0) return @ptrFromInt(alignment);
    const mask = alignment - 1;
    const aligned = (heap_pos + mask) & ~mask;
    heap_pos = aligned + new_size;
    return @ptrCast(&heap[aligned]);
}
