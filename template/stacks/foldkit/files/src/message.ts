import { Schema } from 'effect'
import { defineMessageUnion } from 'foldkit/message'

import { StatusPayload } from './api/status'

// MESSAGE

export const FailureReason = Schema.Literals([
  'http',
  'malformed',
  'unreachable',
])
export type FailureReason = typeof FailureReason.Type

export const Message = defineMessageUnion({
  ClickedRetryStatus: {},
  SucceededFetchStatus: { payload: StatusPayload },
  FailedFetchStatus: { reason: FailureReason, detail: Schema.String },
})
export type Message = typeof Message.Type
