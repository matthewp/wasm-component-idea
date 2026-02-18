# WASM Component Protocol

We are building a **protocol** and a **runtime** for that protocol. The protocol defines how WASM components describe DOM via an opcode buffer.

## Architecture Rules

1. **Host imports are the protocol.** The only functions the host provides to WASM modules are the ones defined by the protocol: the opcode-based rendering interface and `event_target_value`. Do NOT add custom host functions without discussing with me first.

2. **Vite plugin must be minimal.** It compiles source files to WASM and wraps them as JS modules. That's it. The plugin is a prototype build tool, not part of the architecture. Do not add complexity to the build to solve runtime problems.

3. **Use standard WASM APIs only.** WASM has imports, exports, memory, tables — use those. Do not invent custom APIs or conventions on top. If you think a new API is needed, discuss it first.

4. **render() is a pure function.** It returns a pointer to a u32 opcode buffer in linear memory. The host reads it. No side effects, no host calls during render.

## Opcode Protocol

All values are u32-aligned. Format: opcode followed by arguments.

- `1` OPEN — tag_ptr, tag_len
- `2` CLOSE
- `3` ATTR — name_ptr, name_len, val_ptr, val_len
- `4` TEXT — ptr, len
- `5` SLOT — ptr, len
- `6` EVENT — type_ptr, type_len, handler_ptr, handler_len
- `7` COMPONENT — (args TBD, composition design not finalized)
- `0` END

## Project Structure

- `src/runtime.js` — Host runtime that processes opcode buffers
- `src/components/dom.zig` — Comptime HTML parser and opcode buffer generator
- `src/components/*.zig` — Zig components
- `src/components/*.rs` — Rust components
- `src/components/*.wat` — WAT components
- `plugins/vite-plugin-wat.js` — Minimal build plugin
- `wasm-html-macro/` — Rust proc macro for HTML templates
