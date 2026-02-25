const std = @import("std");
const dom = @import("dom.zig");

var count: i32 = 0;
var initialized: bool = false;

fn on_decrement() void {
    if (count > 0) count -= 1;
}
fn on_increment() void {
    count += 1;
}

const view = dom.html(
    \\<div class='counter'>
    \\  <button on:click='on_decrement'>-</button>
    \\  <span class='count'>{}</span>
    \\  <button on:click='on_increment'>+</button>
    \\</div>
);

pub fn render(props: []const dom.Prop) dom.OpcodeList {
    if (!initialized) {
        initialized = true;
        for (props) |prop| {
            if (std.mem.eql(u8, prop.key(), "initial") and prop.disc == 0) {
                count = prop.int();
            }
        }
    }
    return view.update(.{count});
}

pub fn handleEvent(name: []const u8) void {
    if (std.mem.eql(u8, name, "on_decrement")) {
        on_decrement();
    } else if (std.mem.eql(u8, name, "on_increment")) {
        on_increment();
    }
}

comptime {
    dom.exportRenderer(@This());
}
