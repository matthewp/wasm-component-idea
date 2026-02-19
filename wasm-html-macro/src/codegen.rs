use proc_macro2::TokenStream;
use quote::quote;

use crate::parse::Node;

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
        })
        .collect();

    quote! {
        vec![#(#items),*]
    }
}
