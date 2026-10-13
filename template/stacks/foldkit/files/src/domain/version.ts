import { Option } from 'effect'

const SEMVER = /^\d+\.\d+\.\d+$/

export const parseVersion = (raw: string): Option.Option<string> => {
  const trimmed = raw.trim()
  if (SEMVER.test(trimmed)) {
    return Option.some(trimmed)
  }
  return Option.none()
}

export const displayVersion = (raw: string): string =>
  Option.match(parseVersion(raw), {
    onNone: () => 'unknown',
    onSome: version => version,
  })
