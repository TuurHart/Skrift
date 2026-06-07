import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import path from 'path'

export default defineConfig({
  plugins: [react()],
  resolve: {
    alias: {
      '@': path.resolve(__dirname, './src'),
    },
  },
  base: './',           // required for Electron file:// loading in production
  build: {
    outDir: 'renderer-dist',
    emptyOutDir: true,
  },
  server: {
    port: 5173,
  },
})
