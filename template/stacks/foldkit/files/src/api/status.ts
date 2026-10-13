import { Data, Effect, Schema } from 'effect'
import { HttpClient, type HttpClientError } from 'effect/http'

// The one network boundary: GET /status.json, decoded through a Schema.

export const STATUS_PATH = '/status.json'

export const StatusPayload = Schema.Struct({
  status: Schema.Literals(['ok', 'degraded', 'down']),
  checkedAt: Schema.String,
})
export type StatusPayload = typeof StatusPayload.Type

export class StatusHttpError extends Data.TaggedError('StatusHttpError')<{
  readonly status: number
}> {}

export class StatusMalformedError extends Data.TaggedError(
  'StatusMalformedError',
)<{
  readonly detail: string
}> {}

export class StatusUnreachableError extends Data.TaggedError(
  'StatusUnreachableError',
)<{
  readonly detail: string
}> {}

export type StatusError =
  | StatusHttpError
  | StatusMalformedError
  | StatusUnreachableError

const toRequestFailure = (
  error: HttpClientError.HttpClientError,
): StatusHttpError | StatusUnreachableError => {
  if (error.reason._tag === 'StatusCodeError') {
    return new StatusHttpError({ status: error.reason.response.status })
  }
  return new StatusUnreachableError({ detail: error.message })
}

const toMalformed = (error: { readonly message: string }) =>
  new StatusMalformedError({ detail: error.message })

export const fetchStatus: Effect.Effect<
  StatusPayload,
  StatusError,
  HttpClient.HttpClient
> = Effect.gen(function* () {
  const client = HttpClient.filterStatusOk(yield* HttpClient.HttpClient)
  const response = yield* client
    .get(STATUS_PATH)
    .pipe(Effect.mapError(toRequestFailure))
  const body = yield* response.json.pipe(Effect.mapError(toMalformed))
  return yield* Schema.decodeUnknownEffect(StatusPayload)(body).pipe(
    Effect.mapError(toMalformed),
  )
})
