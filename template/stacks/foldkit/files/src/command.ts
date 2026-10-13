import { Effect } from 'effect'
import { Command } from 'foldkit'

import { fetchStatus } from './api/status'
import { Message } from './message'

// COMMAND

export const FetchStatus = Command.define('FetchStatus', {
  messages: [Message.SucceededFetchStatus, Message.FailedFetchStatus],
  execute: fetchStatus.pipe(
    Effect.map(payload => Message.SucceededFetchStatus({ payload })),
    Effect.catchTags({
      StatusHttpError: error =>
        Effect.succeed(
          Message.FailedFetchStatus({
            reason: 'http',
            detail: `HTTP ${error.status}`,
          }),
        ),
      StatusMalformedError: error =>
        Effect.succeed(
          Message.FailedFetchStatus({
            reason: 'malformed',
            detail: error.detail,
          }),
        ),
      StatusUnreachableError: error =>
        Effect.succeed(
          Message.FailedFetchStatus({
            reason: 'unreachable',
            detail: error.detail,
          }),
        ),
    }),
  ),
})
