import QtQuick
import qs.Ui
import "Logic.js" as Logic

// The bar widget: a button that counts presses. Click counts, right-click
// resets. The bar's own button (qs.Ui) supplies colour, font and size, so the
// widget follows `omarchy theme set`; the label is this widget's setting.
BarWidget {
  id: root
  moduleName: "{{PACKAGE_NAME}}"

  property int count: 0

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: Logic.barText(root.setting("label", "Pressed"), root.count)
    tooltipText: Logic.tooltip(root.count)
    onPressed: function(mouseButton) {
      root.count = Logic.next(root.count, mouseButton === Qt.RightButton ? "reset" : "count")
    }
  }
}
