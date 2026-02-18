use proc_macro::{TokenStream, TokenTree, Delimiter};

#[proc_macro]
pub fn html(input: TokenStream) -> TokenStream {
    let instructions = parse(input);
    generate(&instructions)
}

// --- Instruction types ---

enum Inst {
    Open(String),
    Close,
    Attr(String, String),
    Event(String, String),
    Text(String),
    Slot(String),
}

fn instr_size(inst: &Inst) -> usize {
    match inst {
        Inst::Open(_) => 3,
        Inst::Close => 1,
        Inst::Attr(_, _) | Inst::Event(_, _) => 5,
        Inst::Text(_) | Inst::Slot(_) => 3,
    }
}

// --- Parser ---

fn is_punct(tt: &TokenTree, ch: char) -> bool {
    matches!(tt, TokenTree::Punct(p) if p.as_char() == ch)
}

fn expect_ident(tokens: &[TokenTree], i: &mut usize) -> String {
    if let TokenTree::Ident(id) = &tokens[*i] {
        *i += 1;
        id.to_string()
    } else {
        panic!("html!: expected identifier, got `{}`", tokens[*i])
    }
}

fn expect_punct(tokens: &[TokenTree], i: &mut usize, ch: char) {
    if *i < tokens.len() && is_punct(&tokens[*i], ch) {
        *i += 1;
    } else {
        panic!("html!: expected `{}`", ch)
    }
}

fn expect_string(tokens: &[TokenTree], i: &mut usize) -> String {
    if let TokenTree::Literal(lit) = &tokens[*i] {
        *i += 1;
        unquote(&lit.to_string())
    } else {
        panic!("html!: expected string literal, got `{}`", tokens[*i])
    }
}

fn unquote(s: &str) -> String {
    if s.starts_with('"') && s.ends_with('"') {
        s[1..s.len() - 1].to_string()
    } else {
        s.to_string()
    }
}

fn parse(input: TokenStream) -> Vec<Inst> {
    let tokens: Vec<TokenTree> = input.into_iter().collect();
    let mut i = 0;
    let mut out = Vec::new();

    while i < tokens.len() {
        if is_punct(&tokens[i], '<') {
            i += 1;

            // Closing tag: </tag>
            if i < tokens.len() && is_punct(&tokens[i], '/') {
                i += 1;
                let _tag = expect_ident(&tokens, &mut i);
                expect_punct(&tokens, &mut i, '>');
                out.push(Inst::Close);
                continue;
            }

            // Opening tag: <tag ...> or <tag .../>
            let tag = expect_ident(&tokens, &mut i);
            out.push(Inst::Open(tag));

            // Attributes
            loop {
                if i >= tokens.len() {
                    break;
                }
                if is_punct(&tokens[i], '>') {
                    i += 1;
                    break;
                }
                if is_punct(&tokens[i], '/') {
                    i += 1;
                    expect_punct(&tokens, &mut i, '>');
                    out.push(Inst::Close);
                    break;
                }

                let name = expect_ident(&tokens, &mut i);

                // on:event="handler"
                if name == "on" && i < tokens.len() && is_punct(&tokens[i], ':') {
                    i += 1;
                    let event_type = expect_ident(&tokens, &mut i);
                    expect_punct(&tokens, &mut i, '=');
                    let handler = expect_string(&tokens, &mut i);
                    out.push(Inst::Event(event_type, handler));
                } else {
                    // Regular attribute: name="value"
                    expect_punct(&tokens, &mut i, '=');
                    let value = expect_string(&tokens, &mut i);
                    out.push(Inst::Attr(name, value));
                }
            }
        } else if let TokenTree::Literal(lit) = &tokens[i] {
            // String literal = static text
            out.push(Inst::Text(unquote(&lit.to_string())));
            i += 1;
        } else if let TokenTree::Group(g) = &tokens[i] {
            if g.delimiter() == Delimiter::Brace {
                // { expr } = dynamic slot
                out.push(Inst::Slot(g.stream().to_string()));
            }
            i += 1;
        } else {
            i += 1;
        }
    }

    out
}

// --- Code generator ---

fn generate(instrs: &[Inst]) -> TokenStream {
    let buf_size: usize = instrs.iter().map(instr_size).sum::<usize>() + 1;
    let slot_count = instrs.iter().filter(|i| matches!(i, Inst::Slot(_))).count();
    let max_slots = slot_count.max(1);

    // First render: full template + slot values
    let mut first = String::new();
    let mut slot_idx = 0;
    let mut pos = 0;

    for inst in instrs {
        match inst {
            Inst::Open(tag) => {
                first += &format!(
                    "*b.add({}) = 1; *b.add({}) = b\"{}\".as_ptr() as u32; *b.add({}) = {};\n",
                    pos, pos + 1, tag, pos + 2, tag.len()
                );
                pos += 3;
            }
            Inst::Close => {
                first += &format!("*b.add({}) = 2;\n", pos);
                pos += 1;
            }
            Inst::Attr(name, val) => {
                first += &format!(
                    "*b.add({}) = 3; *b.add({}) = b\"{}\".as_ptr() as u32; *b.add({}) = {}; \
                     *b.add({}) = b\"{}\".as_ptr() as u32; *b.add({}) = {};\n",
                    pos, pos+1, name, pos+2, name.len(), pos+3, val, pos+4, val.len()
                );
                pos += 5;
            }
            Inst::Event(etype, handler) => {
                first += &format!(
                    "*b.add({}) = 6; *b.add({}) = b\"{}\".as_ptr() as u32; *b.add({}) = {}; \
                     *b.add({}) = b\"{}\".as_ptr() as u32; *b.add({}) = {};\n",
                    pos, pos+1, etype, pos+2, etype.len(), pos+3, handler, pos+4, handler.len()
                );
                pos += 5;
            }
            Inst::Text(text) => {
                first += &format!(
                    "*b.add({}) = 4; *b.add({}) = b\"{}\".as_ptr() as u32; *b.add({}) = {};\n",
                    pos, pos + 1, text, pos + 2, text.len()
                );
                pos += 3;
            }
            Inst::Slot(expr) => {
                first += &format!(
                    "{{ let (__p, __l) = ({}).write_slot(&mut (*__sbufs)[{}]); \
                       *b.add({}) = 5; *b.add({}) = __p; *b.add({}) = __l; }}\n",
                    expr, slot_idx, pos, pos + 1, pos + 2
                );
                slot_idx += 1;
                pos += 3;
            }
        }
    }
    first += &format!("*b.add({}) = 0;\n", pos);

    // Subsequent renders: slot opcodes only
    let mut subsequent = String::new();
    let mut slot_idx = 0;
    let mut spos = 0;
    for inst in instrs {
        if let Inst::Slot(expr) = inst {
            subsequent += &format!(
                "{{ let (__p, __l) = ({}).write_slot(&mut (*__sbufs)[{}]); \
                   *b.add({}) = 5; *b.add({}) = __p; *b.add({}) = __l; }}\n",
                expr, slot_idx, spos, spos + 1, spos + 2
            );
            slot_idx += 1;
            spos += 3;
        }
    }
    subsequent += &format!("*b.add({}) = 0;\n", spos);

    let code = format!(
        r#"{{
    trait __SlotVal {{
        fn write_slot(self, buf: &mut [u8; 20]) -> (u32, u32);
    }}
    impl __SlotVal for i32 {{
        fn write_slot(self, buf: &mut [u8; 20]) -> (u32, u32) {{
            let mut v: u32 = if self < 0 {{ (-self) as u32 }} else {{ self as u32 }};
            let mut start: usize = 0;
            if self < 0 {{ buf[0] = b'-'; start = 1; }}
            if v == 0 {{ buf[start] = b'0'; return (buf.as_ptr() as u32, (start + 1) as u32); }}
            let mut digits: usize = 0;
            let mut temp = v;
            while temp > 0 {{ digits += 1; temp /= 10; }}
            let mut pos = start + digits;
            while v > 0 {{ pos -= 1; buf[pos] = b'0' + (v % 10) as u8; v /= 10; }}
            (buf.as_ptr() as u32, (start + digits) as u32)
        }}
    }}
    impl<'a> __SlotVal for &'a str {{
        fn write_slot(self, _buf: &mut [u8; 20]) -> (u32, u32) {{
            (self.as_ptr() as u32, self.len() as u32)
        }}
    }}
    impl<'a> __SlotVal for &'a [u8] {{
        fn write_slot(self, _buf: &mut [u8; 20]) -> (u32, u32) {{
            (self.as_ptr() as u32, self.len() as u32)
        }}
    }}
    static mut __DEF: bool = false;
    static mut __BUF: [u32; {buf_size}] = [0u32; {buf_size}];
    static mut __SBUFS: [[u8; 20]; {max_slots}] = [[0u8; 20]; {max_slots}];
    unsafe {{
        let b = core::ptr::addr_of_mut!(__BUF) as *mut u32;
        let __def = core::ptr::addr_of_mut!(__DEF);
        let __sbufs = core::ptr::addr_of_mut!(__SBUFS);
        if !*__def {{
            *__def = true;
            {first}
            core::ptr::addr_of_mut!(__BUF) as u32
        }} else {{
            {subsequent}
            core::ptr::addr_of_mut!(__BUF) as u32
        }}
    }}
}}"#,
        buf_size = buf_size,
        max_slots = max_slots,
        first = first,
        subsequent = subsequent,
    );

    code.parse().unwrap_or_else(|e| {
        panic!("html! generated invalid code: {}\n\nCode:\n{}", e, code)
    })
}
