(module
    (func $add (param i32) (param i32) (result i32)
        local.get 0 local.get 1 i32.add)
    (export "wasm-components:trivial/math@0.1.0#add" (func $add))
)
