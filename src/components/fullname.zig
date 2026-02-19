const dom = @import("dom.zig");

var first: [64]u8 = undefined;
var first_len: u32 = 0;
var last: [64]u8 = undefined;
var last_len: u32 = 0;

export fn on_first() void {
    first_len = dom.eventTargetValue(&first, first.len);
}

export fn on_last() void {
    last_len = dom.eventTargetValue(&last, last.len);
}

const view = dom.html(
    \\<div class='fullname'>
    \\  <h2>Full Name</h2>
    \\  <input on:input='on_first' placeholder='First'/>
    \\  <input on:input='on_last' placeholder='Last'/>
    \\  <p class='result'>{}</p>
    \\</div>
);

var buf: [129]u8 = undefined;

fn fullName() []u8 {
    var pos: u32 = 0;
    @memcpy(buf[0..first_len], first[0..first_len]);
    pos = first_len;
    if (first_len > 0 and last_len > 0) {
        buf[pos] = ' ';
        pos += 1;
    }
    @memcpy(buf[pos .. pos + last_len], last[0..last_len]);
    return buf[0 .. pos + last_len];
}

export fn render() u32 {
    return view.update(.{fullName()});
}
