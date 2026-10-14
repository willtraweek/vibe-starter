import type { Document, HtmlBuilder } from 'foldkit/html'

import { PROJECT_NAME, VERSION } from './build-info'
import { statusView } from './components/status'
import type { Model } from './main'
import type { Message } from './message'

// VIEW

export const view = (model: Model, h: HtmlBuilder<Message>): Document => ({
  title: PROJECT_NAME,
  body: h.main(
    [h.Class('page')],
    [
      h.h1([h.Class('title')], [PROJECT_NAME]),
      h.p([h.Class('version')], [`Version ${VERSION}`]),
      statusView(model.status, h),
    ],
  ),
})
