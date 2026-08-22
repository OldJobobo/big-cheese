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
  property bool fullColorCheese: false
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
      : fullColorCheese
        ? "Big Cheese · Click to open · Double-click for mono"
        : "Big Cheese · Click to open · Double-click for color"
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

  function handleClick(mouseButton) {
    if (!available) return
    if (mouseButton === Qt.RightButton) cheeseService.toggleEnabled()
    else if (mouseButton === Qt.LeftButton) singleClickTimer.restart()
  }

  function handleDoubleClick(mouseButton) {
    if (!available || mouseButton !== Qt.LeftButton) return
    singleClickTimer.stop()
    fullColorCheese = !fullColorCheese
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()
  onCheeseServiceChanged: injectPanel()

  Timer {
    id: singleClickTimer
    interval: Qt.styleHints.mouseDoubleClickInterval
    repeat: false
    onTriggered: root.togglePanel()
  }

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
    text: root.fullColorCheese ? "" : "\uf7ef"
    fontFamily: "Font Awesome 7 Free Solid"
    fontSize: Math.max(1, Style.bar.iconFont - 1)
    iconComponent: root.fullColorCheese ? colorCheese : null
    slotSize: Style.bar.statusSlot
    tooltipText: root.tooltipText
    active: root.pulseActive
    useActiveColor: true
    interactive: false
    opacity: root.serviceEnabled ? 1 : 0.42
    scale: root.pulseActive ? 1.16 : 1

    Behavior on opacity {
      NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
    }

    Behavior on scale {
      NumberAnimation { duration: 140; easing.type: Easing.OutBack }
    }
  }

  Component {
    id: colorCheese

    Image {
      anchors.fill: parent
      source: Qt.resolvedUrl("assets/cheese-emoji.svg")
      sourceSize.width: 64
      sourceSize.height: 64
      fillMode: Image.PreserveAspectFit
      smooth: true
      mipmap: true
    }
  }

  MouseArea {
    anchors.fill: button
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    enabled: root.available
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onEntered: if (root.bar) root.bar.showTooltip(button, root.tooltipText)
    onExited: if (root.bar) root.bar.hideTooltip(button)
    onClicked: function(mouse) { root.handleClick(mouse.button) }
    onDoubleClicked: function(mouse) { root.handleDoubleClick(mouse.button) }
  }
}
