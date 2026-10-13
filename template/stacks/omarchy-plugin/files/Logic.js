// Pure logic for the widget, with no Qt: QML imports this file with
// `import "Logic.js" as Logic`, and the unit tests load it in Node with
// require(), where coverage is held at 100% (tests/run).

// The count stops here, so the bar button stays narrow.
var MAX_COUNT = 999

function next(count, action) {
  if (action === "reset") return 0
  if (action === "count") return Math.min(count + 1, MAX_COUNT)
  return count
}

function barText(label, count) {
  return label + " " + count
}

function tooltip(count) {
  if (count === 0) return "Not pressed yet"
  if (count === 1) return "Pressed once"
  return "Pressed " + count + " times"
}

if (typeof module !== "undefined") {
  module.exports = { MAX_COUNT: MAX_COUNT, next: next, barText: barText, tooltip: tooltip }
}
