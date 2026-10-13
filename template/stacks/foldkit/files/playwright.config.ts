import { defineConfig, devices } from '@playwright/test'

// The named journeys (TESTING.md tier 4) run against the production build,
// served by `vite preview` on 4000 (strictPort: a busy port fails the run).
// Not `pnpm build && pnpm preview`: under pnpm 12.6 that server outlived
// Playwright's shutdown and the run hung after the tests passed.
// The JSON report is what `node scripts/coverage-tiers.mjs --journeys` reads to
// prove every named journey ran and passed. It lives in outputDir, which
// Playwright empties when a run starts, so a report left by an earlier run
// never stands in for this one.
export default defineConfig({
  testDir: 'e2e',
  outputDir: 'test-results',
  forbidOnly: true,
  retries: 0,
  reporter: [['list'], ['json', { outputFile: 'test-results/journeys.json' }]],
  use: { baseURL: 'http://localhost:4000' },
  projects: [{ name: 'chromium', use: { ...devices['Desktop Chrome'] } }],
  webServer: {
    command: 'vite build && vite preview',
    url: 'http://localhost:4000',
    reuseExistingServer: false,
  },
})
