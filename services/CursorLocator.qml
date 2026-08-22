import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "CursorLocatorModel.js" as CursorLocatorModel

Item {
  id: root

  required property var cursorTracker
  required property var cursorPulse
  property bool enabled: true
  property bool easterEggEnabled: false
  property color pointerFill: "#111318"
  property color pointerStroke: "#f8fafc"
  property bool paletteDetected: false
  property string paletteTheme: ""
  property string paletteRequestedTheme: ""

  readonly property string paletteHelperPath: helperPathFromUrl(
    Qt.resolvedUrl("../scripts/cursor-palette.py"))
  readonly property bool active: enabled && cursorPulse
    && cursorPulse.active && cursorPulse.overlayReady
  readonly property real pointerSize: cursorPulse
    ? Math.max(48, Number(cursorPulse.activePeakSize) || 48) : 48

  width: 0
  height: 0
  visible: false

  function helperPathFromUrl(url) {
    var value = String(url || "")
    if (value.indexOf("file://") !== 0) return ""
    try {
      var path = decodeURIComponent(value.substring(7))
      return path.indexOf("/") === 0 ? path : ""
    } catch (error) {
      return ""
    }
  }

  function refreshPalette() {
    if (!cursorPulse || paletteProcess.running || paletteHelperPath === "") return
    var theme = String(cursorPulse.baselineTheme || "default")
    paletteRequestedTheme = theme
    paletteProcess.command = [paletteHelperPath, theme, String(Math.round(pointerSize))]
    paletteProcess.running = true
  }

  Component.onCompleted: refreshPalette()

  Connections {
    target: root.cursorPulse
    function onBaselineThemeChanged() { root.refreshPalette() }
  }

  Process {
    id: paletteProcess
    stdout: StdioCollector { id: paletteOutput; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        if (root.cursorPulse
            && String(root.cursorPulse.baselineTheme || "default")
              !== root.paletteRequestedTheme)
          Qt.callLater(root.refreshPalette)
        return
      }
      try {
        var payload = JSON.parse(String(paletteOutput.text || "{}"))
        var fill = String(payload.fill || "")
        var stroke = String(payload.stroke || "")
        if (!/^#[0-9a-fA-F]{6}$/.test(fill)
            || !/^#[0-9a-fA-F]{6}$/.test(stroke)) return
        root.pointerFill = fill
        root.pointerStroke = stroke
        root.paletteDetected = payload.detected === true
        root.paletteTheme = String(payload.theme || root.paletteTheme)
      } catch (error) {
        root.paletteDetected = false
      }
      if (root.cursorPulse
          && String(root.cursorPulse.baselineTheme || "default")
            !== root.paletteRequestedTheme)
        Qt.callLater(root.refreshPalette)
    }
  }

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: locatorSurface

      required property var modelData
      readonly property var localPosition: CursorLocatorModel.localPosition(
        root.cursorTracker ? root.cursorTracker.cursorX : -1,
        root.cursorTracker ? root.cursorTracker.cursorY : -1,
        Number(modelData && modelData.x),
        Number(modelData && modelData.y))
      readonly property bool cursorInside: root.cursorTracker
        && root.cursorTracker.hasSample
        && CursorLocatorModel.contains(localPosition.x, localPosition.y, width, height)
      readonly property var pointerGeometry: CursorLocatorModel.pointerGeometry(
        localPosition.x, localPosition.y, root.pointerSize)

      screen: modelData
      // Keep each transparent surface mapped while the service is enabled so a
      // shake never waits for a layer-shell window to be created.
      visible: root.enabled
      color: "transparent"
      updatesEnabled: true
      WlrLayershell.namespace: "jobo-big-cheese-locator"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      exclusionMode: ExclusionMode.Ignore
      mask: Region {}

      anchors {
        top: true
        bottom: true
        left: true
        right: true
      }

      Item {
        id: pointer

        x: locatorSurface.pointerGeometry.x
        y: locatorSurface.pointerGeometry.y
        width: locatorSurface.pointerGeometry.width
        height: locatorSurface.pointerGeometry.height
        visible: root.active && locatorSurface.cursorInside
          && !root.easterEggEnabled

        Shape {
          id: arrowShape

          anchors.fill: parent
          antialiasing: true
          preferredRendererType: Shape.CurveRenderer

          ShapePath {
            strokeColor: root.pointerStroke
            fillColor: root.pointerFill
            strokeWidth: arrowShape.height * 4 / 64
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin

            startX: arrowShape.width * 3 / 46
            startY: arrowShape.height * 2 / 64
            PathLine {
              x: arrowShape.width * 3 / 46
              y: arrowShape.height * 48 / 64
            }
            PathLine {
              x: arrowShape.width * 14 / 46
              y: arrowShape.height * 38 / 64
            }
            PathLine {
              x: arrowShape.width * 23 / 46
              y: arrowShape.height * 61 / 64
            }
            PathLine {
              x: arrowShape.width * 32 / 46
              y: arrowShape.height * 57 / 64
            }
            PathLine {
              x: arrowShape.width * 23 / 46
              y: arrowShape.height * 35 / 64
            }
            PathLine {
              x: arrowShape.width * 41 / 46
              y: arrowShape.height * 35 / 64
            }
            PathLine {
              x: arrowShape.width * 3 / 46
              y: arrowShape.height * 2 / 64
            }
          }
        }
      }

      Item {
        id: cheesePointer

        readonly property real cheeseSize: root.pointerSize * 2

        x: locatorSurface.localPosition.x - cheeseSize * 0.41
        y: locatorSurface.localPosition.y - cheeseSize * 0.05
        width: cheeseSize
        height: cheeseSize
        visible: root.active && locatorSurface.cursorInside
          && root.easterEggEnabled

        Behavior on x {
          enabled: cheesePointer.visible
          NumberAnimation { duration: 50; easing.type: Easing.Linear }
        }

        Behavior on y {
          enabled: cheesePointer.visible
          NumberAnimation { duration: 50; easing.type: Easing.Linear }
        }

        Image {
          anchors.fill: parent
          source: Qt.resolvedUrl("../assets/the-big-cheese.png")
          sourceSize.width: 256
          sourceSize.height: 256
          fillMode: Image.PreserveAspectFit
          smooth: true
          mipmap: true
          antialiasing: true
          rotation: 80
          transformOrigin: Item.Center
        }
      }
    }
  }
}
