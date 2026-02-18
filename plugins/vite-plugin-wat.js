import { readFileSync } from 'fs';
import { execFileSync } from 'child_process';
import { tmpdir } from 'os';
import { join } from 'path';
import initWabt from 'wabt';

function wasmToJS(buffer) {
  const base64 = Buffer.from(buffer).toString('base64');
  return `
const bytes = Uint8Array.from(atob("${base64}"), c => c.charCodeAt(0));
export default async function init(imports) {
  const { instance } = await WebAssembly.instantiate(bytes, imports);
  return instance;
}
`;
}

export default function watPlugin() {
  let wabtInstance;

  return {
    name: 'vite-plugin-wasm-components',

    async load(id) {
      // .wat files — assemble with wabt
      if (id.endsWith('.wat')) {
        if (!wabtInstance) wabtInstance = await initWabt();

        const watSource = readFileSync(id, 'utf-8');
        const wasmModule = wabtInstance.parseWat(id, watSource);
        const { buffer } = wasmModule.toBinary({});
        wasmModule.destroy();

        return wasmToJS(buffer);
      }

      // .c files — compile with clang targeting wasm32
      if (id.endsWith('.c')) {
        const outPath = join(tmpdir(), `vite-wasm-${Date.now()}.wasm`);

        execFileSync('clang', [
          '--target=wasm32-unknown-unknown',
          '-nostdlib',
          '-O2',
          '-Wl,--no-entry',
          '-Wl,--export-memory',
          '-fuse-ld=/usr/lib/llvm20/bin/wasm-ld',
          '-o', outPath,
          id,
        ]);

        const buffer = readFileSync(outPath);
        return wasmToJS(buffer);
      }

      return null;
    }
  };
}
