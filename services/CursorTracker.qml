import QtQuick
import Quickshell.Io

Item {
  id: root

  property bool active: false
  property int pollIntervalMs: 120
  property real cursorX: -1
  property real cursorY: -1
  property bool hasSample: false
  property int sampleCount: 0
  property int failureCount: 0
  property string lastError: ""

  readonly property bool running: cursorProcess.running

  signal sampled(real x, real y, double sampledAt)

  width: 0
  height: 0
  visible: false

  function poll() {
    if (!active || cursorProcess.running) return
    cursorProcess.output = ""
    cursorProcess.command = ["hyprctl", "cursorpos", "-j"]
    cursorProcess.running = true
  }

  function invalidate() {
    hasSample = false
    cursorX = -1
    cursorY = -1
  }

  function applyPayload(raw) {
    try {
      var payload = JSON.parse(raw || "{}")
      var nextX = Number(payload.x)
      var nextY = Number(payload.y)
      if (!isFinite(nextX) || !isFinite(nextY))
        throw new Error("cursor payload has no coordinates")

      cursorX = nextX
      cursorY = nextY
      hasSample = true
      sampleCount += 1
      lastError = ""
      sampled(nextX, nextY, Date.now())
    } catch (error) {
      failureCount += 1
      lastError = String(error)
      invalidate()
    }
  }

  function status() {
    return {
      active: active,
      running: running,
      hasSample: hasSample,
      sampleCount: sampleCount,
      failureCount: failureCount,
      x: cursorX,
      y: cursorY,
      error: lastError
    }
  }

  onActiveChanged: {
    if (active) poll()
    else invalidate()
  }

  Timer {
    interval: root.pollIntervalMs
    repeat: true
    running: root.active
    onTriggered: root.poll()
  }

  Process {
    id: cursorProcess

    property string output: ""

    stdout: SplitParser {
      onRead: function(data) {
        cursorProcess.output += data
      }
    }

    onExited: function(exitCode) {
      if (exitCode === 0 && root.active) root.applyPayload(cursorProcess.output)
      else if (exitCode !== 0) {
        root.failureCount += 1
        root.lastError = "hyprctl cursorpos exited with status " + exitCode
        root.invalidate()
      } else {
        root.invalidate()
      }
    }
  }
}
