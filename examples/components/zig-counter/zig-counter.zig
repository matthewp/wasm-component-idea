const std = @import("std");
const dom = @import("dom.zig");

var count: i32 = 0;

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

fn render() dom.OpcodeList {
    return view.update(.{count});
}

fn handleEvent(name_ptr: [*]const u8, name_len: u32) void {
    const name = name_ptr[0..name_len];
    if (std.mem.eql(u8, name, "on_decrement")) {
        on_decrement();
    } else if (std.mem.eql(u8, name, "on_increment")) {
        on_increment();
    }
}

// --- Canonical ABI exports for zig-child interface ---

export fn @"wasm-components:dom/zig-child@0.1.0#render"() [*]u8 {
    return dom.renderExport(render());
}

export fn @"wasm-components:dom/zig-child@0.1.0#handle-event"(name_ptr: [*]const u8, name_len: u32) void {
    dom.resetHeap();
    handleEvent(name_ptr, name_len);
}

export fn @"cabi_post_wasm-components:dom/zig-child@0.1.0#render"(_: [*]u8) void {}
