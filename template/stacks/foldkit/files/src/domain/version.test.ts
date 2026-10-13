import { Option, Schema } from 'effect'

import { describe, expect, it } from '@effect/vitest'

import { displayVersion, parseVersion } from './version'

const Part = Schema.Int.pipe(Schema.check(Schema.isGreaterThanOrEqualTo(0)))

describe('parseVersion', () => {
  it.each([
    ['0.0.0\n', Option.some('0.0.0')],
    ['  1.2.3  ', Option.some('1.2.3')],
    ['10.20.30', Option.some('10.20.30')],
    ['0.1.0.1\n', Option.some('0.1.0')],
    ['1.2.3.4', Option.some('1.2.3')],
    ['v1.2.3', Option.none()],
    ['1.2', Option.none()],
    ['1.2.3.', Option.none()],
    ['1.2.3.4.5', Option.none()],
    ['1.2.3-rc.1', Option.none()],
    ['', Option.none()],
  ])('parseVersion(%j)', (raw, expected) => {
    expect(parseVersion(raw)).toEqual(expected)
  })
})

describe('displayVersion', () => {
  it('shows the parsed version', () => {
    expect(displayVersion('1.2.3\n')).toBe('1.2.3')
  })

  it('falls back to unknown', () => {
    expect(displayVersion('not a version')).toBe('unknown')
  })

  it.prop(
    'shows any MAJOR.MINOR.PATCH read from the VERSION file',
    [Part, Part, Part],
    ([major, minor, patch]) => {
      const version = `${major}.${minor}.${patch}`
      expect(displayVersion(`${version}\n`)).toBe(version)
    },
  )

  // Regression test: after a gstack /ship that writes a MICRO release
  // (VERSION 0.1.0.1, package.json 0.1.0), the page said "Version unknown".
  it.prop(
    'shows a MAJOR.MINOR.PATCH.MICRO as its npm form, as in package.json',
    [Part, Part, Part, Part],
    ([major, minor, patch, micro]) => {
      expect(displayVersion(`${major}.${minor}.${patch}.${micro}\n`)).toBe(
        `${major}.${minor}.${patch}`,
      )
    },
  )
})
