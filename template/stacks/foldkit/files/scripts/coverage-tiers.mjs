#!/usr/bin/env node
// Independent global and tier coverage gates; Node standard library only (TESTING.md).
//
// Config lives in coverage-tiers.json: tiers (explicit src/**/*.ts members) and the
// named E2E journeys. Empty tiers require allow_empty. A metric with nothing to
// measure (total 0) is n/a. --ratchet REF forbids lowering floors or targets and
// removing tiers or members; renaming, moving or deleting a member means listing
// its old path in the tier's `retired`.
//
//   node scripts/coverage-tiers.mjs --validate          # config only (before tests)
//   node scripts/coverage-tiers.mjs --check             # after vitest --coverage
//   node scripts/coverage-tiers.mjs --report            # markdown snapshot table
//   node scripts/coverage-tiers.mjs --ratchet origin/main
//   ... --input coverage/coverage-summary.json          # the default
import { execFileSync } from 'node:child_process'
import { existsSync, readFileSync, readdirSync, realpathSync, statSync } from 'node:fs'
import { dirname, join, relative, sep } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = dirname(dirname(fileURLToPath(import.meta.url)))
const CONFIG = 'coverage-tiers.json'
const GLOBAL_MINIMUM = 90
const METRICS = ['lines', 'branches', 'functions']
const GLOBAL_METRICS = ['lines', 'branches']
const TIER_KEYS = new Set(['title', 'minimum', 'target', 'include', 'allow_empty', 'retired'])
const TOP_KEYS = new Set(['tiers', 'journeys'])

const isObject = value => typeof value === 'object' && value !== null && !Array.isArray(value)
const isNumber = value => typeof value === 'number' && Number.isFinite(value)
const own = (object, key) => Object.prototype.hasOwnProperty.call(object, key)

export const validPath = path =>
  typeof path === 'string' &&
  path.startsWith('src/') &&
  path.endsWith('.ts') &&
  !path.endsWith('.d.ts') &&
  !path.endsWith('.test.ts') &&
  !path.includes('\\') &&
  path.split('/').every(part => part !== '' && part !== '.' && part !== '..')

const insideRoot = path => {
  try {
    const real = realpathSync(join(ROOT, path))
    const root = realpathSync(ROOT)
    return statSync(real).isFile() && real.startsWith(root + sep)
  } catch {
    return false
  }
}

const specFiles = dir => {
  if (!existsSync(dir)) {
    return []
  }
  return readdirSync(dir, { withFileTypes: true }).flatMap(entry => {
    const path = join(dir, entry.name)
    if (entry.isDirectory()) {
      return specFiles(path)
    }
    return entry.isFile() && entry.name.endsWith('.spec.ts') ? [path] : []
  })
}

// Titles of plain test('...') calls: test.skip/fixme/only do not count as journeys.
export const journeyTitles = () => {
  const titles = new Set()
  const call = /(?<![.\w])test\(\s*(['"])((?:\\.|(?!\1)[^\\\n])*)\1/g
  for (const file of specFiles(join(ROOT, 'e2e'))) {
    for (const match of readFileSync(file, 'utf8').matchAll(call)) {
      titles.add(match[2].replace(/\\(.)/g, '$1'))
    }
  }
  return titles
}

export const validate = (config, { checkFiles = true } = {}) => {
  if (!isObject(config)) {
    return ['coverage-tiers.json must be an object with tiers and journeys']
  }
  const errors = []
  const unknown = Object.keys(config).filter(key => !TOP_KEYS.has(key))
  if (unknown.length > 0) {
    errors.push(`unknown top-level keys: ${JSON.stringify(unknown.toSorted())}`)
  }
  const tiers = config.tiers
  if (!isObject(tiers) || Object.keys(tiers).length === 0) {
    errors.push('tiers must be a nonempty object')
  } else {
    const owner = new Map()
    for (const [key, tier] of Object.entries(tiers)) {
      if (key === 'global') {
        errors.push('global is reserved for the global floor, not a tier name')
      }
      if (!isObject(tier)) {
        errors.push(`${key}: tier must be an object`)
        continue
      }
      const extra = Object.keys(tier).filter(name => !TIER_KEYS.has(name))
      if (extra.length > 0) {
        errors.push(`${key}: unknown tier keys: ${JSON.stringify(extra.toSorted())}`)
      }
      if (!isNumber(tier.minimum) || !isNumber(tier.target)) {
        errors.push(`${key}: minimum and target must be finite numbers`)
      } else if (!(tier.minimum >= 0 && tier.minimum <= tier.target && tier.target <= 100)) {
        errors.push(`${key}: need 0 <= minimum <= target <= 100`)
      }
      if (typeof tier.title !== 'string' || tier.title.trim() === '') {
        errors.push(`${key}: title must be a nonempty string`)
      }
      if (own(tier, 'allow_empty') && typeof tier.allow_empty !== 'boolean') {
        errors.push(`${key}: allow_empty must be boolean`)
      }
      const members = tier.include
      let retired = own(tier, 'retired') ? tier.retired : []
      if (!Array.isArray(retired)) {
        errors.push(`${key}: retired must be an array`)
        retired = []
      }
      const seen = new Set()
      for (const path of retired) {
        if (!validPath(path)) {
          errors.push(`${key}: retired must name canonical src/**/*.ts files: ${JSON.stringify(path)}`)
        } else if (seen.has(path) || (Array.isArray(members) && members.includes(path))) {
          errors.push(`${key}: ${path} is listed twice across include and retired`)
        } else {
          seen.add(path)
        }
      }
      if (!Array.isArray(members)) {
        errors.push(`${key}: include must be an explicit array`)
        continue
      }
      if (members.length === 0 && tier.allow_empty !== true) {
        errors.push(`${key}: empty include requires allow_empty: true`)
      }
      for (const path of members) {
        if (!validPath(path)) {
          errors.push(`${key}: include must name canonical src/**/*.ts files (no tests or .d.ts): ${JSON.stringify(path)}`)
          continue
        }
        if (checkFiles && !insideRoot(path)) {
          errors.push(`${key}: include ${JSON.stringify(path)} is not a file within the project`)
        }
        if (owner.has(path)) {
          errors.push(`${path}: duplicate membership in ${JSON.stringify(owner.get(path))} and ${JSON.stringify(key)}`)
        }
        owner.set(path, key)
      }
    }
  }
  const journeys = config.journeys
  if (!Array.isArray(journeys) || journeys.length === 0) {
    errors.push('journeys must be a nonempty array of Playwright test titles')
  } else {
    const titles = checkFiles ? journeyTitles() : new Set()
    const seen = new Set()
    for (const journey of journeys) {
      if (typeof journey !== 'string' || journey.trim() === '') {
        errors.push(`journeys: each must be a nonempty string: ${JSON.stringify(journey)}`)
      } else if (seen.has(journey)) {
        errors.push(`journeys: ${JSON.stringify(journey)} is listed twice`)
      } else {
        seen.add(journey)
        if (checkFiles && !titles.has(journey)) {
          errors.push(`journeys: no test(${JSON.stringify(journey)}) in e2e/**/*.spec.ts`)
        }
      }
    }
  }
  return errors
}

const counters = (entry, label, errors) => {
  if (!isObject(entry)) {
    errors.push(`${label}: missing or invalid coverage counters`)
    return undefined
  }
  const value = {}
  for (const metric of METRICS) {
    const summary = entry[metric]
    if (
      !isObject(summary) ||
      !Number.isSafeInteger(summary.total) ||
      !Number.isSafeInteger(summary.covered) ||
      summary.total < 0 ||
      summary.covered < 0
    ) {
      errors.push(`${label}: missing or invalid coverage counters`)
      return undefined
    }
    if (summary.covered > summary.total) {
      errors.push(`${label}: covered counters exceed totals`)
      return undefined
    }
    value[metric] = { total: summary.total, covered: summary.covered }
  }
  return value
}

export const measure = (config, report) => {
  const errors = []
  const measured = new Map()
  if (!isObject(report)) {
    return { measured, errors: ['coverage summary must be an object'] }
  }
  const root = realpathSync(ROOT)
  const files = new Map()
  let entries = 0
  for (const [path, entry] of Object.entries(report)) {
    if (path === 'total') {
      continue
    }
    entries += 1
    const rel = relative(root, path).split(sep).join('/')
    if (!path.startsWith(root + sep) || rel.startsWith('..')) {
      errors.push(`coverage summary names a file outside the project: ${path}`)
      continue
    }
    const value = counters(entry, rel, errors)
    if (value !== undefined) {
      files.set(rel, value)
    }
  }
  if (entries === 0) {
    return { measured, errors: [...errors, 'coverage summary has no per-file entries'] }
  }
  const total = counters(report.total, 'global', errors)
  if (total !== undefined) {
    if (total.lines.total === 0) {
      errors.push('global: no measurable lines')
    }
    if (files.size === entries) {
      for (const metric of METRICS) {
        for (const field of ['total', 'covered']) {
          const sum = [...files.values()].reduce((acc, value) => acc + value[metric][field], 0)
          if (sum !== total[metric][field]) {
            errors.push('global: counters disagree with per-file sums')
          }
        }
      }
    }
    measured.set('global', total)
  }
  for (const [key, tier] of Object.entries(config.tiers)) {
    if (tier.include.length === 0) {
      measured.set(key, undefined)
      continue
    }
    const sum = Object.fromEntries(METRICS.map(metric => [metric, { total: 0, covered: 0 }]))
    for (const path of tier.include) {
      const value = files.get(path)
      if (value === undefined) {
        if (!own(report, join(root, path))) {
          errors.push(`${key}: ${path} is not in the coverage report (never imported, or excluded from coverage)`)
        }
        continue
      }
      if (value.lines.total === 0) {
        errors.push(`${key}: ${path} has no measurable lines (types only?)`)
      }
      for (const metric of METRICS) {
        sum[metric].total += value[metric].total
        sum[metric].covered += value[metric].covered
      }
    }
    measured.set(key, sum)
  }
  return { measured, errors: [...new Set(errors)], files }
}

const percent = (covered, total) => (100 * covered) / total

export const check = (config, measured, files = new Map()) => {
  const errors = []
  for (const [key, value] of measured) {
    if (value === undefined) {
      continue
    }
    const isGlobal = key === 'global'
    const floor = isGlobal ? GLOBAL_MINIMUM : config.tiers[key].minimum
    for (const metric of isGlobal ? GLOBAL_METRICS : METRICS) {
      const { covered, total } = value[metric]
      if (total > 0 && 100 * covered < floor * total) {
        let hint = ''
        if (isGlobal) {
          const low = [...files]
            .filter(([, file]) => file[metric].total > 0 && 100 * file[metric].covered < floor * file[metric].total)
            .map(([path, file]) => `${path} ${percent(file[metric].covered, file[metric].total).toFixed(2)}%`)
          hint = low.length > 0 ? ` (below the floor: ${low.join(', ')})` : ''
        }
        errors.push(`${key}: ${metric} ${percent(covered, total).toFixed(2)}% is below its minimum ${floor}%${hint}`)
      }
    }
  }
  return errors
}

const cell = (value, metric) => {
  if (value === undefined) {
    return 'n/a (explicitly empty)'
  }
  const { covered, total } = value[metric]
  return total > 0 ? `${percent(covered, total).toFixed(2)}%` : 'n/a (nothing to measure)'
}

export const reportMarkdown = (config, measured) => {
  const lines = [
    '| Tier | Lines | Branches | Functions | Minimum | Target |',
    '|---|---|---|---|---|---|',
  ]
  for (const [key, value] of measured) {
    const tier = key === 'global'
      ? { title: 'Global (lines and branches)', minimum: GLOBAL_MINIMUM, target: 100 }
      : config.tiers[key]
    lines.push(
      `| ${tier.title} | ${cell(value, 'lines')} | ${cell(value, 'branches')} | ${cell(value, 'functions')} | ${tier.minimum}% | ${tier.target}% |`,
    )
  }
  return `${lines.join('\n')}\n`
}

const git = (...args) => {
  try {
    return { status: 0, stdout: execFileSync('git', args, { cwd: ROOT, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }), stderr: '' }
  } catch (error) {
    return { status: error.status ?? 1, stdout: String(error.stdout ?? ''), stderr: String(error.stderr ?? error.message) }
  }
}

export const ratchet = (config, ref) => {
  // rev-parse first: it also refuses a ref that git would read as an option.
  if (git('rev-parse', '--verify', '--quiet', `${ref}^{commit}`).status !== 0) {
    return [`cannot read ${CONFIG} at ${ref}: unknown revision`]
  }
  // A base that predates the file (the project's first PR) has no floors to keep.
  // Only a confirmed absence counts: an unreadable tree still fails.
  const listed = git('ls-tree', '--name-only', ref, '--', CONFIG)
  if (listed.status !== 0) {
    return [`cannot read ${CONFIG} at ${ref}: ${listed.stderr.trim()}`]
  }
  if (listed.stdout.trim() === '') {
    console.log(`coverage-tiers: no ${CONFIG} at ${ref}; nothing to ratchet against`)
    return []
  }
  const shown = git('show', `${ref}:${CONFIG}`)
  if (shown.status !== 0) {
    return [`cannot read ${CONFIG} at ${ref}: ${shown.stderr.trim()}`]
  }
  let old
  try {
    old = JSON.parse(shown.stdout)
  } catch (error) {
    return [`base config: ${CONFIG} at ${ref} is not valid JSON: ${error.message}`]
  }
  const baseErrors = validate(old, { checkFiles: false })
  if (baseErrors.length > 0) {
    return baseErrors.map(error => `base config: ${error}`)
  }
  const errors = []
  for (const [key, before] of Object.entries(old.tiers)) {
    const now = config.tiers[key]
    if (now === undefined) {
      errors.push(`${key}: tier removed since ${ref}`)
      continue
    }
    for (const field of ['minimum', 'target']) {
      if (now[field] < before[field]) {
        errors.push(`${key}: ${field} lowered from ${before[field]} to ${now[field]}`)
      }
    }
    // A reviewed migration lists the old path in `retired`; any other removal fails.
    const kept = new Set([...now.include, ...(now.retired ?? [])])
    const removed = before.include.filter(path => !kept.has(path)).toSorted()
    if (removed.length > 0) {
      errors.push(
        `${key}: existing members removed since ${ref}: ${JSON.stringify(removed)} ` +
          "(to rename, move or delete one, list its old path in the tier's retired)",
      )
    }
  }
  return errors
}

const usage = message => {
  console.error(`coverage-tiers: ${message}`)
  console.error('usage: node scripts/coverage-tiers.mjs (--validate | --check | --report | --ratchet REF) [--input FILE]')
  process.exit(2)
}

const parseArgs = argv => {
  let mode
  let ref
  let input = 'coverage/coverage-summary.json'
  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index]
    const [flag, inline] = arg.startsWith('--') && arg.includes('=') ? [arg.slice(0, arg.indexOf('=')), arg.slice(arg.indexOf('=') + 1)] : [arg, undefined]
    const value = () => {
      if (inline !== undefined) {
        return inline
      }
      index += 1
      if (index >= argv.length) {
        usage(`${flag} needs a value`)
      }
      return argv[index]
    }
    if (['--validate', '--check', '--report', '--ratchet'].includes(flag)) {
      if (mode !== undefined) {
        usage('choose exactly one of --validate, --check, --report, --ratchet')
      }
      mode = flag
      if (flag === '--ratchet') {
        ref = value()
        if (ref.trim() === '') {
          usage('--ratchet needs a git ref')
        }
      } else if (inline !== undefined) {
        usage(`${flag} takes no value`)
      }
    } else if (flag === '--input') {
      input = value()
    } else {
      usage(`unknown argument: ${arg}`)
    }
  }
  if (mode === undefined) {
    usage('choose one of --validate, --check, --report, --ratchet')
  }
  return { mode, ref, input }
}

const main = argv => {
  const { mode, ref, input } = parseArgs(argv)
  let errors
  try {
    const config = JSON.parse(readFileSync(join(ROOT, CONFIG), 'utf8'))
    errors = validate(config)
    if (errors.length === 0 && mode === '--ratchet') {
      errors = ratchet(config, ref)
    } else if (errors.length === 0 && (mode === '--check' || mode === '--report')) {
      const report = JSON.parse(readFileSync(join(ROOT, input), 'utf8'))
      const measured = measure(config, report)
      errors = measured.errors
      if (errors.length === 0 && mode === '--report') {
        process.stdout.write(reportMarkdown(config, measured.measured))
        return 0
      }
      if (errors.length === 0) {
        errors = check(config, measured.measured, measured.files)
      }
    }
  } catch (error) {
    errors = [`cannot load valid configuration/report: ${error instanceof Error ? error.message : String(error)}`]
  }
  for (const error of errors) {
    console.error(`coverage-tiers: FAIL ${error}`)
  }
  console.log(`coverage-tiers: ${errors.length > 0 ? 'FAILED' : 'ok'}`)
  return errors.length > 0 ? 1 : 0
}

if (process.argv[1] !== undefined && realpathSync(process.argv[1]) === fileURLToPath(import.meta.url)) {
  process.exitCode = main(process.argv.slice(2))
}
