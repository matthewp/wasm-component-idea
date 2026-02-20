wit_bindgen::generate!({
    path: "../wit",
    world: "leaf-component",
});

use exports::wasm_components::dom::renderer::{Guest, Opcode, PropValue};
use wasm_components::dom::host::event_query;

struct TodoApp;

struct TodoItem {
    id: u32,
    text: String,
}

static mut TODOS: Vec<TodoItem> = Vec::new();
static mut NEXT_ID: u32 = 0;
static mut INPUT_VALUE: String = String::new();

impl Guest for TodoApp {
    fn render(_props: Vec<(String, PropValue)>) -> Vec<Opcode> {
        let todos = unsafe { &TODOS };
        let input_value = unsafe { &INPUT_VALUE };
        let count_str = format_u32(todos.len() as u32);

        let mut ops = vec![
            Opcode::Open("div".into()),
            Opcode::Attr(("class".into(), "todo-app".into())),
            Opcode::Open("h2".into()),
            Opcode::Text("Todo List".into()),
            Opcode::Close,
            Opcode::Open("div".into()),
            Opcode::Attr(("class".into(), "todo-input".into())),
            Opcode::Open("input".into()),
            Opcode::Attr(("type".into(), "text".into())),
            Opcode::Attr(("placeholder".into(), "What needs to be done?".into())),
            Opcode::AttrSlot(("value".into(), input_value.clone())),
            Opcode::Event(("input".into(), "on_input".into())),
            Opcode::Event(("keydown".into(), "on_keydown".into())),
            Opcode::Close,
            Opcode::Close,
            Opcode::Open("p".into()),
            Opcode::Slot(count_str + " items"),
            Opcode::Close,
            Opcode::Open("ul".into()),
            Opcode::Attr(("class".into(), "todo-list".into())),
        ];

        for todo in todos {
            let id_str = format_u32(todo.id);
            ops.push(Opcode::Begin("todo-item".into()));
            ops.push(Opcode::Open("li".into()));
            ops.push(Opcode::AttrSlot(("data-id".into(), id_str.clone())));
            ops.push(Opcode::Slot(todo.text.clone()));
            ops.push(Opcode::Open("button".into()));
            ops.push(Opcode::Attr(("class".into(), "delete".into())));
            ops.push(Opcode::AttrSlot(("data-id".into(), id_str)));
            ops.push(Opcode::Event(("click".into(), "on_delete".into())));
            ops.push(Opcode::Text("\u{00d7}".into()));
            ops.push(Opcode::Close);
            ops.push(Opcode::Close);
            ops.push(Opcode::End);
        }

        ops.push(Opcode::Close); // </ul>
        ops.push(Opcode::Close); // </div>
        ops
    }

    fn handle_event(handler: String) {
        match handler.as_str() {
            "on_input" => {
                unsafe { INPUT_VALUE = event_query("target.value"); }
            }
            "on_keydown" => {
                if event_query("key") == "Enter" {
                    let value = event_query("target.value");
                    if !value.is_empty() {
                        let id = unsafe {
                            let id = NEXT_ID;
                            NEXT_ID += 1;
                            id
                        };
                        unsafe {
                            TODOS.push(TodoItem { id, text: value });
                            INPUT_VALUE.clear();
                        }
                    }
                }
            }
            "on_delete" => {
                let id_str = event_query("target.dataset.id");
                if let Ok(id) = id_str.parse::<u32>() {
                    unsafe {
                        TODOS.retain(|t| t.id != id);
                    }
                }
            }
            _ => {}
        }
    }
}

fn format_u32(n: u32) -> String {
    if n == 0 {
        return "0".into();
    }
    let mut v = n;
    let mut buf = [0u8; 10];
    let mut pos = buf.len();
    while v > 0 {
        pos -= 1;
        buf[pos] = b'0' + (v % 10) as u8;
        v /= 10;
    }
    unsafe { core::str::from_utf8_unchecked(&buf[pos..]).to_string() }
}

export!(TodoApp);
