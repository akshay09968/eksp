import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

export default defineConfig({
  plugins: [react()],
  build: {
    // Emit straight into the Go embed tree (ADR-0015): one binary ships both.
    outDir: '../backend/web/dist',
    emptyOutDir: true,
  },
  server: {
    proxy: {
      // `npm run dev` against a locally running backend (`make costwatch-demo`)
      '/api': 'http://localhost:8080',
    },
  },
});
