import { defineConfig, devices } from '@playwright/test'

// The named journeys (TESTING.md tier 4) run against the production build,
// served by `vite preview` on 4000 (strictPort: a busy port fails the run).
// Not `pnpm build && pnpm preview`: under pnpm 12.6 that server outlived
// Playwright's shutdown and the run hung after the tests passed.
export default defineConfig({
  testDir: 'e2e',
  forbidOnly: true,
  retries: 0,
  use: { baseURL: 'http://localhost:4000' },
  projects: [{ name: 'chromium', use: { ...devices['Desktop Chrome'] } }],
  webServer: {
    command: 'vite build && vite preview',
    url: 'http://localhost:4000',
    reuseExistingServer: false,
  },
})
