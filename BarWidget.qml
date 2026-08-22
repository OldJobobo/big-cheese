import QtQuick
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "jobo.big-cheese"

  readonly property var cheeseService:
    bar && bar.shell ? bar.shell.serviceFor(root.moduleName) : null
  readonly property bool available: cheeseService !== null
  readonly property bool serviceEnabled: available && cheeseService.enabled
  readonly property bool pulseActive: available && cheeseService.pulseActive
  readonly property string tooltipText: {
    if (!available) return "Big Cheese is loading"
    if (!serviceEnabled) return "Big Cheese is disabled · Right-click to enable"
    if (cheeseService.lastError !== "")
      return "Big Cheese · " + cheeseService.lastError
    if (!cheeseService.pulseReady) return "Big Cheese is preparing the cursor"
    return pulseActive
      ? "Big Cheese is locating the pointer"
      : "Big Cheese · Click to locate · Right-click to disable"
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    iconComponent: Component {
      Text {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: 1
        text: "\uf7ef"
        color: button.active && button.useActiveColor
          ? button.activeColor : button.foreground
        font.family: "Font Awesome 7 Free Solid"
        font.pixelSize: Math.max(1, Style.bar.iconFont - 1)
        renderType: Text.NativeRendering
      }
    }
    slotSize: Style.bar.statusSlot
    tooltipText: root.tooltipText
    active: root.pulseActive
    useActiveColor: true
    enabled: root.available
    opacity: root.serviceEnabled ? 1 : 0.42
    scale: root.pulseActive ? 1.16 : 1

    Behavior on opacity {
      NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
    }

    Behavior on scale {
      NumberAnimation { duration: 140; easing.type: Easing.OutBack }
    }

    onPressed: function(mouseButton) {
      if (!root.available) return
      if (mouseButton === Qt.RightButton) root.cheeseService.toggleEnabled()
      else if (mouseButton === Qt.LeftButton) root.cheeseService.requestPulse(1)
    }
  }
}
