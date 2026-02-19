#![no_std]

use core::panic::PanicInfo;
use wasm_html_macro::html;

#[panic_handler]
fn panic(_: &PanicInfo) -> ! { loop {} }

#[no_mangle]
pub extern "C" fn render() -> u32 {
    html! {
        <div class="app">
            <h1>"WASM Component Protocol"</h1>
            <counter-app />
            <full-name />
        </div>
    }
}
