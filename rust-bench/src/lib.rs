wit_bindgen::generate!({
    path: "../wit",
    world: "leaf-component",
});

use exports::wasm_components::dom::renderer::{Guest, Opcode, PropValue};
use wasm_components::dom::host::event_query;

struct Bench;

struct Row {
    id: u32,
    label: String,
}

static mut DATA: Vec<Row> = Vec::new();
static mut NEXT_ID: u32 = 1;
static mut SELECTED: u32 = 0; // 0 = none

const ADJECTIVES: &[&str] = &[
    "pretty", "large", "big", "small", "tall", "short", "long",
    "handsome", "plain", "quaint", "clean", "elegant", "easy", "angry", "crazy",
    "helpful", "mushy", "odd", "unsightly", "adorable", "important",
    "inexpensive", "cheap", "expensive", "fancy",
];
const COLOURS: &[&str] = &[
    "red", "yellow", "blue", "green", "pink", "brown", "purple",
    "brown", "white", "black", "orange",
];
const NOUNS: &[&str] = &[
    "table", "chair", "house", "bbq", "desk", "car", "pony",
    "cookie", "sandwich", "burger", "pizza", "mouse", "keyboard",
];

static mut SEED: u32 = 0;

fn random(max: usize) -> usize {
    unsafe {
        SEED = SEED.wrapping_mul(1103515245).wrapping_add(12345) & 0x7fffffff;
        (SEED % max as u32) as usize
    }
}

fn build_label() -> String {
    let mut s = String::with_capacity(32);
    s.push_str(ADJECTIVES[random(ADJECTIVES.len())]);
    s.push(' ');
    s.push_str(COLOURS[random(COLOURS.len())]);
    s.push(' ');
    s.push_str(NOUNS[random(NOUNS.len())]);
    s
}

fn create_rows(count: usize) -> Vec<Row> {
    let mut rows = Vec::with_capacity(count);
    for _ in 0..count {
        unsafe {
            let id = NEXT_ID;
            NEXT_ID += 1;
            rows.push(Row { id, label: build_label() });
        }
    }
    rows
}

fn format_u32(n: u32) -> String {
    if n == 0 { return "0".into(); }
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

fn push_button(ops: &mut Vec<Opcode>, id: &str, label: &str, handler: &str) {
    ops.push(Opcode::Open("div".into()));
    ops.push(Opcode::Attr(("class".into(), "col-sm-6 smallpad".into())));
    ops.push(Opcode::Open("button".into()));
    ops.push(Opcode::Attr(("type".into(), "button".into())));
    ops.push(Opcode::Attr(("class".into(), "btn btn-primary btn-block".into())));
    ops.push(Opcode::Attr(("id".into(), id.into())));
    ops.push(Opcode::Event(("click".into(), handler.into())));
    ops.push(Opcode::Text(label.into()));
    ops.push(Opcode::Close); // button
    ops.push(Opcode::Close); // div
}

impl Guest for Bench {
    fn render(_props: Vec<(String, PropValue)>) -> Vec<Opcode> {
        let data = unsafe { &DATA };
        let selected = unsafe { SELECTED };

        let row_count = data.len();
        // Static opcodes (~70) + per-row opcodes (~20 each)
        let mut ops = Vec::with_capacity(70 + row_count * 20);

        // --- Container ---
        ops.push(Opcode::Open("div".into()));
        ops.push(Opcode::Attr(("class".into(), "container".into())));

        // --- Jumbotron ---
        ops.push(Opcode::Open("div".into()));
        ops.push(Opcode::Attr(("class".into(), "jumbotron".into())));
        ops.push(Opcode::Open("div".into()));
        ops.push(Opcode::Attr(("class".into(), "row".into())));

        // Title
        ops.push(Opcode::Open("div".into()));
        ops.push(Opcode::Attr(("class".into(), "col-md-6".into())));
        ops.push(Opcode::Open("h1".into()));
        ops.push(Opcode::Text("WASM Component Protocol".into()));
        ops.push(Opcode::Close); // h1
        ops.push(Opcode::Close); // col-md-6

        // Buttons
        ops.push(Opcode::Open("div".into()));
        ops.push(Opcode::Attr(("class".into(), "col-md-6".into())));
        ops.push(Opcode::Open("div".into()));
        ops.push(Opcode::Attr(("class".into(), "row".into())));
        push_button(&mut ops, "run", "Create 1,000 rows", "run");
        push_button(&mut ops, "runlots", "Create 10,000 rows", "runlots");
        push_button(&mut ops, "add", "Append 1,000 rows", "add");
        push_button(&mut ops, "update", "Update every 10th row", "update");
        push_button(&mut ops, "clear", "Clear", "clear");
        push_button(&mut ops, "swaprows", "Swap Rows", "swaprows");
        ops.push(Opcode::Close); // row
        ops.push(Opcode::Close); // col-md-6

        ops.push(Opcode::Close); // row
        ops.push(Opcode::Close); // jumbotron

        // --- Table ---
        ops.push(Opcode::Open("table".into()));
        ops.push(Opcode::Attr(("class".into(), "table table-hover table-striped test-data".into())));
        ops.push(Opcode::Open("tbody".into()));
        ops.push(Opcode::Attr(("id".into(), "tbody".into())));
        ops.push(Opcode::Event(("click".into(), "on_click".into())));

        for row in data {
            let id_str = format_u32(row.id);
            let row_class = if row.id == selected { "danger" } else { "" };

            ops.push(Opcode::Begin("row".into()));
            ops.push(Opcode::Open("tr".into()));
            ops.push(Opcode::AttrSlot(("class".into(), row_class.into())));

            // Column 1: ID
            ops.push(Opcode::Open("td".into()));
            ops.push(Opcode::Attr(("class".into(), "col-md-1".into())));
            ops.push(Opcode::Slot(id_str.clone()));
            ops.push(Opcode::Close);

            // Column 2: Label
            ops.push(Opcode::Open("td".into()));
            ops.push(Opcode::Attr(("class".into(), "col-md-4".into())));
            ops.push(Opcode::Open("a".into()));
            ops.push(Opcode::Attr(("class".into(), "lbl".into())));
            ops.push(Opcode::AttrSlot(("data-id".into(), id_str.clone())));
            ops.push(Opcode::Slot(row.label.clone()));
            ops.push(Opcode::Close); // a
            ops.push(Opcode::Close); // td

            // Column 3: Delete
            ops.push(Opcode::Open("td".into()));
            ops.push(Opcode::Attr(("class".into(), "col-md-1".into())));
            ops.push(Opcode::Open("a".into()));
            ops.push(Opcode::Attr(("class".into(), "remove".into())));
            ops.push(Opcode::AttrSlot(("data-id".into(), id_str)));
            ops.push(Opcode::Open("span".into()));
            ops.push(Opcode::Attr(("class".into(), "glyphicon glyphicon-remove".into())));
            ops.push(Opcode::Attr(("aria-hidden".into(), "true".into())));
            ops.push(Opcode::Close); // span
            ops.push(Opcode::Close); // a
            ops.push(Opcode::Close); // td

            // Column 4: spacer
            ops.push(Opcode::Open("td".into()));
            ops.push(Opcode::Attr(("class".into(), "col-md-6".into())));
            ops.push(Opcode::Close);

            ops.push(Opcode::Close); // tr
            ops.push(Opcode::End);
        }

        ops.push(Opcode::Close); // tbody
        ops.push(Opcode::Close); // table

        // Preload icon
        ops.push(Opcode::Open("span".into()));
        ops.push(Opcode::Attr(("class".into(), "preloadicon glyphicon glyphicon-remove".into())));
        ops.push(Opcode::Attr(("aria-hidden".into(), "true".into())));
        ops.push(Opcode::Close);

        ops.push(Opcode::Close); // container
        ops
    }

    fn handle_event(handler: String) {
        match handler.as_str() {
            "run" => unsafe {
                DATA = create_rows(1000);
                SELECTED = 0;
            },
            "runlots" => unsafe {
                DATA = create_rows(10000);
                SELECTED = 0;
            },
            "add" => {
                let mut new_rows = create_rows(1000);
                unsafe { DATA.append(&mut new_rows); }
            },
            "update" => unsafe {
                let mut i = 0;
                while i < DATA.len() {
                    DATA[i].label.push_str(" !!!");
                    i += 10;
                }
            },
            "clear" => unsafe {
                DATA.clear();
                SELECTED = 0;
            },
            "swaprows" => unsafe {
                if DATA.len() > 998 {
                    DATA.swap(1, 998);
                }
            },
            "on_click" => {
                let class = event_query("target.className");
                if class.contains("lbl") {
                    let id_str = event_query("target.dataset.id");
                    if let Ok(id) = id_str.parse::<u32>() {
                        unsafe {
                            SELECTED = if SELECTED == id { 0 } else { id };
                        }
                    }
                } else if class.contains("remove") {
                    let id_str = event_query("target.dataset.id");
                    if let Ok(id) = id_str.parse::<u32>() {
                        unsafe { DATA.retain(|r| r.id != id); }
                    }
                } else if class.contains("glyphicon") {
                    let id_str = event_query("target.parentElement.dataset.id");
                    if let Ok(id) = id_str.parse::<u32>() {
                        unsafe { DATA.retain(|r| r.id != id); }
                    }
                }
            },
            _ => {}
        }
    }
}

export!(Bench);
