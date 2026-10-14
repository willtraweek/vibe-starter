import rawVersion from '../VERSION?raw'
import { displayVersion } from './domain/version'

export const PROJECT_NAME = '{{PROJECT_NAME}}'

export const VERSION = displayVersion(rawVersion)
