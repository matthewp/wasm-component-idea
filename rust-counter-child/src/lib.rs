wit_bindgen::generate!({
    path: "../wit",
    world: "rust-counter",
});

use exports::wasm_components::dom::rust_child::{Guest, Opcode};
use wasm_html_macro::html;

struct Counter;

static mut COUNT: i32 = 0;

impl Guest for Counter {
    fn render() -> Vec<Opcode> {
        let count = unsafe { COUNT };
        let count_str = format_i32(count);

        html! {
            <div class="counter">
                <button on:click="on_decrement">"-"</button>
                <span class="count">{ count_str }</span>
                <button on:click="on_increment">"+"</button>
            </div>
        }
    }

    fn handle_event(handler: String) {
        match handler.as_str() {
            "on_decrement" => unsafe {
                if COUNT > 0 { COUNT -= 1; }
            },
            "on_increment" => unsafe {
                COUNT += 1;
            },
            _ => {}
        }
    }
}

fn format_i32(n: i32) -> String {
    if n == 0 { return "0".into(); }
    let mut v = if n < 0 { (-n) as u32 } else { n as u32 };
    let mut buf = [0u8; 11];
    let mut pos = buf.len();
    while v > 0 {
        pos -= 1;
        buf[pos] = b'0' + (v % 10) as u8;
        v /= 10;
    }
    if n < 0 { pos -= 1; buf[pos] = b'-'; }
    unsafe { core::str::from_utf8_unchecked(&buf[pos..]).to_string() }
}

export!(Counter);
