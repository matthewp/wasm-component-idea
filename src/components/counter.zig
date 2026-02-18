const dom = @import("dom.zig");

var count: i32 = 0;

export fn on_decrement() void { if (count > 0) count -= 1; }
export fn on_increment() void { count += 1; }

const view = dom.html(
    \\<div class='counter'>
    \\  <button on:click='on_decrement'>-</button>
    \\  <span class='count'>{}</span>
    \\  <button on:click='on_increment'>+</button>
    \\</div>
);

export fn render() u32 {
    return view.update(.{count});
}
