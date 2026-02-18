import { defineConfig } from 'vite';
import watPlugin from './plugins/vite-plugin-wat.js';

export default defineConfig({
  plugins: [watPlugin()],
});
