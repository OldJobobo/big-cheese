import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui

Panel {
  id: root

  moduleName: "jobo.big-cheese"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var cheeseService: null
  property bool cursorActive: false
  property int selectedIndex: 0

  readonly property var barIdentity: hostWidget || root
  readonly property bool available: cheeseService !== null
  readonly property bool serviceEnabled: available && cheeseService.enabled
  readonly property string mouseTrail: available
    ? String(cheeseService.mouseTrail || "reveal") : "reveal"
  readonly property string mouseTrailDetail: mouseTrail === "off"
    ? "No tail"
    : mouseTrail === "always" ? "Follows every move" : "Only when enlarged"
  readonly property bool growEnabled: available
    && cheeseService.growEnabled === true
  readonly property bool nativeThemeCursorActive: available
    && cheeseService.nativeThemeCursorActive === true
  readonly property bool nativeThemeCursorBusy: available
    && cheeseService.nativeThemeCursorBusy === true
  readonly property string nativeThemeCursorDetail: nativeThemeCursorBusy
    ? "Updating cursor…"
    : nativeThemeCursorActive ? "Normal + enlarged" : "Uses cursor theme"
  readonly property color foreground: bar ? bar.barForeground : Color.foreground
  readonly property color accent: bar ? bar.urgent : Color.accent
  readonly property color dim: Qt.darker(foreground, 1.45)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property string version: available ? String(cheeseService.pluginVersion) : "0.1.1"
  readonly property string configPath: available
    ? String(cheeseService.configPath || "") : ""
  readonly property string configDisplayPath: compactPath(configPath)

  function compactPath(path) {
    var homePath = String(path || "").match(/^\/home\/[^/]+(\/.*)$/)
    return homePath ? "~" + homePath[1] : String(path || "")
  }

  function switchPanel(direction) {
    if (bar && typeof bar.switchPanelFrom === "function")
      return bar.switchPanelFrom(barIdentity, direction)
    return false
  }

  function choose(index) {
    cursorActive = true
    selectedIndex = Math.max(0, Math.min(5, index))
  }

  function moveCursor(dx, dy) {
    if (!cursorActive) {
      choose(0)
      return
    }
    if (selectedIndex === 2 && dx !== 0) {
      cycleTrail(dx)
      return
    }
    if (dy !== 0) choose(selectedIndex + dy)
  }

  function activateCursor() {
    if (!cursorActive) return
    if (selectedIndex === 0) toggleDetection()
    else if (selectedIndex === 1) toggleGrow()
    else if (selectedIndex === 2) cycleTrail(1)
    else if (selectedIndex === 3) toggleNativeThemeCursor()
    else if (selectedIndex === 4) openDonation()
    else openConfig()
  }

  function toggleDetection() {
    if (available) cheeseService.toggleEnabled()
  }

  function toggleGrow() {
    if (available) cheeseService.toggleGrowEnabled()
  }

  function setTrailMode(mode) {
    if (available) cheeseService.setMouseTrail(mode)
  }

  function cycleTrail(direction) {
    var modes = ["off", "reveal", "always"]
    var index = modes.indexOf(mouseTrail)
    var step = direction < 0 ? -1 : 1
    setTrailMode(modes[(index + step + modes.length) % modes.length])
  }

  function toggleNativeThemeCursor() {
    if (available) cheeseService.toggleNativeThemeCursor()
  }

  function openDonation() {
    close()
    Qt.openUrlExternally("https://ko-fi.com/oldjobobo")
  }

  function openConfig() {
    if (available && cheeseService.openConfig()) close()
  }

  onOpenedChanged: if (opened) {
    cursorActive = false
    selectedIndex = 0
    if (available) cheeseService.probeNativeThemeCursor()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(340))
    contentHeight: panel.fittedContentHeight(content.implicitHeight, Style.space(520))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) { root.moveCursor(dx, dy) }
      onActivateRequested: root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) {
        if (text === "e" || text === "E") root.toggleDetection()
        else if (text === "g" || text === "G") root.toggleGrow()
        else if (text === "t" || text === "T") root.cycleTrail(1)
        else if (text === "c" || text === "C") root.toggleNativeThemeCursor()
        else if (text === "d" || text === "D") root.openDonation()
        else if (text === "o" || text === "O") root.openConfig()
      }

      Column {
        id: content
        width: parent.width
        spacing: Style.space(10)

        PanelHero {
          width: parent.width
          title: "Big Cheese"
          meta: "Shake to locate"
          detail: "v" + root.version
          foreground: root.foreground
          fontFamily: root.fontFamily
          iconSize: Style.space(62)
          iconComponent: Component {
            Image {
              width: Style.space(62)
              height: Style.space(62)
              source: Qt.resolvedUrl("assets/big-cheese-icon.png")
              sourceSize.width: 124
              sourceSize.height: 124
              fillMode: Image.PreserveAspectFit
              smooth: true
              mipmap: true
            }
          }
        }

        Text {
          width: parent.width
          text: "No one but you can move your cheese!"
          color: root.foreground
          opacity: 0.82
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
          wrapMode: Text.WordWrap
          horizontalAlignment: Text.AlignHCenter
        }

        Text {
          id: configLink

          width: parent.width
          text: root.configDisplayPath === ""
            ? "Config unavailable"
            : root.configDisplayPath
          color: root.configPath === "" ? root.dim : root.accent
          opacity: root.configPath === "" ? 0.5 : 0.82
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.underline: configMouse.containsMouse
            || (root.cursorActive && root.selectedIndex === 5)
          elide: Text.ElideMiddle
          horizontalAlignment: Text.AlignHCenter

          MouseArea {
            id: configMouse
            anchors.fill: parent
            enabled: root.configPath !== ""
            hoverEnabled: true
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onEntered: root.choose(5)
            onClicked: root.openConfig()
          }
        }

        PanelSeparator {
          width: parent.width
          foreground: root.foreground
        }

        ControlRow {
          title: "Shake to locate"
          detail: root.serviceEnabled
            ? "Ready when the cursor goes missing"
            : "Taking a little cheese break"
          rowIndex: 0
          onActivated: root.toggleDetection()

          ToggleSwitch {
            checked: root.serviceEnabled
            interactive: false
            cursorRing: false
            foreground: root.foreground
            accent: root.accent
          }
        }

        ControlRow {
          title: "Grow"
          detail: root.growEnabled
            ? "Shake longer, grow larger"
            : "Fixed enlarged size"
          rowIndex: 1
          onActivated: root.toggleGrow()

          ToggleSwitch {
            checked: root.growEnabled
            interactive: false
            cursorRing: false
            foreground: root.foreground
            accent: root.accent
          }
        }

        ControlRow {
          title: "Mouse trail"
          detail: root.mouseTrailDetail
          rowIndex: 2
          onActivated: root.cycleTrail(1)

          TrailModeSelector {
            mode: root.mouseTrail
            foreground: root.foreground
            accent: root.accent
            fontFamily: root.fontFamily
            onModeSelected: function(mode) { root.setTrailMode(mode) }
          }
        }

        ControlRow {
          title: "Theme cursor colors"
          detail: root.nativeThemeCursorDetail
          rowIndex: 3
          enabled: root.available && !root.nativeThemeCursorBusy
          onActivated: root.toggleNativeThemeCursor()

          ToggleSwitch {
            checked: root.nativeThemeCursorActive
            interactive: false
            cursorRing: false
            foreground: root.foreground
            accent: root.accent
          }
        }

        ControlRow {
          title: "Give some Cheddar"
          detail: "ko-fi.com/oldjobobo"
          rowIndex: 4
          onActivated: root.openDonation()

          Text {
            text: "\uf004"
            color: root.accent
            font.family: "Font Awesome 7 Free Solid"
            font.pixelSize: Style.font.icon
            Layout.rightMargin: Style.space(7)
            Layout.alignment: Qt.AlignVCenter
          }
        }
      }
    }
  }

  component TrailModeSelector: Row {
    id: selector

    required property string mode
    required property color foreground
    required property color accent
    required property string fontFamily
    signal modeSelected(string mode)

    spacing: Style.space(3)
    Layout.preferredWidth: implicitWidth
    Layout.preferredHeight: Style.space(28)
    Layout.alignment: Qt.AlignVCenter

    Repeater {
      model: [
        { value: "off", label: "Off" },
        { value: "reveal", label: "Reveal" },
        { value: "always", label: "Always" }
      ]

      delegate: Rectangle {
        id: segment

        required property var modelData
        readonly property bool selected: selector.mode === modelData.value

        width: Style.space(modelData.value === "reveal" ? 54 : 48)
        height: Style.space(28)
        radius: Style.cornerRadius
        color: selected
          ? Style.selectedFillFor(selector.foreground, selector.accent)
          : "transparent"
        border.width: selected ? 1 : 0
        border.color: selector.accent

        Behavior on color { ColorAnimation { duration: 60 } }

        Text {
          anchors.centerIn: parent
          text: segment.modelData.label
          color: segment.selected ? selector.accent : root.dim
          font.family: selector.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: segment.selected
        }

        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onEntered: root.choose(1)
          onClicked: selector.modeSelected(segment.modelData.value)
        }
      }
    }
  }

  component ControlRow: CursorSurface {
    id: control

    required property string title
    required property string detail
    required property int rowIndex
    default property alias trailing: trailingSlot.data
    signal activated()

    width: parent ? parent.width : implicitWidth
    implicitHeight: row.implicitHeight + Style.space(18)
    hasCursor: root.cursorActive && root.selectedIndex === rowIndex
    foreground: root.foreground
    accent: root.accent
    opacity: enabled ? 1 : 0.42

    MouseArea {
      anchors.fill: parent
      enabled: control.enabled
      hoverEnabled: true
      cursorShape: control.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
      onEntered: root.choose(control.rowIndex)
      onClicked: control.activated()
    }

    RowLayout {
      id: row
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(7)
      spacing: Style.space(12)

      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.space(2)

        Text {
          Layout.fillWidth: true
          text: control.title
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.bold: true
          elide: Text.ElideRight
        }

        Text {
          Layout.fillWidth: true
          text: control.detail
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      Item {
        id: trailingSlot
        Layout.preferredWidth: childrenRect.width
        Layout.preferredHeight: Math.max(childrenRect.height, Style.space(26))
        Layout.alignment: Qt.AlignVCenter
      }
    }
  }
}
