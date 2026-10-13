#!/usr/bin/env node
// Pin guard (Node standard library only), run by scripts/check.d/foldkit.sh:
// package.json stays in the byte form gstack /ship writes, its version is VERSION,
// every dependency is exact, the runtime and package manager are pinned once,
// node_modules holds each dependency at its pin, the Foldkit + Effect train
// moves together, and pnpm-workspace.yaml keeps the supply-chain policy (age
// exemptions only for the train releases package.json pins).
import { existsSync, readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = dirname(dirname(fileURLToPath(import.meta.url)))
const EXACT = /^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$/
const SEMVER3 = /^\d+\.\d+\.\d+$/
// gstack's VERSION is MAJOR.MINOR.PATCH or MAJOR.MINOR.PATCH.MICRO; package.json
// carries its npm form, the first three parts (npm refuses a fourth).
const RELEASE = /^\d+\.\d+\.\d+(?:\.\d+)?$/
const errors = []

const read = path => readFileSync(join(ROOT, path), 'utf8')
const installed = name => {
  const path = join(ROOT, 'node_modules', name, 'package.json')
  return existsSync(path) ? JSON.parse(readFileSync(path, 'utf8')) : undefined
}

// Numeric semver compare for exact versions (prerelease sorts before release).
const compare = (a, b) => {
  const [coreA, preA = ''] = a.split('-', 2)
  const [coreB, preB = ''] = b.split('-', 2)
  const partsA = coreA.split('.').map(Number)
  const partsB = coreB.split('.').map(Number)
  for (let index = 0; index < 3; index += 1) {
    if (partsA[index] !== partsB[index]) {
      return partsA[index] - partsB[index]
    }
  }
  if (preA === preB) {
    return 0
  }
  if (preA === '' || preB === '') {
    return preA === '' ? 1 : -1
  }
  return preA < preB ? -1 : 1
}

// The peer range forms the @foldkit packages publish: exact, >=X.Y.Z, ^X[.Y[.Z]].
// Anything else is reported, not guessed.
const satisfies = (version, range) => {
  if (EXACT.test(range)) {
    return version === range
  }
  const atLeast = /^>=(\d+\.\d+\.\d+)$/.exec(range)
  if (atLeast) {
    return compare(version, atLeast[1]) >= 0
  }
  const caret = /^\^(\d+)(?:\.(\d+))?(?:\.(\d+))?$/.exec(range)
  if (caret) {
    const [major, minor, patch] = caret.slice(1)
    const core = version.split('-')[0]
    const [vMajor, vMinor] = core.split('.')
    const sameLine = major === '0' && minor !== undefined ? vMajor === '0' && vMinor === minor : vMajor === major
    return sameLine && compare(core, `${major}.${minor ?? 0}.${patch ?? 0}`) >= 0
  }
  return undefined
}

const parse = text => {
  try {
    return JSON.parse(text)
  } catch (error) {
    console.error(`check-pins: FAIL package.json is not valid JSON: ${error.message}`)
    console.log('check-pins: FAILED')
    return process.exit(1)
  }
}
const raw = read('package.json')
const pkg = parse(raw)
if (raw !== `${JSON.stringify(pkg, null, 2)}\n`) {
  errors.push('package.json is not in JSON.stringify(pkg, null, 2) + "\\n" form (gstack /ship rewrites it that way): reformat it')
}
const version = existsSync(join(ROOT, 'VERSION')) ? read('VERSION').trim() : ''
const npmVersion = version.split('.').slice(0, 3).join('.')
if (!RELEASE.test(version)) {
  errors.push(`VERSION must hold MAJOR.MINOR.PATCH or MAJOR.MINOR.PATCH.MICRO, got ${JSON.stringify(version)}`)
} else if (pkg.version !== npmVersion) {
  const form = npmVersion === version ? '' : ` (npm form ${npmVersion})`
  errors.push(`package.json version ${JSON.stringify(pkg.version)} differs from VERSION ${version}${form}: set it to ${npmVersion}`)
}

// Optional and peer dependencies are pinned like the rest; pnpm may skip an
// optional one on a platform it doesn't support, and installs no root peer, so
// only those may be missing from node_modules. Each section is checked on its
// own: merged, one section's entry would hide another's.
const SECTIONS = ['dependencies', 'devDependencies', 'optionalDependencies', 'peerDependencies']
const optional = { ...pkg.optionalDependencies, ...pkg.peerDependencies }
const section = new Map()
for (const key of SECTIONS) {
  for (const [name, spec] of Object.entries(pkg[key] ?? {})) {
    if (typeof spec !== 'string' || !EXACT.test(spec)) {
      errors.push(`${name} must be pinned to an exact version, got ${JSON.stringify(spec)}`)
    }
    if (section.has(name)) {
      errors.push(`${name} is listed in both ${section.get(name)} and ${key}: keep one`)
    }
    section.set(name, key)
  }
}
const deps = { ...pkg.dependencies, ...pkg.devDependencies, ...optional }

const nodeVersion = existsSync(join(ROOT, '.node-version')) ? read('.node-version').trim() : ''
const runtime = pkg.devEngines?.runtime
if (runtime?.name !== 'node' || runtime?.version !== nodeVersion || !SEMVER3.test(nodeVersion)) {
  errors.push(`devEngines.runtime must be node at .node-version's exact version (${JSON.stringify(nodeVersion)}), got ${JSON.stringify(runtime)}`)
}
const manager = pkg.devEngines?.packageManager
if (manager?.name !== 'pnpm' || !SEMVER3.test(String(manager?.version)) || pkg.packageManager !== `pnpm@${manager.version}`) {
  errors.push(`devEngines.packageManager (pnpm, exact) and packageManager (pnpm@<same>) must agree, got ${JSON.stringify(manager)} and ${JSON.stringify(pkg.packageManager)}`)
}

// The train: effect and every @effect/* package (the language-service patcher
// @effect/tsgo has its own versions) share one version, and Foldkit names it.
const effect = deps.effect
if (effect === undefined) {
  errors.push('effect must be a dependency')
}
for (const [name, spec] of Object.entries(deps)) {
  if (name.startsWith('@effect/') && name !== '@effect/tsgo' && spec !== effect) {
    errors.push(`${name} ${spec} must match effect ${effect}: the Effect train moves together`)
  }
}

// node_modules holds every direct dependency at its pin. pnpm can keep another
// version than the one package.json names (12.6.0 keeps a locked prerelease when
// the pin moves to its stable release), and no other check would notice.
const missing = []
for (const [name, spec] of Object.entries(deps)) {
  const meta = installed(name)
  if (meta === undefined) {
    if (!Object.hasOwn(optional, name)) {
      missing.push(name)
    }
  } else if (EXACT.test(String(spec)) && meta.version !== spec) {
    errors.push(`node_modules has ${name} ${meta.version}, package.json pins ${spec}: run pnpm install (if it stays, pnpm-lock.yaml holds the other version: regenerate it)`)
  }
}
if (missing.length > 0) {
  errors.push(`node_modules is missing ${missing.join(', ')}: run pnpm install`)
}

const foldkit = installed('foldkit')
if (foldkit !== undefined) {
  for (const peer of ['effect', '@effect/platform-browser']) {
    const wanted = foldkit.peerDependencies?.[peer]
    if (wanted !== deps[peer]) {
      errors.push(`foldkit ${foldkit.version} needs ${peer} ${wanted}, package.json pins ${deps[peer]}: move the train together (docs/guides/foldkit.md)`)
    }
  }
  // Every @foldkit/* package pins the same exact Effect and names a foldkit range;
  // @foldkit/devtools is released in lockstep with foldkit itself.
  for (const name of Object.keys(deps).filter(dep => dep.startsWith('@foldkit/'))) {
    const meta = installed(name)
    if (meta === undefined) {
      continue
    }
    for (const [peer, range] of Object.entries(meta.peerDependencies ?? {})) {
      const pinned = peer === 'foldkit' ? foldkit.version : deps[peer]
      if (pinned === undefined) {
        continue
      }
      const ok = satisfies(pinned, range)
      if (ok === undefined) {
        errors.push(`${name} declares ${peer} ${JSON.stringify(range)}, which check-pins cannot evaluate: review the train by hand and extend scripts/check-pins.mjs`)
      } else if (!ok) {
        errors.push(`${name} ${meta.version} needs ${peer} ${range}, package.json pins ${pinned}: move the train together`)
      }
    }
  }
  for (const name of ['@foldkit/devtools', '@foldkit/ui']) {
    if (deps[name] !== undefined && deps[name] !== deps.foldkit) {
      errors.push(`${name} ${deps[name]} must equal foldkit ${deps.foldkit} (they release together)`)
    }
  }
}

// .foldkit-ref records the pinned Foldkit release and the commit its tag named,
// one line: vendor-foldkit.sh refuses a tag that moved. A train move updates it.
const ref = existsSync(join(ROOT, '.foldkit-ref')) ? read('.foldkit-ref') : undefined
const recorded = /^(\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?) ([0-9a-f]{40})\n$/.exec(ref ?? '')
if (ref === undefined) {
  errors.push('.foldkit-ref is missing: it records the pinned Foldkit release and its commit for vendor-foldkit.sh')
} else if (recorded === null) {
  errors.push(`.foldkit-ref must be one line, "<version> <40-character lowercase commit>", got ${JSON.stringify(ref)}`)
} else if (recorded[1] !== deps.foldkit) {
  errors.push(`.foldkit-ref records foldkit ${recorded[1]}, package.json pins ${deps.foldkit}: a train move updates both (git ls-remote https://github.com/foldkit/foldkit.git refs/tags/foldkit@${deps.foldkit} gives the commit)`)
}

// pnpm-workspace.yaml holds the supply-chain policy every install runs under,
// read without a YAML library: flat `key: value` lines, and an optional
// minimumReleaseAgeExclude block list. A line it can't read unambiguously fails,
// and so does any other key: adding one is a reviewed change to this file.
const POLICY = {
  minimumReleaseAge: { want: 'a whole number of minutes, at least 1440 (a day)', valid: value => /^\d+$/.test(value) && Number(value) >= 1440 },
  trustPolicy: { want: 'no-downgrade', valid: value => value === 'no-downgrade' },
  strictDepBuilds: { want: 'true', valid: value => value === 'true' },
  blockExoticSubdeps: { want: 'true', valid: value => value === 'true' },
  allowBuilds: { want: '{}', valid: value => value === '{}' },
}
// An age exemption names one release of the Foldkit + Effect train that
// package.json pins: no bare name, scope, range or other version.
const TRAIN = /^(?:foldkit|effect|@foldkit\/[a-z0-9][\w.-]*|@effect\/[a-z0-9][\w.-]*)$/
const EXCLUDE = 'minimumReleaseAgeExclude'
// The settings and age exemptions in pnpm-workspace.yaml's lines, reporting what
// it cannot read.
const readPolicy = lines => {
  const settings = new Map()
  const exempt = []
  let inList = false
  for (const [index, text] of lines.entries()) {
    const at = `pnpm-workspace.yaml:${index + 1}`
    if (/^\s*(?:#.*)?$/.test(text)) {
      continue
    }
    const item = /^ *- +(?:'([^'"\\]*)'|"([^'"\\]*)"|([^\s'"#@][^\s#]*))(?: +#.*)?$/.exec(text)
    const pair = /^([A-Za-z]+):(?: +([^\s#][^#]*?))? *(?: #.*)?$/.exec(text)
    if (item && inList) {
      exempt.push({ entry: item[1] ?? item[2] ?? item[3], at })
    } else if (pair && settings.has(pair[1])) {
      errors.push(`${at}: ${pair[1]} is given twice`)
    } else if (pair) {
      settings.set(pair[1], pair[2] ?? '')
      inList = pair[1] === EXCLUDE && pair[2] === undefined
      if (pair[1] !== EXCLUDE && !Object.hasOwn(POLICY, pair[1])) {
        errors.push(`${at}: ${pair[1]} is not a policy setting check-pins knows: adding one is a reviewed change to scripts/check-pins.mjs`)
      }
      if (pair[1] === EXCLUDE && pair[2] !== undefined && pair[2] !== '[]') {
        errors.push(`${at}: write ${EXCLUDE} as a block list, one "- name@version" per line`)
      }
    } else {
      errors.push(`${at}: check-pins cannot read this line unambiguously (flat key: value lines and a ${EXCLUDE} list of "- name@version" items; quote a scoped name): ${JSON.stringify(text)}`)
    }
  }
  return { settings, exempt }
}
if (existsSync(join(ROOT, 'pnpm-workspace.yaml'))) {
  const { settings, exempt } = readPolicy(read('pnpm-workspace.yaml').split('\n'))
  for (const [key, { want, valid }] of Object.entries(POLICY)) {
    if (!settings.has(key)) {
      errors.push(`pnpm-workspace.yaml must set ${key}: ${want}`)
    } else if (!valid(settings.get(key))) {
      errors.push(`pnpm-workspace.yaml: ${key} must be ${want}, got ${JSON.stringify(settings.get(key))}`)
    }
  }
  const seen = new Set()
  for (const { entry, at } of exempt) {
    const [, name, release] = /^(@?[^@]+)@(.+)$/.exec(entry) ?? []
    if (seen.has(entry)) {
      errors.push(`${at}: ${EXCLUDE} lists ${JSON.stringify(entry)} twice`)
    } else if (name === undefined || !EXACT.test(release)) {
      errors.push(`${at}: ${EXCLUDE} entry ${JSON.stringify(entry)} must be an exact name@version (no bare name, scope or range)`)
    } else if (!TRAIN.test(name)) {
      errors.push(`${at}: ${EXCLUDE} entry ${JSON.stringify(entry)}: only the Foldkit and Effect train (foldkit, @foldkit/*, effect, @effect/*) may skip the age rule`)
    } else if (deps[name] !== release) {
      errors.push(`${at}: ${EXCLUDE} entry ${JSON.stringify(entry)}: package.json pins ${deps[name] === undefined ? `no ${name}` : `${name} ${deps[name]}`}; exempt only a release it pins, and remove the entry once that is a day old`)
    }
    seen.add(entry)
  }
} else {
  errors.push('pnpm-workspace.yaml is missing: it holds the supply-chain policy')
}

for (const error of errors) {
  console.error(`check-pins: FAIL ${error}`)
}
console.log(`check-pins: ${errors.length > 0 ? 'FAILED' : 'ok'}`)
process.exitCode = errors.length > 0 ? 1 : 0
