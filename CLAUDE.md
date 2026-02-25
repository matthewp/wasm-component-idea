# WASM Component Protocol

We are building a **protocol** and a **runtime** for that protocol. Components describe DOM via a WIT-defined opcode variant, using the WebAssembly Component Model for cross-language interop and composition.

## Architecture Rules

1. **The WIT interface is the protocol.** All component interaction is defined in `wit/dom.wit`. Components export `render() -> list<opcode>` and `handle-event(handler: string)`. Do NOT add custom host functions without discussing with me first.

2. **Vite plugins must be minimal.** They compile source to WASM, run `wasm-tools` embed/new, and `jco transpile`. The plugins are a prototype build tool, not part of the architecture.

3. **Use the Component Model.** Cross-language composition, memory isolation, and string serialization are handled by the canonical ABI. Do not invent custom conventions on top.

4. **render() is a pure function.** It returns a `list<opcode>`. No side effects, no host calls during render.

## WIT Protocol (`wit/dom.wit`)

```wit
variant opcode {
    open(string),
    close,
    attr(tuple<string, string>),
    text(string),
    slot(string),
    event(tuple<string, string>),
}
```

## Project Structure

- `wit/dom.wit` — WIT interface definitions (types, renderer, host, child interfaces, worlds)
- `src/runtime.js` — Host runtime that processes structured JS opcode objects from jco
- `src/host.js` — Host function implementations for leaf components
- `plugins/vite-plugin-zig.js` — Zig build plugin (zig → embed → new → jco transpile)
- `plugins/vite-plugin-rust.js` — Rust build plugin (cargo → embed → new → jco transpile)
- `examples/` — Demo app and all example components
  - `index.html` — Main demo page
  - `bench.html` — Benchmark page
  - `main.js` — Demo app entry point
  - `bench.js` — Benchmark entry point
  - `build.sh` — Standalone build script for all components
  - `dist/` — Build output (not tracked)
  - `components/zig-counter/` — Zig counter (dom.zig comptime HTML parser + counter.zig)
  - `components/scheme-counter/` — Scheme counter
  - `components/rust-counter/` — Rust standalone counter (pure-component world)
  - `components/rust-counter-child/` — Rust child counter (rust-counter world, for composition)
  - `components/rust-counter-app/` — Rust parent component (counter-app world, composes children)
  - `components/rust-todo/` — Rust todo app (leaf-component world)
  - `components/rust-bench/` — Rust benchmark component for js-framework-benchmark
  - `components/wasm-html-macro/` — Proc macro for HTML-in-Rust syntax
- `js-framework-benchmark/` — Fork of the benchmark suite (git submodule)
- `design/optimizations.md` — Benchmark results and optimization tracking

## Running Benchmarks

```bash
# 1. Build the benchmark component (compiles Rust, embeds WIT, transpiles with jco, copies runtime)
cd js-framework-benchmark/frameworks/non-keyed/wasm-component-protocol
bash build-prod.sh

# 2. Start the benchmark server (leave running in background)
cd js-framework-benchmark
npm start

# 3. Run benchmarks (in another terminal, from js-framework-benchmark/)
cd js-framework-benchmark/webdriver-ts
LANG="en_US.UTF-8" node dist/benchmarkRunner.js --framework non-keyed/wasm-component-protocol --chromeBinary /usr/bin/chromium

# Run against vanillajs for comparison
LANG="en_US.UTF-8" node dist/benchmarkRunner.js --framework non-keyed/vanillajs --chromeBinary /usr/bin/chromium
```

Results are written to `js-framework-benchmark/webdriver-ts/results/`.
