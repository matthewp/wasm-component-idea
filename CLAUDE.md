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
- `src/components/dom.zig` — Comptime HTML parser producing canonical ABI opcode structs
- `src/components/*.zig` — Zig components
- `rust-counter/` — Rust standalone counter (pure-component world)
- `rust-counter-child/` — Rust child counter (rust-counter world, for composition)
- `rust-counter-app/` — Rust parent component (counter-app world, composes children)
- `plugins/vite-plugin-zig.js` — Zig build plugin (zig → embed → new → jco transpile)
- `plugins/vite-plugin-rust.js` — Rust build plugin (cargo → embed → new → jco transpile)
- `build.sh` — Standalone build script for all components and composition
