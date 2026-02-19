import { readFileSync, existsSync } from 'fs';
import { execFileSync } from 'child_process';
import { tmpdir } from 'os';
import { join, resolve, dirname } from 'path';

const witDir = resolve(import.meta.dirname, '..', 'wit');
const cargobin = join(process.env.HOME, '.cargo', 'bin');
const env = { ...process.env, PATH: `${cargobin}:${process.env.PATH}` };

export default function rustPlugin() {
  return {
    name: 'vite-plugin-rust',

    load(id) {
      if (!id.endsWith('.rs')) return null;

      const ts = Date.now();
      const embeddedWasm = join(tmpdir(), `vite-rust-${ts}.embedded.wasm`);
      const componentWasm = join(tmpdir(), `vite-rust-${ts}.component.wasm`);
      const outDir = join(tmpdir(), `vite-rust-${ts}-out`);

      const source = readFileSync(id, 'utf-8');

      const crateDir = findCargoProject(dirname(id));
      if (!crateDir) {
        throw new Error(`No Cargo.toml found for ${id}`);
      }

      // 1. Build with Cargo
      execFileSync('cargo', ['build', '--target', 'wasm32-unknown-unknown', '--release'], {
        cwd: crateDir, env,
      });

      const crateName = getCrateName(crateDir);
      const coreWasm = join(crateDir, 'target/wasm32-unknown-unknown/release', `${crateName}.wasm`);

      // Determine world from source
      let world = 'pure-component';
      if (source.includes('"counter-app"')) world = 'counter-app';
      else if (source.includes('"rust-counter"')) world = 'rust-counter';

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

function findCargoProject(dir) {
  while (dir !== '/') {
    if (existsSync(join(dir, 'Cargo.toml'))) return dir;
    dir = dirname(dir);
  }
  return null;
}

function getCrateName(crateDir) {
  const toml = readFileSync(join(crateDir, 'Cargo.toml'), 'utf-8');
  const match = toml.match(/name\s*=\s*"([^"]+)"/);
  return match ? match[1].replace(/-/g, '_') : 'unknown';
}
