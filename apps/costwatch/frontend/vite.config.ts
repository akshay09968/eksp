import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

export default defineConfig({
  plugins: [react()],
  build: {
    // Emit straight into the Go embed tree (ADR-0015): one binary ships both.
    outDir: '../backend/web/dist',
    emptyOutDir: true,
    rollupOptions: {
      output: {
        manualChunks: {
          // Recharts (+ its d3 underpinnings) dwarfs the app code; splitting it
          // lets the shell paint while the chart lib streams (AUDIT P2-15).
          charts: ['recharts'],
        },
      },
    },
  },
  server: {
    proxy: {
      // `npm run dev` against a locally running backend (`make costwatch-demo`)
      '/api': 'http://localhost:8080',
    },
  },
});
