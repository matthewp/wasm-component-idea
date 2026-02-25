;; Counter component — Scheme (Puppy)
;;
;; Exports render(props) -> list<opcode> and handle-event(handler).
;; Uses a quasiquote DSL to produce opcode lists matching the WIT protocol.

;; ---- Opcode constructors ----
;; Each returns a tagged list that the canonical ABI layer will
;; serialize into the opcode variant layout.

(define (open tag)       (list 'open tag))
(define (close-tag)      (list 'close))
(define (attr name val)  (list 'attr name val))
(define (text str)       (list 'text str))
(define (slot str)       (list 'slot str))
(define (event typ name) (list 'event typ name))

;; ---- HTML macro ----
;; Translates s-expression markup into flat opcode lists.
;;
;;   (html (div (@ (class "counter"))
;;           (button (@ (on:click "dec")) "-")
;;           (span (@ (class "count")) ,(number->string count))
;;           (button (@ (on:click "inc")) "+")))
;;
;; The (@ ...) form denotes attributes. Bare strings become text nodes.
;; Unquoted expressions (via quasiquote) are emitted as slot opcodes.

(define-syntax html
  (syntax-rules (@)
    ;; Entry: wrap body in a list and flatten
    ((html body)
     (flatten (html-node body)))))

(define-syntax html-node
  (syntax-rules (@ on:)
    ;; Element with attributes and children
    ((html-node (tag (@ attr ...) child ...))
     (list (open (symbol->string 'tag))
           (html-attrs attr ...)
           (html-children child ...)
           (close-tag)))

    ;; Element with children only (no attributes)
    ((html-node (tag child ...))
     (list (open (symbol->string 'tag))
           (html-children child ...)
           (close-tag)))

    ;; Bare string -> text node
    ((html-node str)
     (list (text str)))))

(define-syntax html-attrs
  (syntax-rules (on:)
    ((html-attrs) '())

    ;; Event attribute: (on:click "handler")
    ((html-attrs (on:type handler) rest ...)
     (cons (event (symbol->string 'type) handler)
           (html-attrs rest ...)))

    ;; Regular attribute: (class "foo")
    ((html-attrs (name value) rest ...)
     (cons (attr (symbol->string 'name) value)
           (html-attrs rest ...)))))

(define-syntax html-children
  (syntax-rules ()
    ((html-children) '())
    ((html-children child rest ...)
     (append (html-node child) (html-children rest ...)))))

(define (flatten lst)
  (cond
    ((null? lst) '())
    ((pair? (car lst)) (append (flatten (car lst)) (flatten (cdr lst))))
    (else (cons (car lst) (flatten (cdr lst))))))

;; ---- Canonical ABI serialization ----
;; Each opcode is 32 bytes:
;; [tag:u8][pad:7][f0_ptr:u32][f0_len:u32][f1_ptr:u32][f1_len:u32][reserved:8]

(define ret-area (make-bytevector 8))

(define (string->mem str)
  (let* ((len (string-length str))
         (bv (make-bytevector len)))
    (bytevector-copy-string! bv 0 str)
    (cons (bytevector->pointer bv) len)))

(define no-string (cons 0 0))

(define (count-opcodes lst)
  (cond
    ((null? lst) 0)
    ((symbol? (car lst)) (+ 1 (count-opcodes (cdr lst))))
    (else (count-opcodes (cdr lst)))))

(define (write-opcode! bv idx tag f0 f1)
  (let ((off (* idx 32)))
    (bytevector-u8-set! bv off tag)
    (bytevector-u32-native-set! bv (+ off 8) (car f0))
    (bytevector-u32-native-set! bv (+ off 12) (cdr f0))
    (bytevector-u32-native-set! bv (+ off 16) (car f1))
    (bytevector-u32-native-set! bv (+ off 20) (cdr f1))))

(define (write-opcodes! bv idx lst)
  (cond
    ((null? lst) idx)
    ((eq? (car lst) 'close)
     (write-opcode! bv idx 1 no-string no-string)
     (write-opcodes! bv (+ idx 1) (cdr lst)))
    ((eq? (car lst) 'open)
     (write-opcode! bv idx 0 (string->mem (cadr lst)) no-string)
     (write-opcodes! bv (+ idx 1) (cddr lst)))
    ((eq? (car lst) 'text)
     (write-opcode! bv idx 3 (string->mem (cadr lst)) no-string)
     (write-opcodes! bv (+ idx 1) (cddr lst)))
    ((eq? (car lst) 'slot)
     (write-opcode! bv idx 4 (string->mem (cadr lst)) no-string)
     (write-opcodes! bv (+ idx 1) (cddr lst)))
    ((eq? (car lst) 'attr)
     (write-opcode! bv idx 2 (string->mem (cadr lst)) (string->mem (caddr lst)))
     (write-opcodes! bv (+ idx 1) (cdddr lst)))
    ((eq? (car lst) 'event)
     (write-opcode! bv idx 5 (string->mem (cadr lst)) (string->mem (caddr lst)))
     (write-opcodes! bv (+ idx 1) (cdddr lst)))
    (else (write-opcodes! bv idx (cdr lst)))))

(define (serialize-opcodes opcodes)
  (let* ((n (count-opcodes opcodes))
         (bv (make-bytevector (* n 32))))
    (write-opcodes! bv 0 opcodes)
    (bytevector-u32-native-set! ret-area 0 (bytevector->pointer bv))
    (bytevector-u32-native-set! ret-area 4 n)
    (bytevector->pointer ret-area)))

;; ---- cabi_realloc (canonical ABI allocator) ----

(define-external (cabi_realloc (i32 old-ptr) (i32 old-size) (i32 align) (i32 new-size)) i32
  (linear-alloc align new-size))

;; ---- Component state ----

(define count 0)

;; ---- render ----

(define-external (render (i32 props-ptr) (i32 props-len)) i32
  (serialize-opcodes
    (html (div (@ (class "counter"))
            (button (@ (on:click "on_decrement")) "-")
            (span (@ (class "count")) ,(number->string count))
            (button (@ (on:click "on_increment")) "+")))))

;; ---- handle-event ----

(define-external (handle-event (i32 ptr) (i32 len)) i32
  (let ((handler (pointer->string ptr len)))
    (cond
      ((equal? handler "on_decrement")
       (if (> count 0)
         (set! count (- count 1))))
      ((equal? handler "on_increment")
       (set! count (+ count 1))))))
