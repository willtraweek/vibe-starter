import { Schema } from 'effect'
import type { HttpClient } from 'effect/http'
import type { Runtime, Update } from 'foldkit'
import { defineTaggedUnion } from 'foldkit/schema'
import { modifyFields } from 'foldkit/struct'

import { StatusPayload } from './api/status'
import { FetchStatus } from './command'
import { FailureReason, Message } from './message'

// MODEL

export const StatusState = defineTaggedUnion({
  Loading: {},
  Loaded: { payload: StatusPayload },
  Failed: { reason: FailureReason, detail: Schema.String },
})
export type StatusState = typeof StatusState.Type

export const Model = Schema.Struct({
  status: StatusState,
})
export type Model = typeof Model.Type

// INIT

export const init: Runtime.ApplicationInit<
  Model,
  Message,
  void,
  HttpClient.HttpClient
> = () => ({
  model: { status: StatusState.Loading() },
  commands: [FetchStatus()],
})

// UPDATE

type UpdateReturn = Update.Return<Model, Message, HttpClient.HttpClient>

export const update = (model: Model, message: Message) =>
  Message.match<UpdateReturn>(message, {
    ClickedRetryStatus: () => ({
      model: modifyFields(model, { status: () => StatusState.Loading() }),
      commands: [FetchStatus()],
    }),
    SucceededFetchStatus: ({ payload }) => ({
      model: modifyFields(model, {
        status: () => StatusState.Loaded({ payload }),
      }),
    }),
    FailedFetchStatus: ({ reason, detail }) => ({
      model: modifyFields(model, {
        status: () => StatusState.Failed({ reason, detail }),
      }),
    }),
  })
