wit_bindgen::generate!({
    path: "../../../wit",
    world: "pure-component",
});

use exports::wasm_components::dom::renderer::{Guest, Opcode, PropValue};
use wasm_html_macro::html;

struct CounterApp;

static mut DARK: bool = false;

impl Guest for CounterApp {
    fn render(_props: Vec<(String, PropValue)>) -> Vec<Opcode> {
        let theme = if unsafe { DARK } {
            "counter-app dark"
        } else {
            "counter-app"
        };

        html! {
            <div class={theme}>
                <h2>"Counter Apps"</h2>
                <button on:click="toggle_dark">"Toggle Dark Mode"</button>
                <h3>"Zig Counter"</h3>
                <ZigChild initial={5} />
                <h3>"Rust Counter"</h3>
                <RustChild />
            </div>
        }
    }

    fn handle_event(handler: String) {
        match handler.as_str() {
            "toggle_dark" => unsafe { DARK = !DARK },
            _ => {}
        }
    }
}

export!(CounterApp);
