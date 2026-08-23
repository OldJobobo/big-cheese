import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import "CursorLocatorModel.js" as CursorLocatorModel

Item {
  id: root

  required property var cursorTracker
  required property var cursorPulse
  property bool enabled: true
  property bool easterEggEnabled: false
  property string trailMode: "reveal"
  property bool useOmarchyPalette: false
  property string cursorTheme: "default"
  property color cursorThemeFill: "#111318"
  property color cursorThemeStroke: "#f8fafc"
  property bool cursorPaletteDetected: false
  property string cursorPaletteTheme: "default"
  property string paletteRequestedTheme: ""
  readonly property color pointerFill: useOmarchyPalette
    ? Color.accent : cursorThemeFill
  readonly property color pointerStroke: useOmarchyPalette
    ? Color.background : cursorThemeStroke
  readonly property bool paletteDetected: useOmarchyPalette
    ? true : cursorPaletteDetected
  readonly property string paletteTheme: useOmarchyPalette
    ? "omarchy" : cursorPaletteTheme
  readonly property string paletteHelperPath: helperPathFromUrl(
    Qt.resolvedUrl("../scripts/cursor-palette.py"))

  readonly property bool active: enabled && cursorPulse
    && cursorPulse.active && cursorPulse.overlayReady
  readonly property real pointerSize: cursorPulse
    ? Math.max(48, Number(cursorPulse.activePeakSize) || 48) : 48
  readonly property color trailGlowColor: easterEggEnabled
    ? "#f7b928" : Color.accent
  readonly property color trailCoreColor: easterEggEnabled
    ? "#fff1a8" : Color.foreground

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
    if (paletteProcess.running || paletteHelperPath === "") return false
    paletteRequestedTheme = String(cursorTheme || "default")
    paletteProcess.command = [
      paletteHelperPath,
      paletteRequestedTheme,
      String(Math.round(pointerSize))
    ]
    paletteProcess.running = true
    return true
  }

  onCursorThemeChanged: refreshPalette()
  Component.onCompleted: refreshPalette()

  Process {
    id: paletteProcess
    stdout: StdioCollector { id: paletteOutput; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) return
      try {
        var payload = JSON.parse(String(paletteOutput.text || "{}"))
        var fill = String(payload.fill || "")
        var stroke = String(payload.stroke || "")
        if (!/^#[0-9a-fA-F]{6}$/.test(fill)
            || !/^#[0-9a-fA-F]{6}$/.test(stroke)) return
        root.cursorThemeFill = fill
        root.cursorThemeStroke = stroke
        root.cursorPaletteDetected = payload.detected === true
        root.cursorPaletteTheme = String(payload.theme || "default")
      } catch (error) {
        root.cursorPaletteDetected = false
      }
      if (String(root.cursorTheme || "default")
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
      readonly property var localTrailPosition: CursorLocatorModel.localPosition(
        root.cursorTracker ? root.cursorTracker.rawCursorX : -1,
        root.cursorTracker ? root.cursorTracker.rawCursorY : -1,
        Number(modelData && modelData.x),
        Number(modelData && modelData.y))
      readonly property bool trailCursorInside: root.cursorTracker
        && root.cursorTracker.hasRawSample
        && CursorLocatorModel.contains(
          localTrailPosition.x, localTrailPosition.y, width, height)
      readonly property bool trailRequested: root.trailMode === "always"
        || (root.trailMode === "reveal" && root.active)
      readonly property bool trailEmitting: root.enabled
        && trailRequested && trailCursorInside
      readonly property real trailAnchorSize: root.active
        ? root.pointerSize : Math.max(16,
          Number(root.cursorPulse ? root.cursorPulse.baselineSize : 24) || 24)
      readonly property real trailAnchorX: localTrailPosition.x
        + trailAnchorSize * (root.active && root.easterEggEnabled ? 0.18 : 0.32)
      readonly property real trailAnchorY: localTrailPosition.y
        + trailAnchorSize * (root.active && root.easterEggEnabled ? 0.9 : 0.58)
      readonly property real trailStartWidth: root.easterEggEnabled
        ? Math.max(90, trailAnchorSize * 1.25)
        : Math.max(40, trailAnchorSize * 0.9)
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

      Canvas {
        id: trailCanvas

        property var points: []
        property int pointCount: 0
        property var paintedBounds: Qt.rect(0, 0, 0, 0)
        readonly property int lifetimeMs: root.easterEggEnabled ? 1200 : 950

        anchors.fill: parent
        antialiasing: true
        renderTarget: Canvas.Image
        renderStrategy: Canvas.Threaded

        function appendPoint(x, y, timestamp) {
          var last = points.length > 0 ? points[points.length - 1] : null
          var moved = last === null
            || Math.hypot(x - last.x, y - last.y) >= 0.75
          if (moved) points.push({ x: x, y: y, at: timestamp })
          prune(timestamp)
        }

        function prune(timestamp) {
          while (points.length > 0
              && timestamp - points[0].at > lifetimeMs)
            points.shift()
          pointCount = points.length
          schedulePaint()
        }

        function trailBounds() {
          if (points.length === 0) return Qt.rect(0, 0, 0, 0)
          var minX = points[0].x
          var maxX = minX
          var minY = points[0].y
          var maxY = minY
          for (var index = 1; index < points.length; index += 1) {
            minX = Math.min(minX, points[index].x)
            maxX = Math.max(maxX, points[index].x)
            minY = Math.min(minY, points[index].y)
            maxY = Math.max(maxY, points[index].y)
          }
          var margin = locatorSurface.trailStartWidth / 2 + 6
          return Qt.rect(minX - margin, minY - margin,
            maxX - minX + margin * 2, maxY - minY + margin * 2)
        }

        function unionBounds(first, second) {
          if (first.width <= 0 || first.height <= 0) return second
          if (second.width <= 0 || second.height <= 0) return first
          var left = Math.min(first.x, second.x)
          var top = Math.min(first.y, second.y)
          var right = Math.max(first.x + first.width, second.x + second.width)
          var bottom = Math.max(first.y + first.height, second.y + second.height)
          return Qt.rect(left, top, right - left, bottom - top)
        }

        function schedulePaint() {
          var nextBounds = trailBounds()
          var dirty = unionBounds(paintedBounds, nextBounds)
          paintedBounds = nextBounds
          if (dirty.width > 0 && dirty.height > 0) markDirty(dirty)
        }

        function clearTrail() {
          points = []
          pointCount = 0
          schedulePaint()
        }

        function ribbonEdge(index, first, last, timestamp, width) {
          var previous = points[Math.max(first, index - 1)]
          var current = points[index]
          var after = points[Math.min(last, index + 1)]
          var tangentX = after.x - previous.x
          var tangentY = after.y - previous.y
          var tangentLength = Math.max(0.001,
            Math.hypot(tangentX, tangentY))
          var life = Math.max(0,
            1 - (timestamp - current.at) / lifetimeMs)
          var taper = life * life * (3 - 2 * life)
          var radius = width * taper / 2
          var normalX = -tangentY / tangentLength
          var normalY = tangentX / tangentLength
          return {
            leftX: current.x + normalX * radius,
            leftY: current.y + normalY * radius,
            rightX: current.x - normalX * radius,
            rightY: current.y - normalY * radius
          }
        }

        function drawRibbonChunk(context, first, last, timestamp, width) {
          if (last - first < 1) return
          var edges = []
          for (var index = first; index <= last; index += 1)
            edges.push(ribbonEdge(index, first, last, timestamp, width))
          context.moveTo(edges[0].leftX, edges[0].leftY)
          for (var left = 1; left < edges.length - 1; left += 1) {
            var nextLeft = edges[left + 1]
            context.quadraticCurveTo(edges[left].leftX, edges[left].leftY,
              (edges[left].leftX + nextLeft.leftX) / 2,
              (edges[left].leftY + nextLeft.leftY) / 2)
          }
          var newest = edges[edges.length - 1]
          context.lineTo(newest.leftX, newest.leftY)
          context.lineTo(newest.rightX, newest.rightY)
          for (var right = edges.length - 2; right > 0; right -= 1) {
            var previousRight = edges[right - 1]
            context.quadraticCurveTo(edges[right].rightX, edges[right].rightY,
              (edges[right].rightX + previousRight.rightX) / 2,
              (edges[right].rightY + previousRight.rightY) / 2)
          }
          context.lineTo(edges[0].rightX, edges[0].rightY)
          context.closePath()
        }

        function drawLayer(context, timestamp, color, width, opacity) {
          if (points.length < 2) return
          context.fillStyle = String(color)
          context.globalAlpha = opacity
          context.beginPath()
          var chunkStart = 0
          for (var index = 1; index < points.length; index += 1) {
            var gap = Math.hypot(points[index].x - points[index - 1].x,
              points[index].y - points[index - 1].y) > 220
            if (!gap) continue
            drawRibbonChunk(context, chunkStart, index - 1, timestamp, width)
            chunkStart = index
          }
          drawRibbonChunk(context, chunkStart,
            points.length - 1, timestamp, width)
          context.fill()
          context.globalAlpha = 1
        }

        onPaint: function(region) {
          var context = getContext("2d")
          var now = Date.now()
          context.clearRect(region.x, region.y, region.width, region.height)
          drawLayer(context, now, root.trailGlowColor,
            locatorSurface.trailStartWidth, 0.08)
          drawLayer(context, now, root.trailGlowColor,
            locatorSurface.trailStartWidth * 0.68, 0.12)
          drawLayer(context, now, root.trailGlowColor,
            locatorSurface.trailStartWidth * 0.42, 0.2)
          drawLayer(context, now, root.trailCoreColor,
            locatorSurface.trailStartWidth * 0.14, 0.78)
        }
      }

      Item {
        id: trailHead

        x: locatorSurface.trailAnchorX - width / 2
        y: locatorSurface.trailAnchorY - height / 2
        width: 1
        height: 1

        Behavior on x {
          enabled: locatorSurface.trailEmitting
          NumberAnimation { duration: 50; easing.type: Easing.Linear }
        }

        Behavior on y {
          enabled: locatorSurface.trailEmitting
          NumberAnimation { duration: 50; easing.type: Easing.Linear }
        }
      }

      Timer {
        interval: 16
        repeat: true
        running: locatorSurface.trailEmitting || trailCanvas.pointCount > 0
        onTriggered: {
          var now = Date.now()
          if (locatorSurface.trailEmitting)
            trailCanvas.appendPoint(
              trailHead.x + trailHead.width / 2,
              trailHead.y + trailHead.height / 2,
              now)
          else
            trailCanvas.prune(now)
        }
      }

      Connections {
        target: root
        function onTrailModeChanged() {
          if (root.trailMode === "off") trailCanvas.clearTrail()
        }
      }

      Item {
        id: pointer

        x: locatorSurface.pointerGeometry.x
        y: locatorSurface.pointerGeometry.y
        width: locatorSurface.pointerGeometry.width
        height: locatorSurface.pointerGeometry.height
        visible: root.active && locatorSurface.cursorInside
          && !root.easterEggEnabled

        Behavior on x {
          enabled: pointer.visible
          NumberAnimation { duration: 50; easing.type: Easing.Linear }
        }

        Behavior on y {
          enabled: pointer.visible
          NumberAnimation { duration: 50; easing.type: Easing.Linear }
        }

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
