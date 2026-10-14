import {
  Command,
  click,
  expect,
  given,
  role,
  scene,
  text,
  within,
} from 'foldkit/scene'
import { describe, test } from 'vitest'

import { PROJECT_NAME, VERSION } from './build-info'
import { FetchStatus, FocusStatusPanel, STATUS_PANEL_ID } from './command'
import { Model, StatusState, update } from './main'
import { Message } from './message'
import { view } from './view'

const withStatus = (status: StatusState) => Model.make({ status })

describe('view', () => {
  test('shows the project name, the version and a loading status', () => {
    scene(
      { update, view },
      given(withStatus(StatusState.Loading())),
      expect(role('heading', { name: PROJECT_NAME })).toExist(),
      expect(text(`Version ${VERSION}`)).toExist(),
      expect(role('status')).toHaveText('Checking status...'),
    )
  })

  test('shows the loaded status', () => {
    scene(
      { update, view },
      given(
        withStatus(
          StatusState.Loaded({
            payload: { status: 'ok', checkedAt: '2026-09-25T00:00:00Z' },
          }),
        ),
      ),
      expect(role('status')).toHaveText(
        'Status: ok (checked 2026-09-25T00:00:00Z)',
      ),
      expect(role('alert')).toBeAbsent(),
    )
  })

  test('each loaded status gets its own style', () => {
    scene(
      { update, view },
      given(
        withStatus(
          StatusState.Loaded({
            payload: { status: 'down', checkedAt: '2026-09-25T00:00:00Z' },
          }),
        ),
      ),
      expect(role('status')).toHaveAttr('class', 'status status-down'),
    )
  })

  test('a failed check shows an alert, and Retry recovers', () => {
    scene(
      { update, view },
      given(
        withStatus(StatusState.Failed({ reason: 'http', detail: 'HTTP 503' })),
      ),
      expect(role('alert')).toHaveText('Status check failed (http): HTTP 503'),
      click(role('button', { name: 'Retry' })),
      expect(role('status')).toHaveText('Checking status...'),
      Command.expectExact(FetchStatus(), FocusStatusPanel()),
      Command.resolve(FocusStatusPanel, Message.CompletedFocusStatusPanel()),
      Command.resolve(
        FetchStatus,
        Message.SucceededFetchStatus({
          payload: { status: 'degraded', checkedAt: '2026-09-25T01:00:00Z' },
        }),
      ),
      expect(role('status')).toHaveText(
        'Status: degraded (checked 2026-09-25T01:00:00Z)',
      ),
      expect(role('alert')).toBeAbsent(),
    )
  })

  // Regression test: Retry swapped the failure's <div> (holding the button) for
  // the loading <p>, so the patcher replaced the node and keyboard focus fell to
  // <body>, where a second failure left it. One status panel now holds every
  // state, and Retry focuses it (the E2E journey checks focus in a browser).
  test('Retry keeps the status panel and focuses it, through failure and success', () => {
    const panel = role('region', { name: 'Status' })
    scene(
      { update, view },
      given(
        withStatus(StatusState.Failed({ reason: 'http', detail: 'HTTP 503' })),
      ),
      expect(panel).toHaveId(STATUS_PANEL_ID),
      expect(panel).toHaveAttr('tabIndex', '-1'),
      click(within(panel, role('button', { name: 'Retry' }))),
      Command.expectExact(FetchStatus(), FocusStatusPanel()),
      expect(within(panel, role('status'))).toHaveText('Checking status...'),
      Command.resolve(FocusStatusPanel, Message.CompletedFocusStatusPanel()),
      Command.resolve(
        FetchStatus,
        Message.FailedFetchStatus({
          reason: 'unreachable',
          detail: 'timed out after 10 seconds',
        }),
      ),
      expect(within(panel, role('alert'))).toHaveText(
        'Status check failed (unreachable): timed out after 10 seconds',
      ),
      click(within(panel, role('button', { name: 'Retry' }))),
      Command.expectExact(FetchStatus(), FocusStatusPanel()),
      Command.resolve(FocusStatusPanel, Message.CompletedFocusStatusPanel()),
      Command.resolve(
        FetchStatus,
        Message.SucceededFetchStatus({
          payload: { status: 'ok', checkedAt: '2026-09-25T01:00:00Z' },
        }),
      ),
      expect(within(panel, role('status'))).toHaveText(
        'Status: ok (checked 2026-09-25T01:00:00Z)',
      ),
      expect(panel).toHaveAttr('tabIndex', '-1'),
    )
  })
})
