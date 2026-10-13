import type { Html, HtmlBuilder } from 'foldkit/html'

import { STATUS_PANEL_ID } from '../command'
import { StatusState } from '../main'
import { Message } from '../message'

// VIEW

// NOTE: the panel itself is the same element in every state, so the patcher
// updates it in place and FocusStatusPanel's focus survives each change.
export const statusView = (
  status: StatusState,
  h: HtmlBuilder<Message>,
): Html =>
  h.section(
    [
      h.Id(STATUS_PANEL_ID),
      h.Class('status-panel'),
      h.Tabindex(-1),
      h.AriaLabel('Status'),
    ],
    StatusState.match(status, {
      Loading: () => [
        h.p([h.Role('status'), h.Class('status')], ['Checking status...']),
      ],
      Loaded: ({ payload }) => [
        h.p(
          [h.Role('status'), h.Class(`status status-${payload.status}`)],
          [`Status: ${payload.status} (checked ${payload.checkedAt})`],
        ),
      ],
      Failed: ({ reason, detail }) => [
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
    }),
  )
