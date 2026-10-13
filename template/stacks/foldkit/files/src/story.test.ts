import { Command, given, message, model, story } from 'foldkit/story'
import { describe, expect, test } from 'vitest'

import type { StatusPayload } from './api/status'
import { FetchStatus } from './command'
import { Model, StatusState, init, update } from './main'
import { Message } from './message'

const payload: StatusPayload = {
  status: 'ok',
  checkedAt: '2026-09-25T00:00:00Z',
}

const loading = Model.make({ status: StatusState.Loading() })

const failed = Model.make({
  status: StatusState.Failed({ reason: 'http', detail: 'HTTP 503' }),
})

describe('init', () => {
  test('starts loading and fetches the status', () => {
    const init_ = init()
    expect(init_.model).toEqual(loading)
    expect(init_.commands).toEqual([FetchStatus()])
  })
})

describe('update', () => {
  test('a successful status fetch stores the payload', () => {
    story(
      update,
      given(loading),
      message(Message.SucceededFetchStatus({ payload })),
      model(model => {
        expect(model.status).toEqual(StatusState.Loaded({ payload }))
      }),
      Command.expectNone(),
    )
  })

  test('a failed status fetch stores the reason', () => {
    story(
      update,
      given(loading),
      message(
        Message.FailedFetchStatus({ reason: 'malformed', detail: 'bad json' }),
      ),
      model(model => {
        expect(model.status).toEqual(
          StatusState.Failed({ reason: 'malformed', detail: 'bad json' }),
        )
      }),
      Command.expectNone(),
    )
  })

  test('retrying re-fetches and a success resolves inline', () => {
    story(
      update,
      given(failed),
      message(Message.ClickedRetryStatus()),
      model(model => {
        expect(model.status).toEqual(StatusState.Loading())
      }),
      Command.expectExact(FetchStatus()),
      Command.resolve(FetchStatus, Message.SucceededFetchStatus({ payload })),
      model(model => {
        expect(model.status).toEqual(StatusState.Loaded({ payload }))
      }),
    )
  })

  test('retrying re-fetches and a failure resolves inline', () => {
    story(
      update,
      given(failed),
      message(Message.ClickedRetryStatus()),
      Command.resolve(
        FetchStatus,
        Message.FailedFetchStatus({ reason: 'unreachable', detail: 'offline' }),
      ),
      model(model => {
        expect(model.status).toEqual(
          StatusState.Failed({ reason: 'unreachable', detail: 'offline' }),
        )
      }),
    )
  })
})
