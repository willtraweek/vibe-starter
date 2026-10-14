import QtQuick

// Stand-in for Omarchy's qs.Ui BarWidget ($OMARCHY_PATH/shell/Ui/BarWidget.qml):
// only the properties and function the widget uses. Keep it in step with the
// real one when you use more of it.
Item {
  property QtObject bar: null
  property string moduleName: ""
  property var settings: ({})

  // Bar geometry, lifted off the host bar as the real one does; its fallback
  // barSize is Style.bar.sizeHorizontal, 26 unless the theme changes it.
  readonly property bool vertical: bar ? bar.vertical : false
  readonly property int barSize: bar ? bar.barSize : 26

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }
}
