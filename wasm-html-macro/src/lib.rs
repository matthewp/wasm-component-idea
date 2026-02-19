mod codegen;
mod parse;

use proc_macro::TokenStream;

#[proc_macro]
pub fn html(input: TokenStream) -> TokenStream {
    let nodes = parse::parse(input.into());
    codegen::generate(nodes).into()
}
