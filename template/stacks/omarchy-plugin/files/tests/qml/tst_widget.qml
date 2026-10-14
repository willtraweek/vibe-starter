import QtQuick
import QtTest
import "../.." as Plugin

// The real Widget.qml (TESTING.md tier 3), against stand-ins for the qs.Ui
// components it uses (tests/qml/imports), offscreen: no shell, no compositor.
TestCase {
  name: "Widget"

  Component {
    id: widget
    Plugin.Widget {}
  }

  // The host bar, as much of it as the widget reads.
  Component {
    id: hostBar
    QtObject {
      property bool vertical: false
      property int barSize: 26
    }
  }

  function button(item) {
    return item.children[0]
  }

  function onBar(vertical) {
    var bar = createTemporaryObject(hostBar, null, { vertical: vertical, barSize: vertical ? 28 : 26 })
    return createTemporaryObject(widget, null, { bar: bar })
  }

  function test_click_counts_and_right_click_resets() {
    var item = createTemporaryObject(widget, null)
    verify(item !== null, "Widget.qml loads against the qs.Ui stand-ins")
    compare(button(item).text, "Pressed 0")
    button(item).triggerPress(Qt.LeftButton)
    button(item).triggerPress(Qt.LeftButton)
    compare(item.count, 2)
    compare(button(item).text, "Pressed 2")
    compare(button(item).tooltipText, "Pressed 2 times")
    button(item).triggerPress(Qt.RightButton)
    compare(item.count, 0)
  }

  function test_a_horizontal_bar_shows_the_label_and_the_count() {
    var item = onBar(false)
    compare(item.vertical, false)
    compare(button(item).text, "Pressed 0")
  }

  function test_a_vertical_bar_shows_only_the_count() {
    // Regression test. A vertical bar fixes the button's width to its barSize,
    // and "Pressed 0" overflowed it.
    var item = onBar(true)
    compare(item.vertical, true)
    compare(button(item).text, "0")
    button(item).triggerPress(Qt.LeftButton)
    compare(button(item).text, "1")
    compare(button(item).tooltipText, "Pressed once")
  }

  function test_the_label_comes_from_the_widget_settings() {
    var item = createTemporaryObject(widget, null, { settings: { label: "Taps" } })
    compare(button(item).text, "Taps 0")
  }

  function test_the_widget_reports_its_module_name() {
    var item = createTemporaryObject(widget, null)
    compare(item.moduleName, "{{PACKAGE_NAME}}")
  }
}
