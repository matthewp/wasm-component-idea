wit_bindgen::generate!({
    path: "../wit",
    world: "pure-component",
});

use exports::wasm_components::dom::renderer::Guest;
use exports::wasm_components::dom::renderer::Opcode;
use wasm_html_macro::html;

struct CounterApp;

impl Guest for CounterApp {
    fn render() -> Vec<Opcode> {
        html! {
            <div class="counter-app">
                <h2>"Counter Apps"</h2>
                <h3>"Zig Counter"</h3>
                <ZigChild />
                <h3>"Rust Counter"</h3>
                <RustChild />
            </div>
        }
    }

    fn handle_event(_handler: String) {}
}

export!(CounterApp);
