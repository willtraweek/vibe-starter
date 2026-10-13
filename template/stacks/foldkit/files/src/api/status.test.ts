import { Effect, Layer } from 'effect'
import { HttpClient, HttpClientError, HttpClientResponse } from 'effect/http'

import { assert, describe, it } from '@effect/vitest'

import { STATUS_PATH, fetchStatus } from './status'

// Tier 2: the network edge is the only thing swapped. Each test provides an
// HttpClient Layer that answers with a canned Response or a transport error.

const answering = (respond: () => Response) =>
  Layer.succeed(
    HttpClient.HttpClient,
    HttpClient.make((request, url) =>
      Effect.sync(() => {
        assert.strictEqual(url.pathname, STATUS_PATH)
        return HttpClientResponse.fromWeb(request, respond())
      }),
    ),
  )

const offline = Layer.succeed(
  HttpClient.HttpClient,
  HttpClient.make(request =>
    Effect.fail(
      new HttpClientError.HttpClientError({
        reason: new HttpClientError.TransportError({
          request,
          description: 'offline',
        }),
      }),
    ),
  ),
)

const okBody = { status: 'ok', checkedAt: '2026-09-25T00:00:00Z' }

describe('fetchStatus', () => {
  it.effect('decodes a well-formed payload', () =>
    Effect.gen(function* () {
      const payload = yield* fetchStatus.pipe(
        Effect.provide(answering(() => Response.json(okBody))),
      )
      assert.deepStrictEqual(payload, okBody)
    }),
  )

  it.effect('fails with StatusHttpError on a non-2xx response', () =>
    Effect.gen(function* () {
      const error = yield* fetchStatus.pipe(
        Effect.provide(answering(() => new Response('down', { status: 503 }))),
        Effect.flip,
      )
      assert.deepStrictEqual(
        error._tag === 'StatusHttpError' ? error.status : error._tag,
        503,
      )
    }),
  )

  it.effect('fails with StatusMalformedError when the body is not JSON', () =>
    Effect.gen(function* () {
      const error = yield* fetchStatus.pipe(
        Effect.provide(answering(() => new Response('<html>'))),
        Effect.flip,
      )
      assert.strictEqual(error._tag, 'StatusMalformedError')
    }),
  )

  it.effect('fails with StatusMalformedError on the wrong shape', () =>
    Effect.gen(function* () {
      const error = yield* fetchStatus.pipe(
        Effect.provide(
          answering(() => Response.json({ status: 'maybe', checkedAt: 1 })),
        ),
        Effect.flip,
      )
      assert.strictEqual(error._tag, 'StatusMalformedError')
    }),
  )

  it.effect('fails with StatusUnreachableError on a transport error', () =>
    Effect.gen(function* () {
      const error = yield* fetchStatus.pipe(
        Effect.provide(offline),
        Effect.flip,
      )
      assert.strictEqual(error._tag, 'StatusUnreachableError')
    }),
  )
})
