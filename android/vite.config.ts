// Builds the Android web bundle: the Windows app's screens (windows/src/renderer/src, imported as "@")
// with this folder's Android shell and bridge. Every package resolves from android/node_modules, so the
// Windows install isn't needed and React is never loaded twice.
import { resolve } from 'path'
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

const here = (p: string) => resolve(__dirname, p)
const shared = ['react', 'react-dom', 'lucide-react', 'pdfjs-dist', 'qrcode', '@fontsource/inter', '@fontsource/fraunces', '@anthropic-ai/sdk']

/** The app is shown as "Joshu"; the shared screens still say "Orbit" (internal names, URLs and keys stay as they are). */
const joshu = {
  name: 'joshu-display-name',
  enforce: 'pre' as const,
  transform(code: string, id: string) {
    if (!id.includes('/windows/src/renderer/src/') || !/\.tsx?$/.test(id)) return null
    return code
      .replace(/(?<![\/\w.-])Orbit(?![\w\/])/g, 'Joshu')
      .replace(/>orbit<i \/>/g, '>joshu<i />')
      .replace(/on this PC/g, 'on this phone')
      // The AI comes with Joshu Pro now (no key to add), as on the Mac and iPhone.
      .replace('Add your Anthropic API key, or unlock the keys synced from your Mac, in Settings › AI.', 'Part of Joshu Pro. See Settings › Joshu Pro.')
      .replace('Add your Anthropic API key so ${name} can summarise your inbox.', 'With Joshu Pro, ${name} summarises your inbox.')
      .replace('Add your Anthropic API key in Settings › AI, or unlock the keys synced from your Mac, to chat about your day.', 'Chatting about your day is part of Joshu Pro (Settings › Joshu Pro).')
      .replace("Add your Anthropic API key in Settings and {assistant} will write your review and suggest next week's focus.", "With Joshu Pro, {assistant} writes your review and suggests next week's focus.")
      .replace('Add your Anthropic API key (or unlock your keys from the Mac) in Settings › AI to get savings advice.', 'Savings advice is part of Joshu Pro (Settings › Joshu Pro).')
      .replace('Add your Anthropic API key in Settings › AI first.', 'This is part of Joshu Pro (Settings › Joshu Pro).')
      .replace('Reading PDF statements needs your Anthropic API key (Settings › AI). A CSV export works without it.', 'Reading PDF statements is part of Joshu Pro. A CSV export works without it.')
      // The Mac and iPhone call the assistant "Joshu" until you rename it.
      .replace(/'assistantName', 'Ask'\)/g, "'assistantName', 'Joshu')").replace(/\|\| 'Ask'/g, "|| 'Joshu'")
  },
}

export default defineConfig({
  root: here('.'),
  base: './',
  resolve: {
    alias: [
      { find: '@', replacement: here('../windows/src/renderer/src') },
      { find: '~', replacement: here('src') },
      // Aliased package folders lose the "browser" export condition: point at the browser build directly.
      { find: /^react-dom\/server$/, replacement: here('node_modules/react-dom/server.browser.js') },
      ...shared.map((m) => ({ find: new RegExp(`^${m.replace('/', '\\/')}(?=/|$)`), replacement: here(`node_modules/${m}`) })),
    ],
    dedupe: ['react', 'react-dom'],
  },
  plugins: [joshu, react()],
  build: { outDir: 'dist', emptyOutDir: true, target: 'es2020', chunkSizeWarningLimit: 4000 },
  server: { port: 5199, fs: { allow: [here('..')] } },
})
