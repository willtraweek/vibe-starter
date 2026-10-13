import { Http, Runtime } from 'foldkit'

import { Model, init, update } from './main'
import './styles.css'
import { view } from './view'

const application = Runtime.makeApplication({
  Model,
  init,
  update,
  view,
  container: document.getElementById('root'),
  resources: Http.layer,
})

Runtime.run(application)
