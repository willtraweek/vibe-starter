// Pure-logic tests (TESTING.md tier 1): every rule in Logic.js.
const test = require("node:test")
const assert = require("node:assert/strict")
const Logic = require("../../Logic.js")

test("a click counts and a right-click resets", () => {
  assert.equal(Logic.next(0, "count"), 1)
  assert.equal(Logic.next(41, "count"), 42)
  assert.equal(Logic.next(42, "reset"), 0)
})

test("the count stops at MAX_COUNT instead of growing the button", () => {
  assert.equal(Logic.next(Logic.MAX_COUNT, "count"), Logic.MAX_COUNT)
})

test("an unknown action leaves the count alone", () => {
  assert.equal(Logic.next(7, "wheel"), 7)
})

test("on a horizontal bar the text is the label and the count", () => {
  assert.equal(Logic.barText("Pressed", 3, false), "Pressed 3")
})

test("on a vertical bar the text is only the count, which fits its width", () => {
  // Regression test. A vertical bar fixes the button's width to the bar's
  // (barSize, about 28px), and "Pressed 3" overflowed it.
  assert.equal(Logic.barText("Pressed", 3, true), "3")
  assert.equal(Logic.barText("Pressed", Logic.MAX_COUNT, true), "999")
})

test("the tooltip says how many presses", () => {
  assert.equal(Logic.tooltip(0), "Not pressed yet")
  assert.equal(Logic.tooltip(1), "Pressed once")
  assert.equal(Logic.tooltip(2), "Pressed 2 times")
})
