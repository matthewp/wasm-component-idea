const std = @import("std");

// Host imports — namespaced to avoid collisions with public API.
const host = struct {
    extern "host" fn open_element(ptr: [*]const u8, len: u32) void;
    extern "host" fn close_element() void;
    extern "host" fn attribute(np: [*]const u8, nl: u32, vp: [*]const u8, vl: u32) void;
    extern "host" fn on_event(tp: [*]const u8, tl: u32, np: [*]const u8, nl: u32) void;
    extern "host" fn text(ptr: [*]const u8, len: u32) void;
    extern "host" fn create_template(id: u32) void;
    extern "host" fn slot() void;
    extern "host" fn end_template() void;
    extern "host" fn update(id: u32) void;
    extern "host" fn value(ptr: [*]const u8, len: u32) void;
    extern "host" fn commit() void;
    extern "host" fn event_target_value(buf: [*]u8, buf_len: u32) u32;
};

// --- Comptime HTML parser ---

const Tag = enum { open, close, attr, event, txt, slot_marker };

const Inst = struct {
    tag: Tag,
    a: []const u8 = "",
    b: []const u8 = "",
};

fn isWs(c: u8) bool {
    return c == ' ' or c == '\n' or c == '\r' or c == '\t';
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
                out = out ++ &[_]Inst{.{ .tag = .open, .a = src[ts..i] }};

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

// --- Int-to-string helper ---

var itoa_buf: [20]u8 = undefined;

fn intToValue(n: i32) void {
    var v: u32 = if (n < 0) @intCast(-n) else @intCast(n);
    var pos: usize = itoa_buf.len;

    if (v == 0) {
        pos -= 1;
        itoa_buf[pos] = '0';
    } else {
        while (v > 0) {
            pos -= 1;
            itoa_buf[pos] = '0' + @as(u8, @intCast(v % 10));
            v /= 10;
        }
    }
    if (n < 0) {
        pos -= 1;
        itoa_buf[pos] = '-';
    }
    host.value(itoa_buf[pos..].ptr, @intCast(itoa_buf.len - pos));
}

// --- Public API ---

/// Read the current event's target.value into the provided buffer.
/// Returns the number of bytes written.
pub fn eventTargetValue(buf: [*]u8, len: u32) u32 {
    return host.event_target_value(buf, len);
}

/// Parse an HTML template at compile time. Returns a type with an `update`
/// method that registers the template on first call, then patches slot values.
pub fn html(comptime template: []const u8) type {
    const instrs = comptime parseHtml(template);

    return struct {
        var defined: bool = false;

        pub fn update(values: anytype) void {
            if (!defined) {
                defined = true;
                host.create_template(0);
                inline for (instrs) |ins| {
                    switch (ins.tag) {
                        .open => host.open_element(ins.a.ptr, @intCast(ins.a.len)),
                        .close => host.close_element(),
                        .attr => host.attribute(
                            ins.a.ptr,
                            @intCast(ins.a.len),
                            ins.b.ptr,
                            @intCast(ins.b.len),
                        ),
                        .event => host.on_event(
                            ins.a.ptr,
                            @intCast(ins.a.len),
                            ins.b.ptr,
                            @intCast(ins.b.len),
                        ),
                        .txt => host.text(ins.a.ptr, @intCast(ins.a.len)),
                        .slot_marker => host.slot(),
                    }
                }
                host.end_template();
            }

            host.update(0);
            const info = @typeInfo(@TypeOf(values));
            inline for (info.@"struct".fields) |field| {
                emitValue(@field(values, field.name));
            }
            host.commit();
        }

        fn emitValue(val: anytype) void {
            const T = @TypeOf(val);
            if (T == i32) {
                intToValue(val);
            } else if (T == []const u8 or T == []u8) {
                host.value(@ptrCast(val.ptr), @intCast(val.len));
            } else {
                @compileError("unsupported slot value type");
            }
        }
    };
}
