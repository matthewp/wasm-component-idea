#include "idom.h"

static int count = 0;

HANDLER(on_decrement) { count--; }
HANDLER(on_increment) { count++; }

EXPORT render() {
  EL("div") {
    ATTR("class", "counter");

    EL("button") {
      ON("click", on_decrement);
      TEXT("\xe2\x88\x92");
    } END;

    EL("span") {
      ATTR("class", "count");
      text_int(count);
    } END;

    EL("button") {
      ON("click", on_increment);
      TEXT("+");
    } END;
  } END;
}
