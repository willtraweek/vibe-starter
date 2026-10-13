import { defineConfig } from 'vite'

import { foldkit } from '@foldkit/vite-plugin'

// The DevTools MCP relay stays off (docs/guides/foldkit.md). A numeric
// devToolsMcpPort opens an unauthenticated relay on every network interface,
// so check.sh refuses one.
export default defineConfig({
  plugins: [foldkit({ devToolsMcpPort: false })],
  optimizeDeps: {
    entries: ['src/entry.ts'],
  },
  server: {
    port: 3000,
    strictPort: true,
    watch: { ignored: ['**/repos/**'] },
  },
  preview: { port: 4000, strictPort: true },
})
