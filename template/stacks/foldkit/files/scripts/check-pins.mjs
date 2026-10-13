#!/usr/bin/env node
// Pin guard (Node standard library only), run by scripts/check.d/foldkit.sh:
// package.json stays in the byte form gstack /ship writes, its version is VERSION,
// every dependency is exact, the runtime and package manager are pinned once,
// node_modules holds each dependency at its pin, and the Foldkit + Effect train
// moves together.
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

// Optional dependencies are pinned like the rest; pnpm may skip one on a platform
// it doesn't support, so only those may be missing from node_modules. Each
// section is checked on its own: merged, one section's entry would hide another's.
const SECTIONS = ['dependencies', 'devDependencies', 'optionalDependencies']
const optional = pkg.optionalDependencies ?? {}
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

for (const error of errors) {
  console.error(`check-pins: FAIL ${error}`)
}
console.log(`check-pins: ${errors.length > 0 ? 'FAILED' : 'ok'}`)
process.exitCode = errors.length > 0 ? 1 : 0
