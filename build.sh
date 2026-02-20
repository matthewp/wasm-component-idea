#!/bin/bash
set -euo pipefail

export PATH="$HOME/.cargo/bin:$PATH"

echo "=== Phase 1: Trivial Component ==="

wasm-tools component embed test/wit/trivial.wit test/add.wat -o test/add.wasm --encoding utf8
wasm-tools component new test/add.wasm -o test/add.component.wasm
npx jco transpile test/add.component.wasm -o test/out/ --no-nodejs-compat

echo "=== Standalone Components (pure-component world) ==="

echo "Building Zig counter..."
zig build-exe src/components/counter.zig -target wasm32-freestanding -fno-entry \
  -femit-bin=test/counter.wasm --export-memory -fstrip \
  '--export=wasm-components:dom/renderer@0.1.0#render' \
  '--export=wasm-components:dom/renderer@0.1.0#handle-event' \
  '--export=cabi_post_wasm-components:dom/renderer@0.1.0#render' \
  --export=cabi_realloc
wasm-tools component embed wit/ --world pure-component test/counter.wasm -o test/counter.embedded.wasm --encoding utf8
wasm-tools component new test/counter.embedded.wasm -o test/counter.component.wasm
npx jco transpile test/counter.component.wasm -o dist/zig-counter/ --name zig-counter --no-nodejs-compat -q

echo "Building Rust counter..."
(cd rust-counter && cargo build --target wasm32-unknown-unknown --release 2>&1)
wasm-tools component embed wit/ --world pure-component \
  rust-counter/target/wasm32-unknown-unknown/release/rust_counter.wasm \
  -o test/rust-counter.embedded.wasm --encoding utf8
wasm-tools component new test/rust-counter.embedded.wasm -o test/rust-counter.component.wasm
npx jco transpile test/rust-counter.component.wasm -o dist/rust-counter/ --name rust-counter --no-nodejs-compat -q

echo "Building counter-app..."
(cd rust-counter-app && cargo build --target wasm32-unknown-unknown --release 2>&1)
wasm-tools component embed wit/ --world pure-component \
  rust-counter-app/target/wasm32-unknown-unknown/release/rust_counter_app.wasm \
  -o test/counter-app.embedded.wasm --encoding utf8
wasm-tools component new test/counter-app.embedded.wasm -o test/counter-app.component.wasm
npx jco transpile test/counter-app.component.wasm -o dist/counter-app/ --name counter-app --no-nodejs-compat -q

echo "Building Rust todo..."
(cd rust-todo && cargo build --target wasm32-unknown-unknown --release 2>&1)
~/.cargo/bin/wasm-tools component embed wit/ --world leaf-component \
  rust-todo/target/wasm32-unknown-unknown/release/rust_todo.wasm \
  -o test/rust-todo.embedded.wasm --encoding utf8
~/.cargo/bin/wasm-tools component new test/rust-todo.embedded.wasm -o test/rust-todo.component.wasm
npx jco transpile test/rust-todo.component.wasm -o dist/rust-todo/ --name rust-todo --no-nodejs-compat -q \
  -M 'wasm-components:dom/host@0.1.0=../../src/host.js'

echo "Done!"
