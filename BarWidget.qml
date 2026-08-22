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
  readonly property bool opened: panelLoader.item
    ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item
    ? panelLoader.item.popoutSwitchClosing === true : false
  readonly property string tooltipText: {
    if (opened) return ""
    if (!available) return "Big Cheese is loading"
    if (!serviceEnabled) return "Big Cheese is disabled · Right-click to enable"
    if (cheeseService.lastError !== "")
      return "Big Cheese · " + cheeseService.lastError
    if (!cheeseService.pulseReady) return "Big Cheese is preparing the cursor"
    return pulseActive
      ? "Big Cheese is locating the pointer"
      : "Big Cheese · Click to open"
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
    if ("cheeseService" in target) target.cheeseService = root.cheeseService
  }

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function togglePanel() {
    if (bar) bar.hideTooltip(button)
    if (panelLoader.item) panelLoader.item.toggle()
  }

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  function handlePress(mouseButton) {
    if (!available) return
    if (mouseButton === Qt.RightButton) cheeseService.toggleEnabled()
    else if (mouseButton === Qt.LeftButton) togglePanel()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()
  onCheeseServiceChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "\uf7ef"
    fontFamily: "Font Awesome 7 Free Solid"
    fontSize: Math.max(1, Style.bar.iconFont - 1)
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

    onPressed: function(mouseButton) { root.handlePress(mouseButton) }
  }
}
