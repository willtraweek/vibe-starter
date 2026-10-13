import { Effect, Layer } from 'effect'
import { HttpClient, HttpClientError, HttpClientResponse } from 'effect/http'

import { assert, describe, it } from '@effect/vitest'

import { FetchStatus } from './command'
import { Message } from './message'

// Tier 2: FetchStatus maps every outcome of the status request to a Message.
// Only the HttpClient Layer (the network edge) is swapped.

const answering = (response: Response) =>
  Layer.succeed(
    HttpClient.HttpClient,
    HttpClient.make(request =>
      Effect.succeed(HttpClientResponse.fromWeb(request, response)),
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

const run = (layer: Layer.Layer<HttpClient.HttpClient>) =>
  FetchStatus().effect.pipe(Effect.provide(layer))

describe('FetchStatus', () => {
  it.effect('reports a well-formed status', () =>
    Effect.gen(function* () {
      const checkedAt = '2026-09-25T00:00:00Z'
      assert.deepStrictEqual(
        yield* run(answering(Response.json({ status: 'ok', checkedAt }))),
        Message.SucceededFetchStatus({ payload: { status: 'ok', checkedAt } }),
      )
    }),
  )

  it.effect('reports a non-2xx response as an http failure', () =>
    Effect.gen(function* () {
      assert.deepStrictEqual(
        yield* run(answering(new Response(null, { status: 404 }))),
        Message.FailedFetchStatus({ reason: 'http', detail: 'HTTP 404' }),
      )
    }),
  )

  it.effect('reports a malformed payload', () =>
    Effect.gen(function* () {
      const result = yield* run(answering(new Response('nope')))
      assert.deepStrictEqual(
        result._tag === 'FailedFetchStatus' ? result.reason : result._tag,
        'malformed',
      )
    }),
  )

  it.effect('reports a transport failure as unreachable', () =>
    Effect.gen(function* () {
      const result = yield* run(offline)
      assert.deepStrictEqual(
        result._tag === 'FailedFetchStatus' ? result.reason : result._tag,
        'unreachable',
      )
    }),
  )
})
