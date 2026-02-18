(module
  ;; Import incremental-DOM host functions
  (import "host" "open_element" (func $open_element (param i32 i32)))
  (import "host" "close_element" (func $close_element))
  (import "host" "attribute" (func $attribute (param i32 i32 i32 i32)))
  (import "host" "text" (func $text (param i32 i32)))
  (import "host" "on_event" (func $on_event (param i32 i32 i32 i32)))

  (memory (export "memory") 1)

  ;; Mutable state
  (global $count (mut i32) (i32.const 0))

  ;; Static strings in linear memory
  ;; 0: "div" (3)
  (data (i32.const 0) "div")
  ;; 3: "class" (5)
  (data (i32.const 3) "class")
  ;; 8: "counter" (7)
  (data (i32.const 8) "counter")
  ;; 15: "button" (6)
  (data (i32.const 15) "button")
  ;; 21: "click" (5)
  (data (i32.const 21) "click")
  ;; 26: "−" (3 bytes, UTF-8 minus sign)
  (data (i32.const 26) "\e2\88\92")
  ;; 29: "+" (1)
  (data (i32.const 29) "+")
  ;; 30: "span" (4)
  (data (i32.const 30) "span")
  ;; 34: "count" (5)
  (data (i32.const 34) "count")
  ;; 39: "on_decrement" (12)
  (data (i32.const 39) "on_decrement")
  ;; 51: "on_increment" (12)
  (data (i32.const 51) "on_increment")

  ;; Buffer for itoa at offsets 200-219

  ;; Convert $count global to decimal string in the buffer.
  ;; Returns (ptr, len) suitable for passing straight to $text.
  (func $write_count (result i32 i32)
    (local $n i32)
    (local $pos i32)
    (local $digit i32)
    (local $is_neg i32)

    (local.set $n (global.get $count))
    (local.set $pos (i32.const 219))

    ;; Handle zero
    (if (i32.eqz (local.get $n))
      (then
        (i32.store8 (i32.const 219) (i32.const 48)) ;; '0'
        (i32.const 219)
        (i32.const 1)
        return
      )
    )

    ;; Handle negative
    (if (i32.lt_s (local.get $n) (i32.const 0))
      (then
        (local.set $is_neg (i32.const 1))
        (local.set $n (i32.sub (i32.const 0) (local.get $n)))
      )
    )

    ;; Extract digits right-to-left
    (block $done
      (loop $digits
        (br_if $done (i32.eqz (local.get $n)))

        (local.set $digit (i32.rem_u (local.get $n) (i32.const 10)))
        (i32.store8 (local.get $pos) (i32.add (i32.const 48) (local.get $digit)))
        (local.set $pos (i32.sub (local.get $pos) (i32.const 1)))
        (local.set $n (i32.div_u (local.get $n) (i32.const 10)))

        (br $digits)
      )
    )

    ;; Prepend '-' if negative
    (if (local.get $is_neg)
      (then
        (i32.store8 (local.get $pos) (i32.const 45)) ;; '-'
        (local.set $pos (i32.sub (local.get $pos) (i32.const 1)))
      )
    )

    ;; Return (ptr, len) — feeds directly into (call $text)
    (i32.add (local.get $pos) (i32.const 1))
    (i32.sub (i32.const 219) (local.get $pos))
  )

  (func (export "render")
    ;; <div class="counter">
    (call $open_element (i32.const 0) (i32.const 3))
    (call $attribute (i32.const 3) (i32.const 5) (i32.const 8) (i32.const 7))

    ;; <button onclick="on_decrement"> − </button>
    (call $open_element (i32.const 15) (i32.const 6))
    (call $on_event (i32.const 21) (i32.const 5) (i32.const 39) (i32.const 12))
    (call $text (i32.const 26) (i32.const 3))
    (call $close_element)

    ;; <span class="count"> {count} </span>
    (call $open_element (i32.const 30) (i32.const 4))
    (call $attribute (i32.const 3) (i32.const 5) (i32.const 34) (i32.const 5))
    (call $write_count)
    (call $text)
    (call $close_element)

    ;; <button onclick="on_increment"> + </button>
    (call $open_element (i32.const 15) (i32.const 6))
    (call $on_event (i32.const 21) (i32.const 5) (i32.const 51) (i32.const 12))
    (call $text (i32.const 29) (i32.const 1))
    (call $close_element)

    ;; </div>
    (call $close_element)
  )

  ;; Named event handlers — no dispatch needed
  (func (export "on_decrement")
    (global.set $count (i32.sub (global.get $count) (i32.const 1)))
  )

  (func (export "on_increment")
    (global.set $count (i32.add (global.get $count) (i32.const 1)))
  )
)
