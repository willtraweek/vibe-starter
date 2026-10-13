import { Command, click, expect, given, role, scene, text } from 'foldkit/scene'
import { describe, test } from 'vitest'

import { PROJECT_NAME, VERSION } from './build-info'
import { FetchStatus } from './command'
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
      Command.expectExact(FetchStatus()),
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
})
