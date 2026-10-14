import { defineConfig } from 'vitest/config'

// Coverage has no thresholds here on purpose: scripts/coverage-tiers.mjs
// enforces the floors, because Vitest passes a tier glob that matches nothing.
export default defineConfig({
  test: {
    include: ['src/**/*.test.ts'],
    environment: 'happy-dom',
    setupFiles: ['./src/vitest-setup.ts'],
    server: {
      deps: {
        inline: ['foldkit', '@foldkit/devtools'],
      },
    },
    coverage: {
      provider: 'v8',
      include: ['src/**/*.ts'],
      exclude: [
        'src/entry.ts',
        'src/vitest-setup.ts',
        'src/**/*.test.ts',
        'src/**/*.d.ts',
      ],
      reporter: ['text', 'json-summary'],
    },
  },
})
