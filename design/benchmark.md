# Road to js-framework-benchmark

Target: [krausest/js-framework-benchmark](https://github.com/krausest/js-framework-benchmark)

The benchmark tests create/append/clear/swap/delete on 1k–10k row tables, row selection, and single-row updates. It's the standard perf test for UI frameworks.

Our current runtime can do initial DOM build and slot text updates. That's it. Below are the gaps, each with a standalone example app to build and prove out before we attempt the full benchmark.

---

## Gap 1: Dynamic attributes

**Problem:** Attributes are set once at DOM build time. The benchmark requires toggling a `class="danger"` on the selected row.

**Example app:** A list of 3–5 items. Clicking one highlights it (sets class), clicking another moves the highlight. Proves we can update attributes on re-render, not just text.

**What changes:**
- New opcode or slot mechanism for attributes that can change between renders
- Runtime tracks mutable attribute bindings and patches them on re-render

---

## Gap 2: Event context

**Problem:** `handle-event(handler: string)` tells the component *what* happened but not *where*. Clicking row 42's delete button just fires `"delete"` — the component has no idea which row.

**Example app:** A list of items with a delete button on each. Clicking delete removes that specific item. Proves the component can receive event context.

**What changes:**
- Extend the protocol so events can carry context back to the component (e.g. a data attribute value, or an event payload string)
- Minimal WIT change — possibly `handle-event(handler: string, detail: string)` or a host function like `event-data(attr: string) -> string`

---

## Gap 3: List rendering

**Problem:** `render()` returns a flat opcode list. The runtime builds DOM once and never adds/removes nodes. The benchmark creates 1,000–10,000 rows and then appends, clears, and deletes individual rows.

**Example app:** A simple list with "add item" and "clear" buttons. Grows from 0 to N items. Proves the runtime can reconcile structural changes — adding new DOM nodes, removing old ones.

**What changes:**
- Runtime needs a reconciliation strategy for re-renders that change DOM structure
- Options: full rebuild (simple, baseline), or incremental patch (fast, complex)
- Start with non-keyed (reuse DOM nodes for different data) since it's simpler

---

## Gap 4: Event delegation

**Problem:** Attaching an event listener per row means 20k listeners for 10k rows. That kills performance and memory.

**Example app:** Same list app from Gap 3, but at 1k+ rows with click-to-select. Proves event delegation works at scale.

**What changes:**
- Runtime registers one listener on a parent element and resolves the target row
- The opcode stream marks which events should be delegated vs direct-bound
- Or: runtime auto-delegates events inside list regions

---

## Gap 5: Benchmark app

**Depends on:** Gaps 1–4 all working.

Once the above are solid, build the actual benchmark implementation:

- Non-keyed implementation under `frameworks/non-keyed/wasm-component-protocol/`
- Standard HTML shell with the required button IDs and table structure
- Rust or Zig component managing the row data model
- Runtime handling all DOM operations

### Benchmark operations

| Operation | What it tests |
|-----------|--------------|
| Create 1,000 rows | List rendering from empty |
| Create 10,000 rows | List rendering at scale |
| Append 1,000 rows | Adding to existing list |
| Update every 10th row | Partial text update (slot-like) |
| Select row | Dynamic attribute (class toggle) |
| Swap rows | Reorder within list |
| Remove row | Single item deletion |
| Clear | Remove all rows |

### Row HTML structure (required by benchmark)

```html
<tr>
    <td class="col-md-1">1</td>
    <td class="col-md-4"><a>pretty red table</a></td>
    <td class="col-md-1">
        <a><span class="glyphicon glyphicon-remove" aria-hidden="true"></span></a>
    </td>
    <td class="col-md-6"></td>
</tr>
```

---

## Order of work

1. **Gap 1** — dynamic attributes (small, foundational)
2. **Gap 2** — event context (small, foundational)
3. **Gap 3** — list rendering (big, core capability)
4. **Gap 4** — event delegation (performance, needed at scale)
5. **Gap 5** — benchmark app (integration, the goal)

Each gap is a standalone example app that proves the capability before we move on.
