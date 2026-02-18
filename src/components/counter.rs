#![no_std]

use core::panic::PanicInfo;
use core::ptr::addr_of_mut;
use wasm_html_macro::html;

#[panic_handler]
fn panic(_: &PanicInfo) -> ! { loop {} }

static mut COUNT: i32 = 0;

#[no_mangle]
pub extern "C" fn on_decrement() {
    unsafe { let c = addr_of_mut!(COUNT); if *c > 0 { *c -= 1; } }
}

#[no_mangle]
pub extern "C" fn on_increment() {
    unsafe { *addr_of_mut!(COUNT) += 1; }
}

#[no_mangle]
pub extern "C" fn render() -> u32 {
    let count = unsafe { *addr_of_mut!(COUNT) };
    html! {
        <div class="counter">
            <button on:click="on_decrement">"-"</button>
            <span class="count">{ count }</span>
            <button on:click="on_increment">"+"</button>
        </div>
    }
}
