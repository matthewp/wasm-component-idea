import { readFileSync } from 'fs';
import { execFileSync } from 'child_process';
import { tmpdir } from 'os';
import { join } from 'path';

function wasmToJS(buffer) {
  const base64 = Buffer.from(buffer).toString('base64');
  return `
const bytes = Uint8Array.from(atob("${base64}"), c => c.charCodeAt(0));
const compiled = await WebAssembly.compile(bytes);
export default function init(hostImports, otherImports) {
  return new WebAssembly.Instance(compiled, { ...hostImports, ...otherImports });
}
`;
}

export default function zigPlugin() {
  return {
    name: 'vite-plugin-zig',

    load(id) {
      if (!id.endsWith('.zig')) return null;

      const outPath = join(tmpdir(), `vite-wasm-${Date.now()}.wasm`);
      const source = readFileSync(id, 'utf-8');
      const exports = [...source.matchAll(/export fn (\w+)/g)].map(m => `--export=${m[1]}`);

      execFileSync('zig', [
        'build-exe',
        '-target', 'wasm32-freestanding',
        '-fno-entry',
        '-O', 'ReleaseSmall',
        '--export-table',
        `-femit-bin=${outPath}`,
        ...exports,
        id,
      ]);

      return wasmToJS(readFileSync(outPath));
    }
  };
}
