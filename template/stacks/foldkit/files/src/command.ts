import { Effect } from 'effect'
import { Command, Dom } from 'foldkit'

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

export const STATUS_PANEL_ID = 'status-panel'

// NOTE: Retry's button leaves the page while the check reruns, which would drop
// keyboard focus on <body>; the status panel stays in place in every state.
export const FocusStatusPanel = Command.define('FocusStatusPanel', {
  messages: [Message.CompletedFocusStatusPanel],
  execute: Dom.focus(`#${STATUS_PANEL_ID}`).pipe(
    Effect.ignore,
    Effect.as(Message.CompletedFocusStatusPanel()),
  ),
})
