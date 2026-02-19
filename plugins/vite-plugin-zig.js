import { readFileSync } from 'fs';
import { execFileSync } from 'child_process';
import { tmpdir } from 'os';
import { join, resolve } from 'path';

const witDir = resolve(import.meta.dirname, '..', 'wit');
const cargobin = join(process.env.HOME, '.cargo', 'bin');
const env = { ...process.env, PATH: `${cargobin}:${process.env.PATH}` };

export default function zigPlugin() {
  return {
    name: 'vite-plugin-zig',

    load(id) {
      if (!id.endsWith('.zig')) return null;

      const ts = Date.now();
      const coreWasm = join(tmpdir(), `vite-zig-${ts}.wasm`);
      const embeddedWasm = join(tmpdir(), `vite-zig-${ts}.embedded.wasm`);
      const componentWasm = join(tmpdir(), `vite-zig-${ts}.component.wasm`);
      const outDir = join(tmpdir(), `vite-zig-${ts}-out`);

      const source = readFileSync(id, 'utf-8');

      // Collect all exports (both @"special" and plain names)
      const specialExports = [...source.matchAll(/export fn @"([^"]+)"/g)].map(m => `--export=${m[1]}`);
      const plainExports = [...source.matchAll(/export fn (\w+)/g)].map(m => `--export=${m[1]}`);

      // Always export cabi_realloc (may come from imported dom.zig)
      const allExports = [...specialExports, ...plainExports];
      if (!allExports.some(e => e.includes('cabi_realloc'))) {
        allExports.push('--export=cabi_realloc');
      }

      // 1. Compile Zig to core wasm
      execFileSync('zig', [
        'build-exe',
        '-target', 'wasm32-freestanding',
        '-fno-entry',
        '-O', 'ReleaseSmall',
        '--export-memory',
        `-femit-bin=${coreWasm}`,
        ...allExports,
        id,
      ], { env });

      // Determine world from exports
      let world = 'pure-component';
      if (source.includes('zig-child@')) world = 'zig-counter';
      else if (source.includes('rust-child@')) world = 'rust-counter';

      // 2. Embed WIT
      execFileSync('wasm-tools', [
        'component', 'embed', witDir, '--world', world,
        coreWasm, '-o', embeddedWasm, '--encoding', 'utf8',
      ], { env });

      // 3. Create component
      execFileSync('wasm-tools', ['component', 'new', embeddedWasm, '-o', componentWasm], { env });

      // 4. Transpile with jco (inline wasm as base64)
      execFileSync('npx', [
        'jco', 'transpile', componentWasm,
        '-o', outDir,
        '--name', 'component',
        '--no-nodejs-compat',
        '-b', '10000000',
        '-q',
      ], { env });

      return readFileSync(join(outDir, 'component.js'), 'utf-8');
    }
  };
}
