import { expect, test } from '@playwright/test'

import packageJson from '../package.json' with { type: 'json' }

test('home renders the project name, version and status', async ({ page }) => {
  await page.goto('/')
  await expect(page).toHaveTitle(packageJson.description)
  await expect(page.getByRole('heading', { level: 1 })).toHaveText(
    packageJson.description,
  )
  await expect(page.getByText(`Version ${packageJson.version}`)).toBeVisible()
  await expect(page.getByRole('status')).toHaveText(
    'Status: ok (checked 2026-09-25T00:00:00Z)',
  )
})
