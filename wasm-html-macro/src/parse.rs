use proc_macro2::{Delimiter, TokenStream, TokenTree};
use syn::{Expr, LitStr};

pub enum Node {
    Open(String),
    Close,
    Attr { name: String, value: String },
    Event { event_type: String, handler: String },
    Text(String),
    Slot(Expr),
    Child(String),
}

pub fn parse(input: TokenStream) -> Vec<Node> {
    let tokens: Vec<TokenTree> = input.into_iter().collect();
    let mut nodes = Vec::new();
    let mut pos = 0;

    while pos < tokens.len() {
        match &tokens[pos] {
            // `<` — start of an open or close tag
            TokenTree::Punct(p) if p.as_char() == '<' => {
                pos += 1;
                // Check for `</tag>`
                if pos < tokens.len() {
                    if let TokenTree::Punct(p2) = &tokens[pos] {
                        if p2.as_char() == '/' {
                            pos += 1;
                            // consume tag name (may be hyphenated: e.g. `my-component`)
                            let _tag = consume_tag_name(&tokens, &mut pos);
                            // consume `>`
                            expect_punct(&tokens, &mut pos, '>');
                            nodes.push(Node::Close);
                            continue;
                        }
                    }
                }

                // Open tag: `<tag`
                let tag = consume_tag_name(&tokens, &mut pos);

                // PascalCase tag names are child components: <ZigChild /> → child("zig-child")
                if tag.starts_with(|c: char| c.is_uppercase()) {
                    expect_punct(&tokens, &mut pos, '/');
                    expect_punct(&tokens, &mut pos, '>');
                    nodes.push(Node::Child(pascal_to_kebab(&tag)));
                    continue;
                }

                nodes.push(Node::Open(tag));

                // Parse attributes until `>` or `/>`
                loop {
                    if pos >= tokens.len() {
                        break;
                    }
                    match &tokens[pos] {
                        // `>` — end of open tag
                        TokenTree::Punct(p) if p.as_char() == '>' => {
                            pos += 1;
                            break;
                        }
                        // `/` followed by `>` — self-closing
                        TokenTree::Punct(p) if p.as_char() == '/' => {
                            pos += 1;
                            expect_punct(&tokens, &mut pos, '>');
                            nodes.push(Node::Close);
                            break;
                        }
                        // attribute: `name="value"` or `on:event="handler"`
                        TokenTree::Ident(_) => {
                            let name = ident_string(&tokens[pos]);
                            pos += 1;

                            // Check for `on:event`
                            if pos < tokens.len() {
                                if let TokenTree::Punct(p) = &tokens[pos] {
                                    if p.as_char() == ':' {
                                        // event binding: on:click="handler"
                                        pos += 1; // skip `:`
                                        let event_type = ident_string(&tokens[pos]);
                                        pos += 1;
                                        expect_punct(&tokens, &mut pos, '=');
                                        let handler = consume_string_literal(&tokens, &mut pos);
                                        nodes.push(Node::Event { event_type, handler });
                                        continue;
                                    }
                                }
                            }

                            // Regular attribute: name="value"
                            expect_punct(&tokens, &mut pos, '=');
                            let value = consume_string_literal(&tokens, &mut pos);
                            nodes.push(Node::Attr { name, value });
                        }
                        _ => {
                            panic!(
                                "html!: unexpected token in attribute position: {:?}",
                                tokens[pos]
                            );
                        }
                    }
                }
            }
            // String literal — text content
            TokenTree::Literal(_) => {
                let lit_str: LitStr = syn::parse2(TokenStream::from(tokens[pos].clone()))
                    .expect("html!: expected string literal for text content");
                nodes.push(Node::Text(lit_str.value()));
                pos += 1;
            }
            // `{ expr }` — slot (dynamic content)
            TokenTree::Group(g) if g.delimiter() == Delimiter::Brace => {
                let expr: Expr = syn::parse2(g.stream())
                    .expect("html!: expected expression inside { }");
                nodes.push(Node::Slot(expr));
                pos += 1;
            }
            _ => {
                panic!("html!: unexpected token: {:?}", tokens[pos]);
            }
        }
    }

    nodes
}

fn consume_tag_name(tokens: &[TokenTree], pos: &mut usize) -> String {
    let mut name = ident_string(&tokens[*pos]);
    *pos += 1;
    // Handle hyphenated tag names: `my-component` tokenizes as `my`, `-`, `component`
    while *pos + 1 < tokens.len() {
        if let TokenTree::Punct(p) = &tokens[*pos] {
            if p.as_char() == '-' {
                if let TokenTree::Ident(_) = &tokens[*pos + 1] {
                    name.push('-');
                    name.push_str(&ident_string(&tokens[*pos + 1]));
                    *pos += 2;
                    continue;
                }
            }
        }
        break;
    }
    name
}

fn ident_string(tt: &TokenTree) -> String {
    match tt {
        TokenTree::Ident(id) => id.to_string(),
        _ => panic!("html!: expected identifier, got {:?}", tt),
    }
}

fn expect_punct(tokens: &[TokenTree], pos: &mut usize, ch: char) {
    match &tokens[*pos] {
        TokenTree::Punct(p) if p.as_char() == ch => {
            *pos += 1;
        }
        _ => panic!("html!: expected '{}', got {:?}", ch, tokens[*pos]),
    }
}

fn consume_string_literal(tokens: &[TokenTree], pos: &mut usize) -> String {
    let lit_str: LitStr = syn::parse2(TokenStream::from(tokens[*pos].clone()))
        .expect("html!: expected string literal");
    *pos += 1;
    lit_str.value()
}

fn pascal_to_kebab(s: &str) -> String {
    let mut result = String::new();
    for (i, c) in s.chars().enumerate() {
        if c.is_uppercase() {
            if i > 0 {
                result.push('-');
            }
            for lc in c.to_lowercase() {
                result.push(lc);
            }
        } else {
            result.push(c);
        }
    }
    result
}
