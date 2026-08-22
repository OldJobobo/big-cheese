import QtQuick
import Quickshell.Io

Item {
  id: root

  property bool active: false
  property bool armed: false
  property int idlePollIntervalMs: 110
  property int armedPollIntervalMs: 55
  property int failuresBeforeInvalidation: 2
  property real cursorX: -1
  property real cursorY: -1
  property bool hasSample: false
  property int sampleCount: 0
  property int launchCount: 0
  property int failureCount: 0
  property int consecutiveFailureCount: 0
  property double lastSampleAt: 0
  property int actualSampleIntervalMs: 0
  property int lastLatencyMs: 0
  property string lastError: ""
  property bool launchPending: false

  readonly property int effectivePollIntervalMs:
    armed ? armedPollIntervalMs : idlePollIntervalMs
  readonly property bool running: cursorProcess.running

  signal sampled(real x, real y, double sampledAt)
  signal samplingInvalidated()

  width: 0
  height: 0
  visible: false

  function poll() {
    if (!active || launchPending || cursorProcess.running) return false
    launchPending = true
    cursorProcess.output = ""
    cursorProcess.launchedAt = Date.now()
    cursorProcess.command = ["hyprctl", "cursorpos", "-j"]
    launchCount += 1
    cursorProcess.running = true
    return true
  }

  function invalidate() {
    hasSample = false
    cursorX = -1
    cursorY = -1
    lastSampleAt = 0
    actualSampleIntervalMs = 0
  }

  function recordFailure(message) {
    failureCount += 1
    consecutiveFailureCount += 1
    lastError = String(message)
    var invalidationThreshold = Math.max(1, failuresBeforeInvalidation)
    if (consecutiveFailureCount === invalidationThreshold) {
      invalidate()
      samplingInvalidated()
    }
  }

  function applyPayload(raw, sampledAt) {
    try {
      var payload = JSON.parse(String(raw || "{}"))
      if (typeof payload.x !== "number" || !isFinite(payload.x)
          || typeof payload.y !== "number" || !isFinite(payload.y))
        throw new Error("cursor payload has no finite numeric coordinates")
      if (typeof sampledAt !== "number" || !isFinite(sampledAt))
        throw new Error("cursor sample has no finite numeric timestamp")

      var nextX = payload.x
      var nextY = payload.y
      var now = sampledAt
      actualSampleIntervalMs = lastSampleAt > 0
        ? Math.max(0, Math.round(now - lastSampleAt)) : 0
      cursorX = nextX
      cursorY = nextY
      hasSample = true
      sampleCount += 1
      consecutiveFailureCount = 0
      lastSampleAt = now
      lastError = ""
      sampled(nextX, nextY, now)
      return true
    } catch (error) {
      recordFailure(error)
      return false
    }
  }

  function clearErrors() {
    consecutiveFailureCount = 0
    lastError = ""
  }

  function status() {
    return {
      active: active,
      armed: armed,
      running: running,
      launchPending: launchPending,
      hasSample: hasSample,
      sampleCount: sampleCount,
      launchCount: launchCount,
      failureCount: failureCount,
      consecutiveFailureCount: consecutiveFailureCount,
      lastSampleAt: lastSampleAt,
      actualSampleIntervalMs: actualSampleIntervalMs,
      lastLatencyMs: lastLatencyMs,
      effectivePollIntervalMs: effectivePollIntervalMs,
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
    interval: root.effectivePollIntervalMs
    repeat: true
    running: root.active
    onTriggered: root.poll()
  }

  Process {
    id: cursorProcess

    property string output: ""
    property double launchedAt: 0

    stdout: SplitParser {
      onRead: function(data) {
        cursorProcess.output += data
      }
    }

    onStarted: root.launchPending = false

    onExited: function(exitCode) {
      root.launchPending = false
      root.lastLatencyMs = cursorProcess.launchedAt > 0
        ? Math.max(0, Math.round(Date.now() - cursorProcess.launchedAt)) : 0
      if (exitCode === 0 && root.active)
        root.applyPayload(cursorProcess.output, Date.now())
      else if (exitCode !== 0)
        root.recordFailure("hyprctl cursorpos exited with status " + exitCode)
      else
        root.invalidate()
    }
  }
}
