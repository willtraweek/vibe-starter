import type { Html, HtmlBuilder } from 'foldkit/html'

import { StatusState } from '../main'
import { Message } from '../message'

// VIEW

export const statusView = (
  status: StatusState,
  h: HtmlBuilder<Message>,
): Html =>
  StatusState.match(status, {
    Loading: () =>
      h.p([h.Role('status'), h.Class('status')], ['Checking status...']),
    Loaded: ({ payload }) =>
      h.p(
        [h.Role('status'), h.Class(`status status-${payload.status}`)],
        [`Status: ${payload.status} (checked ${payload.checkedAt})`],
      ),
    Failed: ({ reason, detail }) =>
      h.div(
        [h.Class('status-failed')],
        [
          h.p(
            [h.Role('alert'), h.Class('status status-error')],
            [`Status check failed (${reason}): ${detail}`],
          ),
          h.button(
            [
              h.Type('button'),
              h.Class('button'),
              h.OnClick(Message.ClickedRetryStatus()),
            ],
            ['Retry'],
          ),
        ],
      ),
  })
