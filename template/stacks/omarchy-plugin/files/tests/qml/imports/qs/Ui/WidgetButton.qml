import QtQuick

// Stand-in for Omarchy's qs.Ui WidgetButton ($OMARCHY_PATH/shell/Ui/WidgetButton.qml):
// the bar sets its look; tests press it through triggerPress(), as its own
// MouseArea does.
Item {
  property var bar: null
  property string text: ""
  property string tooltipText: ""

  signal pressed(int button)

  function triggerPress(button) {
    pressed(button)
  }
}
