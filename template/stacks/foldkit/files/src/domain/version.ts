import { Option } from 'effect'

// NOTE: gstack's VERSION is MAJOR.MINOR.PATCH or MAJOR.MINOR.PATCH.MICRO, and
// package.json holds its npm form, the first three parts (npm refuses a
// fourth). The page shows that npm form for both.
const RELEASE = /^(\d+\.\d+\.\d+)(?:\.\d+)?$/

export const parseVersion = (raw: string): Option.Option<string> =>
  Option.fromNullishOr(RELEASE.exec(raw.trim())?.[1])

export const displayVersion = (raw: string): string =>
  Option.match(parseVersion(raw), {
    onNone: () => 'unknown',
    onSome: version => version,
  })
