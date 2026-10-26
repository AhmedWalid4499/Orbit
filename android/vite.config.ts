// Builds the Android web bundle: the Windows app's screens (windows/src/renderer/src, imported as "@")
// with this folder's Android shell and bridge. Every package resolves from android/node_modules, so the
// Windows install isn't needed and React is never loaded twice.
import { resolve } from 'path'
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

const here = (p: string) => resolve(__dirname, p)
const shared = ['react', 'react-dom', 'lucide-react', 'pdfjs-dist', 'qrcode', '@fontsource/inter', '@fontsource/fraunces', '@anthropic-ai/sdk']

export default defineConfig({
  root: here('.'),
  base: './',
  resolve: {
    alias: [
      { find: '@', replacement: here('../windows/src/renderer/src') },
      { find: '~', replacement: here('src') },
      ...shared.map((m) => ({ find: new RegExp(`^${m.replace('/', '\\/')}(?=/|$)`), replacement: here(`node_modules/${m}`) })),
    ],
    dedupe: ['react', 'react-dom'],
  },
  plugins: [react()],
  build: { outDir: 'dist', emptyOutDir: true, target: 'es2020', chunkSizeWarningLimit: 4000 },
  server: { port: 5199, fs: { allow: [here('..')] } },
})
