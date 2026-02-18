#ifndef IDOM_H
#define IDOM_H

// --- Host imports (provided by the JS runtime) ---

// Shared: used by both incremental-DOM and template definition
__attribute__((import_module("host"), import_name("open_element")))
void _open_element(const char* tag, int len);

__attribute__((import_module("host"), import_name("close_element")))
void _close_element(void);

__attribute__((import_module("host"), import_name("attribute")))
void _attribute(const char* name, int name_len, const char* val, int val_len);

__attribute__((import_module("host"), import_name("text")))
void _text(const char* s, int len);

__attribute__((import_module("host"), import_name("on_event")))
void _on_event(const char* type, int type_len, const char* name, int name_len);

// Template system
__attribute__((import_module("host"), import_name("create_template")))
void _create_template(int id);

__attribute__((import_module("host"), import_name("slot")))
void _slot(void);

__attribute__((import_module("host"), import_name("end_template")))
void _end_template(void);

__attribute__((import_module("host"), import_name("update")))
void _update(int template_id);

__attribute__((import_module("host"), import_name("value")))
void _value(const char* s, int len);

__attribute__((import_module("host"), import_name("commit")))
void _commit(void);

// --- DSL macros ---

// Structure (works in both incremental-DOM render and template definition)
#define EL(tag)          _open_element(tag, sizeof(tag) - 1);
#define END              _close_element()
#define ATTR(name, val)  _attribute(name, sizeof(name) - 1, val, sizeof(val) - 1)
#define TEXT(s)          _text(s, sizeof(s) - 1)
#define ON(event, fn)    _on_event(event, sizeof(event) - 1, #fn, sizeof(#fn) - 1)

// Template definition (used inside INIT)
#define TEMPLATE(id)     _create_template(id);
#define END_TEMPLATE     _end_template()
#define SLOT             _slot()

// Template render (used inside render)
#define UPDATE(id)       _update(id)
#define VALUE(s)         _value(s, sizeof(s) - 1)
#define COMMIT           _commit()

// Function decorators
#define INIT \
  __attribute__((export_name("init"))) \
  void init(void)

#define HANDLER(name) \
  __attribute__((export_name(#name))) \
  void name(void)

#define EXPORT \
  __attribute__((export_name("render"))) \
  void

// --- Helpers ---

static char _itoa_buf[20];

static void text_int(int n) {
  char* end = _itoa_buf + sizeof(_itoa_buf);
  char* p = end;
  int neg = 0;
  if (n == 0) { _text("0", 1); return; }
  if (n < 0) { neg = 1; n = -n; }
  while (n > 0) { *--p = '0' + (n % 10); n /= 10; }
  if (neg) *--p = '-';
  _text(p, end - p);
}

static void value_int(int n) {
  char* end = _itoa_buf + sizeof(_itoa_buf);
  char* p = end;
  int neg = 0;
  if (n == 0) { _value("0", 1); return; }
  if (n < 0) { neg = 1; n = -n; }
  while (n > 0) { *--p = '0' + (n % 10); n /= 10; }
  if (neg) *--p = '-';
  _value(p, end - p);
}

#endif
