#!/usr/bin/env node
// Source rules the type checker can't see (Node standard library only), run by
// scripts/check.d/foldkit.sh. Each violation is reported as file:line; any
// violation or unreadable file exits 1. docs/guides/foldkit.md explains them.
//
// - Boundary: src/domain and src/api import no foldkit, foldkit/... or
//   @foldkit/... module in any form (type-only included), and name every module
//   they load with a plain string.
// - Mocks: src and e2e call no mock, doMock or importMock on Vitest's vi, under
//   any name (aliases, namespace imports, the global).
// - DevTools relay: only the root vite.config.ts configures Vite, and it calls
//   the Foldkit plugin once: relay off, or the token-protected default.
// - MCP: an agent's Foldkit MCP server runs the pinned local bin.
// - Sources: src holds .ts modules only (coverage measures src/**/*.ts).
//
// The rules read code through a deliberately small tokenizer, not regular
// expressions over lines: comments, strings (escapes decoded), template
// literals, regular expressions, identifiers and punctuators. It refuses what
// it cannot read, and the rules refuse any use of a name they govern outside
// the forms below, instead of guessing. Extend this file, with a test, when a
// safe form is refused.
import { lstatSync, readFileSync, readdirSync, statSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = dirname(dirname(fileURLToPath(import.meta.url)))
const SCRIPT = /\.(?:[cm]?[jt]s|[jt]sx)$/
const GUIDE = 'see docs/guides/foldkit.md'
const EXTEND = 'extend scripts/check-rules.mjs if the change is safe'
const violations = []
const report = (file, line, message) => violations.push(`${file}:${line}: ${message}`)

// --- tokenizer -------------------------------------------------------------------
class Unreadable extends Error {
  constructor(message, line) {
    super(message)
    this.line = line
  }
}
const ID_START = /[\p{ID_Start}$_]/u
const ID_PART = /[\p{ID_Continue}$\u200c\u200d]/u
const SPACE = /[\t\v\f \u00a0\ufeff\p{Zs}]/u
const PUNCTUATORS = [
  '>>>=', '...', '===', '!==', '**=', '<<=', '>>=', '>>>', '&&=', '||=', '??=',
  '=>', '==', '!=', '<=', '>=', '&&', '||', '??', '?.', '++', '--', '+=', '-=',
  '*=', '%=', '&=', '|=', '^=', '<<', '>>', '**', '{', '}', '(', ')', '[', ']',
  ';', ',', '<', '>', '+', '-', '*', '%', '&', '|', '^', '!', '~', '?', ':',
  '=', '.', '@', '#',
]
// After these keywords an expression starts: `/` opens a regular expression and
// `{` an object literal. After else and do a statement starts: `/` opens a
// regular expression and `{` a block. `void {` is a TypeScript return type
// before a function body, or the void operator.
const BEFORE_EXPRESSION = new Set([
  'return', 'typeof', 'instanceof', 'in', 'of', 'new', 'delete', 'void',
  'throw', 'case', 'yield', 'await', 'default', 'extends', 'as', 'satisfies',
])
const BEFORE_STATEMENT = new Set(['else', 'do'])
const NUMBER = /(?:0[xX][\da-fA-F_]+|0[oO][0-7_]+|0[bB][01_]+|(?:\d[\d_]*(?:\.[\d_]*)?|\.\d[\d_]*)(?:[eE][+-]?\d[\d_]*)?)n?/y
const LINE_END = /[\n\r\u2028\u2029]/g
const isKeyword = (token, set) => token?.type === 'ident' && !token.property && !token.escaped && set.has(token.value)
const newline = (c, next) => c === '\n' || c === '\u2028' || c === '\u2029' || (c === '\r' && next !== '\n')
// Whether a token ends an operand, so a following `!` is TypeScript's postfix
// non-null assertion rather than a logical not.
const endsOperand = token =>
  ['num', 'string', 'template', 'templateTail', 'regex'].includes(token?.type) ||
  (token?.type === 'ident' && !isKeyword(token, BEFORE_EXPRESSION) && !isKeyword(token, BEFORE_STATEMENT)) ||
  (token?.type === 'punct' && ((token.value === ')' && !token.control) || token.value === ']'))

const tokenize = source => {
  const tokens = []
  const references = []
  const stack = []
  let pos = 0
  let line = 1
  const fail = message => {
    throw new Unreadable(message, line)
  }
  const last = () => tokens[tokens.length - 1]
  const push = (type, value, start, extra = {}) => {
    const previous = last()
    const property = previous?.type === 'punct' && ['.', '?.', '#'].includes(previous.value)
    tokens.push({ type, value, line: start, property, ...extra })
  }

  const unicodeEscape = () => {
    if (source[pos] === '{') {
      const end = source.indexOf('}', pos)
      const hex = end < 0 ? '' : source.slice(pos + 1, end)
      if (!/^[\da-fA-F]{1,6}$/.test(hex) || Number.parseInt(hex, 16) > 0x10ffff) {
        fail('malformed \\u{...} escape')
      }
      pos = end + 1
      return String.fromCodePoint(Number.parseInt(hex, 16))
    }
    const hex = source.slice(pos, pos + 4)
    if (!/^[\da-fA-F]{4}$/.test(hex)) {
      fail('malformed \\u escape')
    }
    pos += 4
    return String.fromCharCode(Number.parseInt(hex, 16))
  }
  // pos is at the backslash: the escape's value (a string's cooked text).
  const escape = () => {
    const c = source[pos + 1]
    pos += 2
    switch (c) {
      case 'n': return '\n'
      case 't': return '\t'
      case 'r': return '\r'
      case 'b': return '\b'
      case 'f': return '\f'
      case 'v': return '\v'
      case 'x': {
        const hex = source.slice(pos, pos + 2)
        if (!/^[\da-fA-F]{2}$/.test(hex)) {
          fail('malformed \\x escape')
        }
        pos += 2
        return String.fromCharCode(Number.parseInt(hex, 16))
      }
      case 'u': return unicodeEscape()
      case '\r':
        if (source[pos] === '\n') {
          pos += 1
        }
        line += 1
        return ''
      case '\n': case '\u2028': case '\u2029':
        line += 1
        return ''
      case undefined: return fail('unterminated escape')
      default:
        if (/\d/.test(c) && !(c === '0' && !/\d/.test(source[pos] ?? ''))) {
          fail('legacy octal escape')
        }
        return c === '0' ? '\0' : c
    }
  }
  const string = quote => {
    const start = line
    let value = ''
    pos += 1
    for (;;) {
      const c = source[pos]
      if (c === quote) {
        pos += 1
        return push('string', value, start)
      }
      if (c === undefined || c === '\n' || c === '\r') {
        return fail('unterminated string')
      }
      if (c === '\\') {
        value += escape()
      } else {
        value += c
        pos += 1
      }
    }
  }
  // pos is just past a backtick or the } that closes a substitution.
  const template = head => {
    const start = line
    let value = ''
    // A tagged template may hold any escape (String.raw`\1`); its text then has
    // no cooked value, so it never counts as a plain string.
    let cooked = true
    for (;;) {
      const c = source[pos]
      if (c === undefined) {
        return fail('unterminated template literal')
      }
      if (c === '`') {
        pos += 1
        return push(head ? 'template' : 'templateTail', value, start, cooked ? {} : { uncooked: true })
      }
      if (c === '$' && source[pos + 1] === '{') {
        pos += 2
        push(head ? 'templateHead' : 'templateMiddle', value, start, cooked ? {} : { uncooked: true })
        return stack.push({ open: '${' })
      }
      if (c === '\\') {
        const at = pos
        try {
          value += escape()
        } catch (error) {
          if (!(error instanceof Unreadable) || source[at + 1] === undefined) {
            throw error
          }
          pos = Math.max(pos, at + 2)
          cooked = false
        }
      } else if (c === '\r') {
        value += '\n'
        pos += source[pos + 1] === '\n' ? 2 : 1
        line += 1
      } else {
        value += c
        pos += 1
        if (newline(c)) {
          line += 1
        }
      }
    }
  }
  const identifier = () => {
    const start = line
    let name = ''
    let escaped = false
    for (;;) {
      const c = String.fromCodePoint(source.codePointAt(pos) ?? 32)
      let part = c
      if (c === '\\') {
        if (source[pos + 1] !== 'u') {
          fail('malformed escape in an identifier')
        }
        pos += 2
        part = unicodeEscape()
        escaped = true
      } else if ((name === '' ? ID_START : ID_PART).test(c)) {
        pos += c.length
      } else {
        break
      }
      if (!(name === '' ? ID_START : ID_PART).test(part)) {
        fail('escape that is not an identifier character')
      }
      name += part
    }
    push('ident', name, start, { escaped })
  }
  const regex = () => {
    const start = line
    let inClass = false
    pos += 1
    for (;;) {
      const c = source[pos]
      if (c === undefined || newline(c) || c === '\r') {
        fail('unterminated regular expression')
      }
      if (c === '\\') {
        if (source[pos + 1] === undefined || newline(source[pos + 1]) || source[pos + 1] === '\r') {
          fail('unterminated regular expression')
        }
        pos += 2
        continue
      }
      pos += 1
      if (c === '[') {
        inClass = true
      } else if (c === ']') {
        inClass = false
      } else if (c === '/' && !inClass) {
        break
      }
    }
    while (pos < source.length && ID_PART.test(source[pos])) {
      pos += 1
    }
    push('regex', null, start)
  }
  // The usual heuristic, made exact for `)` (a control statement's condition),
  // `!` and `}` (a block), and refused where a `}` could close either.
  const regexAllowed = () => {
    const previous = last()
    if (previous === undefined || previous.type === 'templateHead' || previous.type === 'templateMiddle') {
      return true
    }
    if (previous.type === 'ident') {
      return isKeyword(previous, BEFORE_EXPRESSION) || isKeyword(previous, BEFORE_STATEMENT)
    }
    if (previous.type !== 'punct') {
      return false
    }
    switch (previous.value) {
      case ')': return previous.control
      case '!': return !endsOperand(tokens[tokens.length - 2])
      case ']': case '++': case '--': return false
      case '}':
        if (previous.kind === 'unknown') {
          fail('cannot tell whether this / after } starts a regular expression: end the statement with a semicolon')
        }
        return previous.kind === 'block'
      default: return true
    }
  }
  const braceKind = () => {
    const previous = last()
    if (previous === undefined) {
      return 'block'
    }
    if (previous.type === 'punct') {
      if ([';', '{'].includes(previous.value)) {
        return 'block'
      }
      if (previous.value === ')') {
        return previous.control ? 'block' : 'unknown'
      }
      return [':', '>', ']', '}', '=>'].includes(previous.value) ? 'unknown' : 'object'
    }
    if (previous.type === 'ident' && !previous.property) {
      if (isKeyword(previous, new Set(['void']))) {
        return 'unknown'
      }
      if (isKeyword(previous, new Set(['else', 'do', 'try', 'finally']))) {
        return 'block'
      }
      return isKeyword(previous, BEFORE_EXPRESSION) ? 'object' : 'unknown'
    }
    return previous.type === 'templateHead' || previous.type === 'templateMiddle' ? 'object' : 'unknown'
  }
  const controlParen = () => {
    const previous = last()
    if (isKeyword(previous, new Set(['if', 'while', 'for', 'with']))) {
      return true
    }
    return isKeyword(previous, new Set(['await'])) && isKeyword(tokens[tokens.length - 2], new Set(['for']))
  }

  const lineEnd = from => {
    LINE_END.lastIndex = from
    return LINE_END.exec(source)?.index ?? source.length
  }
  if (source.startsWith('#!')) {
    pos = lineEnd(0)
  }
  while (pos < source.length) {
    const c = source[pos]
    const next = source[pos + 1]
    if (newline(c, next)) {
      line += 1
      pos += 1
    } else if (c === '\r' || SPACE.test(c)) {
      pos += 1
    } else if (c === '/' && next === '/') {
      const end = lineEnd(pos)
      // A triple-slash directive loads types like an import does.
      const directive = /^\/\/\/\s*<reference\s+(?:types|path)\s*=\s*(["'])(.*?)\1/.exec(source.slice(pos, end))
      if (directive) {
        references.push({ kind: 'reference', specifier: directive[2], line, start: tokens.length, end: tokens.length })
      }
      pos = end
    } else if (c === '/' && next === '*') {
      const end = source.indexOf('*/', pos + 2)
      if (end < 0) {
        fail('unterminated comment')
      }
      line += source.slice(pos, end).match(/\r\n?|[\n\u2028\u2029]/g)?.length ?? 0
      pos = end + 2
    } else if (c === '"' || c === "'") {
      string(c)
    } else if (c === '`') {
      pos += 1
      template(true)
    } else if (c === '}' && stack[stack.length - 1]?.open === '${') {
      stack.pop()
      pos += 1
      template(false)
    } else if (c === '\\' || ID_START.test(String.fromCodePoint(source.codePointAt(pos)))) {
      identifier()
    } else if (/\d/.test(c) || (c === '.' && /\d/.test(next ?? ''))) {
      NUMBER.lastIndex = pos
      NUMBER.exec(source)
      pos = NUMBER.lastIndex
      if (pos < source.length && (ID_START.test(source[pos]) || /\d/.test(source[pos]))) {
        fail('malformed number')
      }
      push('num', null, line)
    } else if (c === '/') {
      if (regexAllowed()) {
        regex()
      } else {
        const value = next === '=' ? '/=' : '/'
        pos += value.length
        push('punct', value, line)
      }
    } else {
      let value = PUNCTUATORS.find(candidate => source.startsWith(candidate, pos))
      if (value === undefined) {
        fail(`unexpected character ${JSON.stringify(c)}`)
      }
      if (value === '?.' && /\d/.test(source[pos + 2] ?? '')) {
        value = '?'
      }
      const extra = {}
      if (value === '(') {
        stack.push({ open: '(', control: controlParen() })
      } else if (value === '[') {
        stack.push({ open: '[' })
      } else if (value === '{') {
        stack.push({ open: '{', kind: braceKind() })
      } else if (value === ')' || value === ']' || value === '}') {
        const open = stack.pop()
        if (open?.open !== { ')': '(', ']': '[', '}': '{' }[value]) {
          fail(`unbalanced ${value}`)
        }
        Object.assign(extra, { control: open.control === true, kind: open.kind })
      }
      pos += value.length
      push('punct', value, line, extra)
    }
  }
  if (stack.length > 0) {
    fail(`unclosed ${stack[stack.length - 1].open}`)
  }
  return { tokens, references }
}

// --- module references ---------------------------------------------------------
const isPunct = (token, value) => token?.type === 'punct' && token.value === value
const isName = (token, value) => token?.type === 'ident' && !token.property && token.value === value
const isText = token => token?.type === 'string' || (token?.type === 'template' && !token.uncooked)

// { kind, specifier (null unless a plain string), line, start, end, ... } for every
// import and export declaration, side-effect import, import(), require() and
// triple-slash reference. A declaration this cannot parse throws.
const moduleRefs = ({ tokens, references }) => {
  const refs = [...references]
  const unreadable = (index, what) => {
    throw new Unreadable(`cannot read this ${what}`, tokens[index].line)
  }
  // The `a as b` pairs between the braces at index (type-only ones included),
  // and the index past the closing brace.
  const specifiers = (index, what) => {
    const names = []
    let i = index + 1
    while (!isPunct(tokens[i], '}')) {
      // `type x`, `type as as y` and `type as` are type-only; `type as y` renames type.
      const after = tokens[i + 1]
      if (isName(tokens[i], 'type') && (after?.type === 'string' || (after?.type === 'ident' &&
        (after.value !== 'as' || isName(tokens[i + 2], 'as') || isPunct(tokens[i + 2], ',') || isPunct(tokens[i + 2], '}'))))) {
        i += 1
      }
      const first = tokens[i]
      if (first?.type !== 'ident' && first?.type !== 'string') {
        unreadable(i, what)
      }
      let second = first
      if (isName(tokens[i + 1], 'as')) {
        second = tokens[i + 2]
        if (second?.type !== 'ident' && second?.type !== 'string') {
          unreadable(i, what)
        }
        i += 2
      }
      names.push({ first: first.value, second: second.value })
      i += 1
      if (isPunct(tokens[i], ',')) {
        i += 1
      } else if (!isPunct(tokens[i], '}')) {
        unreadable(i, what)
      }
    }
    return { names, end: i + 1 }
  }
  const call = (kind, index) => {
    const argument = tokens[index + 2]
    const after = tokens[index + 3]
    const plain = isText(argument) && (isPunct(after, ')') || isPunct(after, ','))
    return { kind, specifier: plain ? argument.value : null, line: tokens[index].line, start: index, end: index + 1 }
  }
  for (let index = 0; index < tokens.length; index += 1) {
    const token = tokens[index]
    const next = tokens[index + 1]
    if (token.type === 'ident' && token.value === 'require' && isPunct(next, '(')) {
      refs.push(call('require', index))
    }
    // An escaped import or export is no keyword. Elsewhere they are member, key or
    // exported names (x.import, { import: 1 }, export { a as import }).
    if (token.type !== 'ident' || token.escaped || token.property || (token.value !== 'import' && token.value !== 'export')) {
      continue
    }
    const declaration = next?.type === 'string' || next?.type === 'ident' || isPunct(next, '{') || isPunct(next, '*')
    if (token.value === 'import' && isPunct(next, '(')) {
      refs.push(call('import()', index))
      continue
    }
    if (!declaration) {
      continue
    }
    if (token.value === 'import') {
      if (next.type === 'string') {
        refs.push({ kind: 'import', specifier: next.value, line: token.line, start: index, end: index + 2, names: [] })
        index += 1
        continue
      }
      let i = index + 1
      const ref = { kind: 'import', specifier: null, line: token.line, start: index, names: [] }
      if (isName(tokens[i], 'type') && !isPunct(tokens[i + 1], ',') && !isName(tokens[i + 1], 'from') && !isPunct(tokens[i + 1], '=')) {
        i += 1
      }
      if (tokens[i]?.type === 'ident' && !tokens[i].escaped) {
        ref.default = tokens[i].value
        i += 1
        if (isPunct(tokens[i], '=')) {
          // TypeScript's `import x = require('m')` (require() records the module)
          // or `import x = Namespace.Member`.
          refs.push({ ...ref, kind: 'import =', end: i + 1 })
          index = i
          continue
        }
        if (isPunct(tokens[i], ',')) {
          i += 1
        }
      }
      if (isPunct(tokens[i], '*') && isName(tokens[i + 1], 'as') && tokens[i + 2]?.type === 'ident') {
        ref.namespace = tokens[i + 2].value
        i += 3
      } else if (isPunct(tokens[i], '{')) {
        const list = specifiers(i, 'import')
        ref.names = list.names.map(({ first, second }) => ({ imported: first, local: second }))
        i = list.end
      }
      if (!isName(tokens[i], 'from') || tokens[i + 1]?.type !== 'string') {
        unreadable(index, 'import')
      }
      refs.push({ ...ref, specifier: tokens[i + 1].value, end: i + 2 })
      index = i + 1
      continue
    }
    // export: only `export * ... from` and `export {...} from` name a module.
    let i = index + 1
    if (isName(tokens[i], 'type') && (isPunct(tokens[i + 1], '{') || isPunct(tokens[i + 1], '*'))) {
      i += 1
    }
    if (isPunct(tokens[i], '*')) {
      const ref = { kind: 'export from', star: true, names: [], line: token.line, start: index }
      i += 1
      if (isName(tokens[i], 'as')) {
        ref.names = [{ imported: '*', exported: tokens[i + 1]?.value }]
        i += 2
      }
      if (!isName(tokens[i], 'from') || tokens[i + 1]?.type !== 'string') {
        unreadable(index, 'export')
      }
      refs.push({ ...ref, specifier: tokens[i + 1].value, end: i + 2 })
      index = i + 1
    } else if (isPunct(tokens[i], '{')) {
      const list = specifiers(i, 'export')
      if (isName(tokens[list.end], 'from') && tokens[list.end + 1]?.type === 'string') {
        refs.push({
          kind: 'export from',
          star: false,
          names: list.names.map(({ first, second }) => ({ imported: first, exported: second })),
          specifier: tokens[list.end + 1].value,
          line: token.line,
          start: index,
          end: list.end + 2,
        })
        index = list.end + 1
      } else {
        index = list.end - 1
      }
    }
  }
  return refs
}

// --- reading the project ---------------------------------------------------------
const parsed = new Map()
const source = file => {
  try {
    return readFileSync(join(ROOT, file), 'utf8')
  } catch (error) {
    report(file, 1, `cannot read it (${error.code ?? error.message})`)
    return undefined
  }
}
// The file's tokens and module references, or undefined (reported) when it
// can't be read.
const read = file => {
  if (!parsed.has(file)) {
    const text = source(file)
    let result
    if (text !== undefined) {
      try {
        const lexed = tokenize(text)
        result = { ...lexed, refs: moduleRefs(lexed) }
      } catch (error) {
        if (!(error instanceof Unreadable)) {
          throw error
        }
        report(file, error.line, `check-rules cannot read this file: ${error.message} (${EXTEND})`)
      }
    }
    parsed.set(file, result)
  }
  return parsed.get(file)
}
const exists = file => {
  try {
    lstatSync(join(ROOT, file))
    return true
  } catch {
    return false
  }
}
// src and e2e are read whole. Elsewhere generated and vendored trees are left
// out, and so is another repository inside this one (an agent's worktree, say:
// it has its own checks).
const GOVERNED = /^(?:src|e2e)(?:\/|$)/
const GENERATED = new Set(['repos', 'dist', 'coverage', 'test-results', 'playwright-report', 'blob-report'])
const prune = (path, name) =>
  name === '.git' ||
  (!GOVERNED.test(path) && (name === 'node_modules' || (!path.includes('/') && GENERATED.has(name)) || exists(`${path}/.git`)))
// Every file in the project, relative to its root. An unreadable directory, a
// broken link and (in src and e2e) a link to a directory are reported.
const walk = dir => {
  let entries
  try {
    entries = readdirSync(join(ROOT, dir), { withFileTypes: true })
  } catch (error) {
    report(dir, 1, `cannot read this directory (${error.code ?? error.message})`)
    return []
  }
  return entries.flatMap(entry => {
    const path = dir === '.' ? entry.name : `${dir}/${entry.name}`
    let directory = entry.isDirectory()
    if (entry.isSymbolicLink()) {
      try {
        directory = statSync(join(ROOT, path)).isDirectory()
      } catch (error) {
        report(path, 1, `is a broken symbolic link (${error.code ?? error.message})`)
        return []
      }
      if (directory) {
        if (GOVERNED.test(path)) {
          report(path, 1, `is a symbolic link to a directory, which check-rules does not follow (${EXTEND})`)
        }
        return []
      }
    }
    if (directory) {
      return prune(path, entry.name) ? [] : walk(path)
    }
    return entry.isFile() || entry.isSymbolicLink() ? [path] : []
  })
}
const files = walk('.')
const scripts = files.filter(path => SCRIPT.test(path))
const under = (...dirs) => scripts.filter(path => dirs.some(dir => path.startsWith(`${dir}/`)))
const lineOf = (text, needle) => (text.slice(0, Math.max(0, text.indexOf(needle))).match(/\n/g)?.length ?? 0) + 1

// --- boundary: src/domain and src/api stay framework-free -------------------------
const FOLDKIT = /^@?foldkit(?:\/|$)|(?:^|\/)(?:node_modules\/@?foldkit|repos\/foldkit)(?:\/|$)/
for (const file of under('src/domain', 'src/api')) {
  for (const ref of read(file)?.refs ?? []) {
    if (ref.kind === 'import =') {
      continue
    }
    if (ref.specifier === null) {
      report(file, ref.line, `${ref.kind} of a computed module name: src/domain and src/api name every module with a plain string, so this check can see it (${GUIDE})`)
    } else if (FOLDKIT.test(ref.specifier)) {
      report(file, ref.line, `loads ${JSON.stringify(ref.specifier)}: src/domain and src/api must not import foldkit (they stay framework-free; ${GUIDE})`)
    }
  }
}

// --- mocks: no vi.mock, vi.doMock or vi.importMock --------------------------------
const VITEST = new Set(['vitest', '@effect/vitest'])
const VI = new Set(['vi', 'vitest'])
const MOCKS = new Set(['mock', 'doMock', 'importMock'])
const NO_MOCK = 'no vi.mock, vi.doMock or vi.importMock: swap a Layer at the network edge instead (TESTING.md: mocks only at trust boundaries)'
// The identifier after the `.` at index, if there is one.
const member = (tokens, index) => (isPunct(tokens[index], '.') && tokens[index + 1]?.type === 'ident' ? tokens[index + 1] : undefined)
// A non-call typeof query may name the binding or a dotted member. Do not
// exempt calls, computed members, optional access or postfix assertions: a
// runtime typeof still evaluates its operand, including a forbidden mock.
const typeQuery = (tokens, index) => {
  if (!isName(tokens[index - 1], 'typeof')) {
    return false
  }
  let end = index + 1
  while (member(tokens, end) !== undefined) {
    end += 2
  }
  const next = tokens[end]
  return next === undefined ||
    (next.type === 'punct' && [';', ',', '}', ')', ']', '|', '&'].includes(next.value)) ||
    (next.line > tokens[end - 1].line && isKeyword(next, new Set(['type', 'interface', 'const', 'let', 'var', 'export', 'import', 'declare', 'function', 'class'])))
}
for (const file of under('src', 'e2e')) {
  const lexed = read(file)
  if (lexed === undefined) {
    continue
  }
  const { tokens, refs } = lexed
  // vi and vitest count even unimported: Vitest's globals option defines them.
  const bindings = new Set(VI)
  const namespaces = new Set()
  const declared = new Set()
  for (const ref of refs) {
    for (let index = ref.start; index < ref.end; index += 1) {
      declared.add(index)
    }
    if (!VITEST.has(ref.specifier) || ref.kind === 'reference') {
      continue
    }
    if (ref.kind === 'import') {
      if (ref.default !== undefined || ref.names.some(name => name.imported === 'default')) {
        report(file, ref.line, `a default import from ${ref.specifier} is not a form check-rules can follow (${EXTEND})`)
      }
      if (ref.namespace !== undefined) {
        namespaces.add(ref.namespace)
      }
      for (const name of ref.names.filter(entry => VI.has(entry.imported))) {
        bindings.add(name.local)
      }
    } else if (ref.kind === 'export from') {
      if (ref.star || ref.names.some(name => VI.has(name.imported) || name.imported === 'default')) {
        report(file, ref.line, `re-exports vi from ${ref.specifier}, which would hide its calls: ${NO_MOCK}`)
      }
    } else {
      report(file, ref.line, `${ref.kind} loads ${ref.specifier}: import { vi } statically, so check-rules can follow it`)
    }
  }
  // A binding may only be called as binding.method(...) (or <...>(...)), and a
  // namespace only read as ns.name, or called as ns.vi.method(...).
  tokens.forEach((token, index) => {
    if (token.type !== 'ident' || token.property || declared.has(index) || typeQuery(tokens, index)) {
      return
    }
    let shown = token.value
    let called = member(tokens, index + 1)
    let after = index + 3
    if (namespaces.has(token.value)) {
      if (called !== undefined && !VI.has(called.value)) {
        return
      }
      shown = called === undefined ? shown : `${shown}.${called.value}`
      called = called === undefined ? undefined : member(tokens, index + 3)
      after = index + 5
    } else if (!bindings.has(token.value)) {
      return
    }
    if (called !== undefined && MOCKS.has(called.value)) {
      report(file, token.line, `${shown}.${called.value}: ${NO_MOCK}`)
    } else if (called === undefined || !(isPunct(tokens[after], '(') || isPunct(tokens[after], '<'))) {
      report(file, token.line, `${shown} is used other than as ${shown}.<method>(...) (an alias, an argument, a computed member), which could hide a mock: ${NO_MOCK} (${EXTEND})`)
    }
  })
}

// --- DevTools relay: one plugin call, in the root vite.config.ts ------------------
// Joined at run time: this file is one of the scripts the plugin count below reads.
const PLUGIN = ['@foldkit', 'vite-plugin'].join('/')
const CONFIG = 'vite.config.ts'
const RELAY = `${CONFIG} must import { foldkit } from '${PLUGIN}' once and call foldkit({ devToolsMcpPort: false }) (relay off) or foldkit() (the token-protected relay) once; a numeric devToolsMcpPort opens an unauthenticated DevTools relay on every network interface (${GUIDE}; ${EXTEND})`
// Tokens as text in which only punctuators and plain identifiers read as
// themselves: { devToolsMcpPort: 'false' } (a string) is not { devToolsMcpPort: false }.
const shape = tokens =>
  tokens.map(token => (token.type === 'punct' || (token.type === 'ident' && !token.escaped) ? token.value : `<${token.type}>`)).join(' ')
// A bounded, non-evaluating shell grammar: literal words, quotes and escapes,
// joined by &&, ||, ; or newline. Expansions, redirection, grouping and nested
// shell evaluation need a reviewed extension; this is not a shell sandbox.
const unsupported = detail => { throw new Error(`unsupported shell syntax (${detail})`) }
const shellCommands = command => {
  const commands = []
  let words = []
  let word = ''
  let started = false
  let quote
  const finishWord = () => {
    if (started) {
      words.push(word)
      word = ''
      started = false
    }
  }
  const finishCommand = () => {
    finishWord()
    if (words.length > 0) {
      commands.push(words)
      words = []
    }
  }
  for (let index = 0; index < command.length; index += 1) {
    const char = command[index]
    const next = command[index + 1]
    if (quote === "'") {
      if (char === quote) {
        quote = undefined
      } else {
        word += char
      }
    } else if (char === '\\') {
      if (next === undefined) {
        unsupported('trailing backslash')
      }
      if (quote === '"' && !['$', '`', '"', '\\', '\n'].includes(next)) {
        word += char
      } else {
        index += 1
        if (next !== '\n') {
          word += next
          started = true
        }
      }
    } else if (char === quote) {
      quote = undefined
    } else if (char === '$' || char === '`') {
      unsupported('expansion or substitution')
    } else if (quote === '"') {
      word += char
    } else if (char === "'" || char === '"') {
      quote = char
      started = true
    } else if (char === '\n' || char === ';' || ((char === '&' || char === '|') && next === char)) {
      finishCommand()
      if (char === '&' || char === '|') {
        index += 1
      }
    } else if (/[\t\r ]/.test(char)) {
      finishWord()
    } else if (/[&|<>()*?[\]{}]/.test(char) || (!started && (char === '~' || char === '#'))) {
      unsupported(`operator or expansion ${JSON.stringify(char)}`)
    } else {
      word += char
      started = true
    }
  }
  if (quote !== undefined) {
    unsupported('unterminated quote')
  }
  finishCommand()
  for (const commandWords of commands) {
    let executable = 0
    let wrapped = false
    // Literal environment assignments and the standard execution wrappers do
    // not change the following executable's identity. Wrapper options have
    // their own semantics: reject them rather than mistake one for the command.
    while (executable < commandWords.length) {
      const argument = commandWords[executable]
      if (/^[A-Za-z_][A-Za-z0-9_]*=/.test(argument)) {
        executable += 1
      } else if (['env', 'command', 'exec'].includes(argument.split('/').pop())) {
        wrapped = true
        executable += 1
      } else {
        if (wrapped && argument.startsWith('-')) {
          unsupported('wrapper options need a reviewed checker extension')
        }
        break
      }
    }
    if (/^(?:.*\/)?(?:[bdkz]?sh|bash|dash|fish|csh|tcsh|eval|source|\.)$/.test(commandWords[executable] ?? '')) {
      unsupported('nested shell evaluation')
    }
  }
  return commands
}
const checkShellCommand = (command, file, line, forbidden, requireLiteral = true) => {
  if (typeof command !== 'string') {
    report(file, line, `${forbidden}: ${RELAY}`)
    return
  }
  let commands
  try {
    commands = shellCommands(command)
  } catch (error) {
    if (requireLiteral) {
      report(file, line, `${error.message}: ${RELAY}`)
    }
    return
  }
  if (commands.some(words => {
    const vite = words.findIndex(word => /(?:^|\/)vite(?:\.m?js)?$/.test(word))
    return vite >= 0 && words.slice(vite + 1).some(word => /^--config(?:[=.].*)?$|^-[A-Za-z]*c[A-Za-z]*(?:=.*)?$/.test(word))
  })) {
    report(file, line, `${forbidden}: ${RELAY}`)
  }
}
for (const file of files.filter(path => path.split('/').pop().startsWith('vite.config.') && path !== CONFIG)) {
  report(file, 1, `only the root ${CONFIG} may configure Vite: ${RELAY}`)
}
const manifest = source('package.json')
if (manifest !== undefined) {
  let commands = {}
  try {
    commands = JSON.parse(manifest).scripts ?? {}
  } catch (error) {
    report('package.json', 1, `is not valid JSON (${error.message})`)
  }
  for (const [name, command] of Object.entries(commands)) {
    checkShellCommand(command, 'package.json', lineOf(manifest, JSON.stringify(name)), `script ${JSON.stringify(name)} must be a command that passes no --config to vite`)
  }
}
if (exists('playwright.config.ts')) {
  const { tokens = [], refs = [] } = read('playwright.config.ts') ?? {}
  const closes = new Map()
  const depths = []
  const stack = []
  tokens.forEach((token, index) => {
    depths[index] = stack.length
    if (token.type === 'punct' && ['{', '[', '('].includes(token.value)) {
      stack.push(index)
    } else if (token.type === 'punct' && ['}', ']', ')'].includes(token.value)) {
      closes.set(stack.pop(), index)
    }
  })
  const bindings = new Map()
  tokens.forEach((token, index) => {
    if (isKeyword(token, new Set(['const', 'let', 'var'])) && tokens[index + 1]?.type === 'ident') {
      const name = tokens[index + 1].value
      const entries = bindings.get(name) ?? []
      entries.push(isName(token, 'const') && depths[index] === 0 && isPunct(tokens[index + 2], '=') ? index + 3 : undefined)
      bindings.set(name, entries)
    }
  })
  const property = (index, name) =>
    (isName(tokens[index], name) || (isText(tokens[index]) && tokens[index].value === name)) &&
    (isPunct(tokens[index - 1], '{') || isPunct(tokens[index - 1], ',')) &&
    !refs.some(ref => index >= ref.start && index < ref.end)
  const plainCommand = index => isPunct(tokens[index + 1], ':') && isText(tokens[index + 2]) &&
    (isPunct(tokens[index + 3], ',') || isPunct(tokens[index + 3], '}'))
  const cannotFollow = index => report('playwright.config.ts', tokens[index]?.line ?? 1,
    `cannot follow this webServer value: use literal objects/arrays or unambiguous local const aliases (${EXTEND})`)
  const valueEnd = index => closes.has(index) ? closes.get(index) + 1 : tokens[index]?.type === 'ident' ? index + 1 : undefined
  const strictCommands = new Set()
  const follow = (index, end, visited = new Set()) => {
    if (valueEnd(index) !== end) {
      cannotFollow(index)
      return
    }
    if (tokens[index]?.type === 'ident') {
      const name = tokens[index].value
      const entries = bindings.get(name) ?? []
      const value = entries[0]
      const last = value === undefined ? undefined : valueEnd(value)
      const after = tokens[last]
      const terminated = last !== undefined && (after === undefined || isPunct(after, ';') ||
        (after.line > tokens[last - 1].line && isKeyword(after, new Set(['const', 'let', 'var', 'export', 'import', 'function', 'class', 'type', 'interface']))))
      if (entries.length !== 1 || visited.has(name) || !terminated) {
        cannotFollow(index)
        return
      }
      follow(value, last, new Set([...visited, name]))
      return
    }
    if (!isPunct(tokens[index], '{') && !isPunct(tokens[index], '[')) {
      cannotFollow(index)
      return
    }
    for (let entry = index + 1; entry < end - 1;) {
      let next = entry
      while (next < end - 1 && !isPunct(tokens[next], ',')) {
        next = closes.has(next) ? closes.get(next) + 1 : next + 1
      }
      if (isPunct(tokens[index], '[')) {
        follow(entry, next, visited)
      } else if (!((tokens[entry]?.type === 'ident' || isText(tokens[entry])) && isPunct(tokens[entry + 1], ':')) &&
        !(tokens[entry]?.type === 'ident' && tokens[entry].value !== 'command' && next === entry + 1)) {
        cannotFollow(entry)
      } else if (property(entry, 'command') && plainCommand(entry)) {
        strictCommands.add(entry + 2)
      }
      entry = next + 1
    }
  }
  tokens.forEach((token, index) => {
    if (property(index, 'command') && !plainCommand(index)) {
      report('playwright.config.ts', token.line, `the webServer command must be one plain string, so check-rules can read it (${EXTEND})`)
    }
    if (property(index, 'webServer')) {
      const value = isPunct(tokens[index + 1], ':') ? index + 2 : index
      const end = valueEnd(value)
      if (end === undefined || !(isPunct(tokens[end], ',') || isPunct(tokens[end], '}'))) {
        cannotFollow(index)
      } else {
        follow(value, end)
      }
    }
  })
  tokens.forEach((token, index) => {
    // Retain the permissive scan for other literal strings, including metadata
    // commands and paths. Only commands reached through webServer must satisfy
    // the entire shell grammar; this does not evaluate JavaScript expressions.
    if (token.type === 'string' || token.type.startsWith('template')) {
      checkShellCommand(token.value, 'playwright.config.ts', token.line, 'a command passes --config to vite', strictCommands.has(index))
    }
  })
}
// Checks vite.config.ts; returns its one allowed plugin specifier token, if any.
const checkConfig = ({ tokens, refs }) => {
  for (const ref of refs.filter(entry => entry.specifier === null && entry.kind !== 'import =')) {
    report(CONFIG, ref.line, `${ref.kind} of a computed module name, which check-rules cannot follow: ${RELAY}`)
  }
  const imports = refs.filter(entry => entry.specifier === PLUGIN || entry.specifier?.startsWith(`${PLUGIN}/`))
  const [plugin] = imports
  const exact = imports.length === 1 && plugin.end - plugin.start === 6 &&
    shape(tokens.slice(plugin.start, plugin.start + 5)) === 'import { foldkit } from'
  if (!exact) {
    report(CONFIG, plugin?.line ?? 1, `imports ${PLUGIN} other than as import { foldkit } from '${PLUGIN}', once: ${RELAY}`)
  }
  const inImport = at => imports.some(entry => at >= entry.start && at < entry.end)
  const uses = tokens.flatMap((token, at) => (token.type === 'ident' && token.value === 'foldkit' && !inImport(at) ? [at] : []))
  const calls = uses.filter(at => !tokens[at].property && isPunct(tokens[at + 1], '('))
  for (const index of uses.filter(at => !calls.includes(at))) {
    report(CONFIG, tokens[index].line, `uses foldkit other than as the one plugin call: ${RELAY}`)
  }
  if (calls.length !== 1) {
    report(CONFIG, tokens[calls[1]]?.line ?? 1, `calls foldkit(...) ${calls.length} times: ${RELAY}`)
  }
  for (const index of calls) {
    let depth = 0
    let end = index + 1
    do {
      depth += isPunct(tokens[end], '(') ? 1 : isPunct(tokens[end], ')') ? -1 : 0
      end += 1
    } while (depth > 0 && end < tokens.length)
    // Whitespace-normalized; the trailing commas a formatter may add are allowed.
    const argument = shape(tokens.slice(index + 2, end - 1)).replace(/ ,(?= \}|$)/g, '')
    if (argument !== '' && argument !== '{ devToolsMcpPort : false }') {
      report(CONFIG, tokens[index].line, `foldkit(...) takes another argument than { devToolsMcpPort: false } or none: ${RELAY}`)
    }
  }
  return exact ? tokens[plugin.start + 5] : undefined
}
if (!exists(CONFIG)) {
  report(CONFIG, 1, `is missing: ${RELAY}`)
}
const config = exists(CONFIG) ? read(CONFIG) : undefined
const allowed = config === undefined ? undefined : checkConfig(config)
for (const file of scripts) {
  for (const token of read(file)?.tokens ?? []) {
    if ((token.type === 'string' || token.type.startsWith('template')) && token.value.includes(PLUGIN) && token !== allowed) {
      report(file, token.line, `names ${PLUGIN}: only ${CONFIG} loads it, once: ${RELAY}`)
    }
  }
}

// --- MCP: the pinned local bin ------------------------------------------------------
const BIN = 'node_modules/.bin/foldkit-devtools-mcp'
const isObject = value => typeof value === 'object' && value !== null && !Array.isArray(value)
const localBin = server =>
  isObject(server) &&
  server.command === BIN &&
  Object.entries(server).every(([key, value]) =>
    key === 'command' || (key === 'type' && value === 'stdio') || (key === 'env' && isObject(value) && Object.values(value).every(item => typeof item === 'string')))
for (const file of ['.mcp.json', '.cursor/mcp.json', '.vscode/mcp.json'].filter(exists)) {
  const text = source(file)
  let settings
  try {
    settings = text === undefined ? undefined : JSON.parse(text)
  } catch (error) {
    report(file, 1, `is not valid JSON, so check-rules cannot check its Foldkit server (${error.message})`)
  }
  for (const key of ['mcpServers', 'servers']) {
    const servers = isObject(settings) ? settings[key] : undefined
    if (servers !== undefined && !isObject(servers)) {
      report(file, lineOf(text, JSON.stringify(key)), `${key} must be an object`)
    }
    for (const [name, server] of Object.entries(isObject(servers) ? servers : {})) {
      if (/foldkit/i.test(JSON.stringify(server) ?? '') && !localBin(server)) {
        report(file, lineOf(text, JSON.stringify(name)), `server ${JSON.stringify(name)} must call the pinned local bin: exactly {"command": "${BIN}"} (an "env" object may be added), never npx, pnpm dlx, pnpx, bunx or yarn dlx (${GUIDE})`)
      }
    }
  }
}

// --- sources: .ts only under src ----------------------------------------------------
for (const file of files.filter(path => path.startsWith('src/') && /\.(?:[cm]ts|tsx|[cm]?js|jsx)$/.test(path))) {
  report(file, 1, 'coverage measures src/**/*.ts only, so this module would escape the floors: write it as .ts')
}

for (const violation of violations) {
  console.error(`check-rules: FAIL ${violation}`)
}
console.log(`check-rules: ${violations.length > 0 ? 'FAILED' : 'ok'}`)
process.exitCode = violations.length > 0 ? 1 : 0
