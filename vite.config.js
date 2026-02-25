import { defineConfig } from 'vite';
import zigPlugin from './plugins/vite-plugin-zig.js';
import rustPlugin from './plugins/vite-plugin-rust.js';

export default defineConfig({
  root: 'examples',
  plugins: [zigPlugin(), rustPlugin()],
});
