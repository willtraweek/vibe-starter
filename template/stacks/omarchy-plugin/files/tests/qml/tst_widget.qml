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

  function button(item) {
    return item.children[0]
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

  function test_the_label_comes_from_the_widget_settings() {
    var item = createTemporaryObject(widget, null, { settings: { label: "Taps" } })
    compare(button(item).text, "Taps 0")
  }

  function test_the_widget_reports_its_module_name() {
    var item = createTemporaryObject(widget, null)
    compare(item.moduleName, "{{PACKAGE_NAME}}")
  }
}
