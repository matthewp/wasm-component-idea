// Benchmark component using the callback protocol (update/value/commit).
// Per-slot value() calls: N+2 boundary crossings per render.

const host = struct {
    extern "host" fn create_template(id: u32) void;
    extern "host" fn open_element(ptr: [*]const u8, len: u32) void;
    extern "host" fn close_element() void;
    extern "host" fn slot() void;
    extern "host" fn end_template() void;
    extern "host" fn update(id: u32) void;
    extern "host" fn value(ptr: [*]const u8, len: u32) void;
    extern "host" fn commit() void;
};

const MAX_SLOTS: u32 = 1000;

var slot_count: u32 = 10;
var frame: u32 = 0;
var itoa_buf: [20]u8 = undefined;

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

fn emitValue(v: u32) void {
    var val = v;
    var pos: usize = itoa_buf.len;
    if (val == 0) {
        pos -= 1;
        itoa_buf[pos] = '0';
    } else {
        while (val > 0) {
            pos -= 1;
            itoa_buf[pos] = '0' + @as(u8, @intCast(val % 10));
            val /= 10;
        }
    }
    host.value(itoa_buf[pos..].ptr, @intCast(itoa_buf.len - pos));
}

export fn render() void {
    host.update(0);
    var i: u32 = 0;
    while (i < slot_count) : (i += 1) {
        emitValue(frame * 1000 + i);
    }
    host.commit();
    frame +%= 1;
}
