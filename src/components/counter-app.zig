const dom = @import("dom.zig");

const view = dom.html(
    \\<div class="counter-app">
    \\  <h2>Counter Apps</h2>
    \\  <zig-counter />
    \\  <rust-counter />
    \\</div>
);

export fn render() u32 {
    return view.update(.{});
}
