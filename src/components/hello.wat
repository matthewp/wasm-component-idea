(module
  ;; Import incremental-DOM host functions
  (import "host" "open_element" (func $open_element (param i32 i32)))
  (import "host" "close_element" (func $close_element))
  (import "host" "attribute" (func $attribute (param i32 i32 i32 i32)))
  (import "host" "text" (func $text (param i32 i32)))

  ;; Export memory so the host can read our string data
  (memory (export "memory") 1)

  ;; String constants laid out in linear memory
  ;; offset 0: "div" (len 3)
  (data (i32.const 0) "div")
  ;; offset 3: "class" (len 5)
  (data (i32.const 3) "class")
  ;; offset 8: "greeting" (len 8)
  (data (i32.const 8) "greeting")
  ;; offset 16: "h1" (len 2)
  (data (i32.const 16) "h1")
  ;; offset 18: "Hello from WASM!" (len 16)
  (data (i32.const 18) "Hello from WASM!")
  ;; offset 34: "p" (len 1)
  (data (i32.const 34) "p")
  ;; offset 35: "Rendered via incremental-DOM from WebAssembly." (len 46)
  (data (i32.const 35) "Rendered via incremental-DOM from WebAssembly.")

  (func (export "render")
    ;; <div class="greeting">
    (call $open_element (i32.const 0) (i32.const 3))
    (call $attribute (i32.const 3) (i32.const 5) (i32.const 8) (i32.const 8))

    ;; <h1>Hello from WASM!</h1>
    (call $open_element (i32.const 16) (i32.const 2))
    (call $text (i32.const 18) (i32.const 16))
    (call $close_element)

    ;; <p>Rendered via incremental-DOM from WebAssembly.</p>
    (call $open_element (i32.const 34) (i32.const 1))
    (call $text (i32.const 35) (i32.const 46))
    (call $close_element)

    ;; </div>
    (call $close_element)
  )
)
