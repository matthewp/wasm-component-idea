#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="$HOME/.cargo/bin:$PATH"

echo "=== Phase 1: Trivial Component ==="

wasm-tools component embed "$ROOT/test/wit/trivial.wit" "$ROOT/test/add.wat" -o "$ROOT/test/add.wasm" --encoding utf8
wasm-tools component new "$ROOT/test/add.wasm" -o "$ROOT/test/add.component.wasm"
npx jco transpile "$ROOT/test/add.component.wasm" -o "$ROOT/test/out/" --no-nodejs-compat

echo "=== Standalone Components (pure-component world) ==="

echo "Building Zig counter..."
zig build-exe "$ROOT/examples/components/zig-counter/counter.zig" -target wasm32-freestanding -fno-entry \
  -femit-bin="$ROOT/test/counter.wasm" --export-memory -fstrip \
  '--export=wasm-components:dom/renderer@0.1.0#render' \
  '--export=wasm-components:dom/renderer@0.1.0#handle-event' \
  '--export=cabi_post_wasm-components:dom/renderer@0.1.0#render' \
  --export=cabi_realloc
wasm-tools component embed "$ROOT/wit/" --world pure-component "$ROOT/test/counter.wasm" -o "$ROOT/test/counter.embedded.wasm" --encoding utf8
wasm-tools component new "$ROOT/test/counter.embedded.wasm" -o "$ROOT/test/counter.component.wasm"
npx jco transpile "$ROOT/test/counter.component.wasm" -o "$ROOT/examples/dist/zig-counter/" --name zig-counter --no-nodejs-compat -q

echo "Building Rust counter..."
(cd "$ROOT/examples/components/rust-counter" && cargo build --target wasm32-unknown-unknown --release 2>&1)
wasm-tools component embed "$ROOT/wit/" --world pure-component \
  "$ROOT/examples/components/rust-counter/target/wasm32-unknown-unknown/release/rust_counter.wasm" \
  -o "$ROOT/test/rust-counter.embedded.wasm" --encoding utf8
wasm-tools component new "$ROOT/test/rust-counter.embedded.wasm" -o "$ROOT/test/rust-counter.component.wasm"
npx jco transpile "$ROOT/test/rust-counter.component.wasm" -o "$ROOT/examples/dist/rust-counter/" --name rust-counter --no-nodejs-compat -q

echo "Building counter-app..."
(cd "$ROOT/examples/components/rust-counter-app" && cargo build --target wasm32-unknown-unknown --release 2>&1)
wasm-tools component embed "$ROOT/wit/" --world pure-component \
  "$ROOT/examples/components/rust-counter-app/target/wasm32-unknown-unknown/release/rust_counter_app.wasm" \
  -o "$ROOT/test/counter-app.embedded.wasm" --encoding utf8
wasm-tools component new "$ROOT/test/counter-app.embedded.wasm" -o "$ROOT/test/counter-app.component.wasm"
npx jco transpile "$ROOT/test/counter-app.component.wasm" -o "$ROOT/examples/dist/counter-app/" --name counter-app --no-nodejs-compat -q

echo "Building Rust todo..."
(cd "$ROOT/examples/components/rust-todo" && cargo build --target wasm32-unknown-unknown --release 2>&1)
~/.cargo/bin/wasm-tools component embed "$ROOT/wit/" --world leaf-component \
  "$ROOT/examples/components/rust-todo/target/wasm32-unknown-unknown/release/rust_todo.wasm" \
  -o "$ROOT/test/rust-todo.embedded.wasm" --encoding utf8
~/.cargo/bin/wasm-tools component new "$ROOT/test/rust-todo.embedded.wasm" -o "$ROOT/test/rust-todo.component.wasm"
npx jco transpile "$ROOT/test/rust-todo.component.wasm" -o "$ROOT/examples/dist/rust-todo/" --name rust-todo --no-nodejs-compat -q \
  -M "wasm-components:dom/host@0.1.0=../../../src/host.js"

# echo "Building Scheme counter..."
# puppyc "$ROOT/examples/components/scheme-counter/counter.scm" "$ROOT/test/scheme-counter.wasm"
# wasm-tools component embed "$ROOT/wit/" --world pure-component "$ROOT/test/scheme-counter.wasm" -o "$ROOT/test/scheme-counter.embedded.wasm" --encoding utf8
# wasm-tools component new "$ROOT/test/scheme-counter.embedded.wasm" -o "$ROOT/test/scheme-counter.component.wasm"
# npx jco transpile "$ROOT/test/scheme-counter.component.wasm" -o "$ROOT/examples/dist/scheme-counter/" --name scheme-counter --no-nodejs-compat -q

echo "Done!"
