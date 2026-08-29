import QtQuick
import qs.Ui

// Bar icon: left click opens Search mode, right click opens Bookmarks mode.
BarWidget {
  id: root
  moduleName: "weblauncher"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    horizontalMargin: 7.5
    onPressed: function(mouseButton) {
      if (!root.bar) return
      if (mouseButton === Qt.RightButton)
        root.bar.run("omarchy-shell shell summon weblauncher '{\"mode\":\"bookmarks\"}'")
      else
        root.bar.run("omarchy-shell shell summon weblauncher '{\"mode\":\"search\"}'")
    }
  }
}
