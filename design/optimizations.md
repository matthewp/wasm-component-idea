# Optimization Tracking

Benchmark: js-framework-benchmark (non-keyed), comparing against vanillajs.

## Current results

| Benchmark | Vanilla | WASM | Ratio |
|---|---|---|---|
| create 1k | 55.2ms | 60.4ms | 1.1x |
| replace 1k | 33.6ms | 34.9ms | 1.0x |
| update 10th | 39.2ms | 61.9ms | 1.6x |
| select row | 6.1ms | 37.0ms | 6.1x |
| swap rows | 30.9ms | 50.9ms | 1.6x |
| remove one | 64.6ms | 54.9ms | 0.8x |
| create 10k | 579.4ms | 639.6ms | 1.1x |
| append 1k | 63.0ms | 80.9ms | 1.3x |
| clear 1k | 24.8ms | 36.1ms | 1.5x |

## Completed optimizations

### Template caching + compact re-render

**Problem**: Every `render()` call sent ALL opcodes (static + dynamic) across the WASM-JS ABI boundary. For 1000 rows with ~20 opcodes each, that's ~21,000 opcodes serialized and walked — even when only 2 class attributes change.

**Solution**: Two-part optimization:
1. **Runtime template caching** (`src/runtime.js`): After the first instance of a begin/end group is built, cache a `<template>` element. New instances use `cloneNode(true)` instead of element-by-element construction.
2. **Compact re-render** (`rust-bench/src/lib.rs`): After the first full render, subsequent renders send only `begin` + dynamic parts + `end` per row (7 opcodes) instead of all static+dynamic opcodes (~20 per row).

**Result**: Reduced opcode count from ~21,000 to ~7,000 for 1000 rows. Select row improved from 10.5x to 6.1x. Replace and create benchmarks also improved.

## Open problems

### Select row is still 6.1x (target: ~2x)

**Root cause**: O(n) full scan when only O(1) work is needed.

When selecting a row, only 2 DOM mutations happen: the old selected row loses `class="danger"`, the new one gains it. But both sides still do work proportional to the full list:

- **Rust side**: `compact_render` iterates all 1000 rows, allocates 7000 opcodes, serializes them across the ABI boundary.
- **JS runtime side**: Loops through all 1000 instances, comparing all 5 parts each (5000 string comparisons) to find the 2 that actually changed.

Vanillajs does ~6ms because it directly toggles the class on the 2 affected rows with no diffing.

**Possible approaches**:
- **Dirty-tracking in the component**: The component knows which rows changed (e.g. old selected + new selected). It could emit opcodes for only those rows, with an index or ID to tell the runtime which instances to update.
- **Skip-opcode**: A new opcode like `skip(n)` that tells the runtime to advance `n` instances without sending their parts. Select would emit: `skip(old_idx), begin, parts, end, skip(new_idx - old_idx - 1), begin, parts, end, skip(remaining)`.
- **Partial re-render at the protocol level**: A mechanism for the component to say "only these instances changed" without walking the entire list.

### Update every 10th row is 1.6x

Same O(n) scan problem. Only 100 labels change out of 1000 rows, but we send and diff all 5000 parts.

### Swap rows is 1.6x

Same pattern — 2 rows swap but all 1000 are diffed.

### Clear is 1.5x

Compact render sends an empty opcode list. The runtime trims all instances. The overhead is likely the trimming loop removing 1000 instances' DOM nodes one at a time. Could potentially be optimized with a single `replaceChildren()` or `innerHTML = ''` on the parent.

### Append 1k is 1.3x

Template cloning helps here (1000 `cloneNode` calls), but each clone still requires a DFS walk to wire up 5 parts. The DFS walk + `indexOf` lookups in `cloneFromTemplate` may be a bottleneck at scale.
