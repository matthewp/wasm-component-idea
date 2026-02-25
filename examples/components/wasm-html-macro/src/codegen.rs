use proc_macro2::TokenStream;
use quote::quote;
use syn::{Expr, Lit};

use crate::parse::{Node, PropValue};

pub fn generate(nodes: Vec<Node>) -> TokenStream {
    let items: Vec<TokenStream> = nodes
        .into_iter()
        .map(|node| match node {
            Node::Open(tag) => quote! { Opcode::Open(#tag.into()) },
            Node::Close => quote! { Opcode::Close },
            Node::Attr { name, value } => {
                quote! { Opcode::Attr((#name.into(), #value.into())) }
            }
            Node::Event {
                event_type,
                handler,
            } => {
                quote! { Opcode::Event((#event_type.into(), #handler.into())) }
            }
            Node::Text(text) => quote! { Opcode::Text(#text.into()) },
            Node::Slot(expr) => quote! { Opcode::Slot(#expr) },
            Node::Child(name) => quote! { Opcode::Child(#name.into()) },
            Node::DynAttr { name, value } => {
                quote! { Opcode::AttrSlot((#name.into(), (#value).to_string())) }
            }
            Node::Begin(id) => quote! { Opcode::Begin(#id.into()) },
            Node::End => quote! { Opcode::End },
            Node::Prop { name, value } => match value {
                PropValue::Str(s) => {
                    quote! { Opcode::Prop((#name.into(), PropValue::Str(#s.into()))) }
                }
                PropValue::Expr(expr) => {
                    let val = match &expr {
                        Expr::Lit(lit) => match &lit.lit {
                            Lit::Int(i) => quote! { PropValue::Int(#i) },
                            Lit::Float(f) => quote! { PropValue::Float(#f) },
                            Lit::Bool(b) => quote! { PropValue::Boolean(#b.value) },
                            _ => quote! { PropValue::Str((#expr).to_string()) },
                        },
                        _ => quote! { PropValue::Str((#expr).to_string()) },
                    };
                    quote! { Opcode::Prop((#name.into(), #val)) }
                }
            },
        })
        .collect();

    quote! {
        vec![#(#items),*]
    }
}
