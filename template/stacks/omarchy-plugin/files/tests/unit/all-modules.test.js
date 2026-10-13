// Loads every logic module outside tests/, the *.js files and the *.mjs
// ECMAScript modules QML can import too, so none can hide from the coverage
// gate: Node reports only files that were loaded.
const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const { pathToFileURL } = require("node:url")

const root = path.join(__dirname, "..", "..")

function modules(dir) {
  return fs.readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
    const file = path.join(dir, entry.name)
    if (!entry.isDirectory()) return /\.m?js$/.test(entry.name) ? [file] : []
    const skip = entry.name.startsWith(".") || entry.name === "node_modules" || file === path.join(root, "tests")
    return skip ? [] : modules(file)
  })
}

test("every *.js and *.mjs module outside tests/ loads under Node", async () => {
  const found = modules(root)
  assert.ok(found.length > 0, "found no logic modules")
  for (const file of found) {
    // import() loads an ECMAScript module on any Node tests/run accepts;
    // require() of one needs Node 22.12.
    const loaded = file.endsWith(".mjs") ? await import(pathToFileURL(file).href) : require(file)
    assert.equal(typeof loaded, "object", path.relative(root, file))
  }
})
