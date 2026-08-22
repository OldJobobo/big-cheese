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
  readonly property color foreground: bar ? bar.barForeground : Color.foreground
  readonly property color accent: bar ? bar.urgent : Color.accent
  readonly property color dim: Qt.darker(foreground, 1.45)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property string version: available ? String(cheeseService.pluginVersion) : "0.1.0"

  function switchPanel(direction) {
    if (bar && typeof bar.switchPanelFrom === "function")
      return bar.switchPanelFrom(barIdentity, direction)
    return false
  }

  function choose(index) {
    cursorActive = true
    selectedIndex = Math.max(0, Math.min(1, index))
  }

  function moveCursor(dy) {
    if (!cursorActive) {
      choose(0)
      return
    }
    if (dy !== 0) choose(selectedIndex + dy)
  }

  function activateCursor() {
    if (!cursorActive) return
    if (selectedIndex === 0) toggleDetection()
    else openDonation()
  }

  function toggleDetection() {
    if (available) cheeseService.toggleEnabled()
  }

  function openDonation() {
    close()
    Qt.openUrlExternally("https://ko-fi.com/oldjobobo")
  }

  onOpenedChanged: if (opened) {
    cursorActive = false
    selectedIndex = 0
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
    contentHeight: panel.fittedContentHeight(content.implicitHeight, Style.space(440))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) { root.moveCursor(dy) }
      onActivateRequested: root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) {
        if (text === "e" || text === "E") root.toggleDetection()
        else if (text === "d" || text === "D") root.openDonation()
      }

      Column {
        id: content
        width: parent.width
        spacing: Style.space(14)

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
          title: "Give some Cheddar"
          detail: "ko-fi.com/oldjobobo"
          rowIndex: 1
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
