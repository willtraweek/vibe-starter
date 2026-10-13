// Loads every logic module outside tests/, so none can hide from the coverage
// gate: Node reports only files that were loaded.
const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")

const root = path.join(__dirname, "..", "..")

function modules(dir) {
  return fs.readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
    const file = path.join(dir, entry.name)
    if (!entry.isDirectory()) return entry.name.endsWith(".js") ? [file] : []
    const skip = entry.name.startsWith(".") || entry.name === "node_modules" || file === path.join(root, "tests")
    return skip ? [] : modules(file)
  })
}

test("every *.js module outside tests/ loads under Node", () => {
  const found = modules(root)
  assert.ok(found.length > 0, "found no logic modules")
  for (const file of found) assert.equal(typeof require(file), "object", path.relative(root, file))
})
