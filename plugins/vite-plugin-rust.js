import { readFileSync, existsSync } from 'fs';
import { execFileSync } from 'child_process';
import { tmpdir } from 'os';
import { join, dirname } from 'path';

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

export default function rustPlugin() {
  return {
    name: 'vite-plugin-rust',

    load(id) {
      if (!id.endsWith('.rs')) return null;

      const outPath = join(tmpdir(), `vite-wasm-${Date.now()}.wasm`);
      const source = readFileSync(id, 'utf-8');

      const args = [
        '--target', 'wasm32-unknown-unknown',
        '--crate-type', 'cdylib',
        '--edition', '2021',
        '-C', 'opt-level=s',
        '-C', 'lto=yes',
        '-C', 'strip=symbols',
        '-o', outPath,
      ];

      if (source.includes('wasm_html_macro')) {
        const macroDir = join(dirname(id), '..', '..', 'wasm-html-macro');
        if (existsSync(macroDir)) {
          execFileSync('cargo', ['build', '--release'], { cwd: macroDir });
          const libPath = join(macroDir, 'target/release/libwasm_html_macro.so');
          args.push('--extern', `wasm_html_macro=${libPath}`);
        }
      }

      args.push(id);
      execFileSync('rustc', args);

      return wasmToJS(readFileSync(outPath));
    }
  };
}
