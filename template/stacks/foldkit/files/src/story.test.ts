import { Effect, Fiber, Layer } from 'effect'
import { HttpClient } from 'effect/http'
import { TestClock } from 'effect/testing'
import { Command, given, message, model, story } from 'foldkit/story'

import { describe, expect, it, test } from '@effect/vitest'

import type { StatusPayload } from './api/status'
import { FetchStatus, FocusStatusPanel } from './command'
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

const silent = Layer.succeed(
  HttpClient.HttpClient,
  HttpClient.make(() => Effect.never),
)

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
      Command.expectExact(FetchStatus(), FocusStatusPanel()),
      Command.resolve(FocusStatusPanel, Message.CompletedFocusStatusPanel()),
      model(model => {
        expect(model.status).toEqual(StatusState.Loading())
      }),
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
      Command.resolve(FocusStatusPanel, Message.CompletedFocusStatusPanel()),
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

  // Regression test: a status server that never answered left the page on
  // "Checking status..." forever. The real FetchStatus, run on the TestClock,
  // now fails after 10 seconds, and Retry recovers from that failure.
  it.effect('a status check that times out fails, and Retry recovers', () =>
    Effect.gen(function* () {
      const fiber = yield* FetchStatus().effect.pipe(
        Effect.provide(silent),
        Effect.forkChild,
      )
      yield* TestClock.adjust('10 seconds')
      const timedOut = yield* Fiber.join(fiber)
      story(
        update,
        given(loading),
        message(timedOut),
        model(model => {
          expect(model.status).toEqual(
            StatusState.Failed({
              reason: 'unreachable',
              detail: 'timed out after 10 seconds',
            }),
          )
        }),
        message(Message.ClickedRetryStatus()),
        Command.expectExact(FetchStatus(), FocusStatusPanel()),
        Command.resolve(FocusStatusPanel, Message.CompletedFocusStatusPanel()),
        Command.resolve(FetchStatus, Message.SucceededFetchStatus({ payload })),
        model(model => {
          expect(model.status).toEqual(StatusState.Loaded({ payload }))
        }),
      )
    }),
  )
})
