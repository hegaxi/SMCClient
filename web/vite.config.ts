import { defineConfig } from 'vitest/config';
import react from '@vitejs/plugin-react';

// En desarrollo, /api se envía a la API (dotnet run en http://localhost:5080).
// El build se publica dentro de la API (wwwroot): una sola aplicación en IIS.
export default defineConfig({
  plugins: [react()],
  server: {
    proxy: {
      '/api': 'http://localhost:5080',
      '/salud': 'http://localhost:5080',
    },
  },
  build: {
    outDir: '../src/SMCClient.Api/wwwroot',
    emptyOutDir: true,
  },
  test: {
    environment: 'jsdom',
    globals: true,
    setupFiles: ['./src/pruebas/setup.ts'],
  },
});
