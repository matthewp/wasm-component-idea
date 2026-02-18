// Benchmark component using the buffer protocol (update_template).
// Single boundary crossing per render: writes all slot data to linear
// memory, then calls update_template(id, bufPtr, count).

const host = struct {
    extern "host" fn create_template(id: u32) void;
    extern "host" fn open_element(ptr: [*]const u8, len: u32) void;
    extern "host" fn close_element() void;
    extern "host" fn slot() void;
    extern "host" fn end_template() void;
    extern "host" fn update_template(template_id: u32, buf_ptr: u32, count: u32) void;
};

const MAX_SLOTS: u32 = 1000;
const STR_BUF_SIZE: u32 = 12;

var slot_count: u32 = 10;
var frame: u32 = 0;

// Per-slot string buffers — all values must exist simultaneously in memory
var str_bufs: [MAX_SLOTS][STR_BUF_SIZE]u8 = undefined;

// Buffer of (ptr, len) u32 pairs for update_template
var pair_buf: [MAX_SLOTS * 2]u32 = undefined;

const span: []const u8 = "span";

export fn set_slot_count(n: u32) void {
    slot_count = n;
}

export fn init() void {
    host.create_template(0);
    var i: u32 = 0;
    while (i < MAX_SLOTS) : (i += 1) {
        host.open_element(span.ptr, @intCast(span.len));
        host.slot();
        host.close_element();
    }
    host.end_template();
}

fn formatInto(buf: *[STR_BUF_SIZE]u8, v: u32) u32 {
    if (v == 0) {
        buf[0] = '0';
        return 1;
    }
    // Count digits
    var temp = v;
    var digits: u32 = 0;
    while (temp > 0) {
        digits += 1;
        temp /= 10;
    }
    // Write digits right-to-left into buf[0..digits]
    var val = v;
    var pos = digits;
    while (val > 0) {
        pos -= 1;
        buf[pos] = '0' + @as(u8, @intCast(val % 10));
        val /= 10;
    }
    return digits;
}

export fn render() void {
    var i: u32 = 0;
    while (i < slot_count) : (i += 1) {
        const len = formatInto(&str_bufs[i], frame * 1000 + i);
        pair_buf[i * 2] = @intFromPtr(&str_bufs[i]);
        pair_buf[i * 2 + 1] = len;
    }
    host.update_template(0, @intFromPtr(&pair_buf), slot_count);
    frame +%= 1;
}
