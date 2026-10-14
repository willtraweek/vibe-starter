import { type Page, type Route, expect, test } from '@playwright/test'

import packageJson from '../package.json' with { type: 'json' }

// Holds each GET /status.json until the test answers it, so the test can look
// at the page while a check is still running.
const holdStatusRequests = async (page: Page) => {
  const held: Array<Route> = []
  await page.route('**/status.json', route => {
    held.push(route)
  })
  return async (answer: Parameters<Route['fulfill']>[0]) => {
    await expect.poll(() => held.length).toBe(1)
    const route = held.shift()
    if (route === undefined) {
      throw new Error('no status request to answer')
    }
    await route.fulfill(answer)
  }
}

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

// Regression test: Retry's button left the page while the check reran, and
// keyboard focus fell to <body>, where a second failure left it. Focus must stay
// in the status panel through loading, another failure, and the success after.
test('retrying a failed status check keeps keyboard focus', async ({
  page,
}) => {
  const answer = await holdStatusRequests(page)
  const panel = page.getByRole('region', { name: 'Status' })
  const retry = panel.getByRole('button', { name: 'Retry' })
  await page.goto('/')
  await answer({ status: 503, body: 'down' })
  await expect(panel.getByRole('alert')).toHaveText(
    'Status check failed (http): HTTP 503',
  )
  await retry.focus()
  await page.keyboard.press('Enter')
  await expect(panel.getByRole('status')).toHaveText('Checking status...')
  await expect(panel).toBeFocused()
  await answer({ status: 503, body: 'down' })
  await expect(panel.getByRole('alert')).toBeVisible()
  await expect(panel).toBeFocused()
  await page.keyboard.press('Tab')
  await expect(retry).toBeFocused()
  await page.keyboard.press('Enter')
  await expect(panel).toBeFocused()
  await answer({ json: { status: 'ok', checkedAt: '2026-09-25T01:00:00Z' } })
  await expect(panel.getByRole('status')).toHaveText(
    'Status: ok (checked 2026-09-25T01:00:00Z)',
  )
  await expect(panel).toBeFocused()
})
