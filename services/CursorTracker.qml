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
  property real rawCursorX: -1
  property real rawCursorY: -1
  property bool hasSample: false
  property bool hasRawSample: false
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
  readonly property string helperPath: helperPathFromUrl(
    Qt.resolvedUrl("../scripts/cursor-position.py"))

  signal observed(real x, real y, double sampledAt)
  signal sampled(real x, real y, double sampledAt)
  signal samplingInvalidated()

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

  // Starts one long-lived sampler. Each coordinate query uses Hyprland's
  // read-only command socket; no hyprctl process is launched per sample.
  function poll() {
    if (!active || launchPending || cursorProcess.running) return false
    if (helperPath === "") {
      recordFailure("cursor position helper path is invalid")
      return false
    }
    launchPending = true
    cursorProcess.launchedAt = Date.now()
    cursorProcess.command = [helperPath, String(armedPollIntervalMs)]
    launchCount += 1
    cursorProcess.running = true
    return true
  }

  function ensureRunning() {
    if (cursorProcess.running || launchPending) return true
    return root.poll()
  }

  function invalidate() {
    hasSample = false
    hasRawSample = false
    cursorX = -1
    cursorY = -1
    rawCursorX = -1
    rawCursorY = -1
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
      if (typeof payload.error === "string" && payload.error !== "")
        throw new Error(payload.error)
      if (typeof payload.x !== "number" || !isFinite(payload.x)
          || typeof payload.y !== "number" || !isFinite(payload.y))
        throw new Error("cursor payload has no finite numeric coordinates")

      var payloadSampledAt = payload.sampledAtMs
      var now = payloadSampledAt === undefined ? sampledAt : payloadSampledAt
      if (typeof now !== "number" || !isFinite(now))
        throw new Error("cursor sample has no finite numeric timestamp")

      rawCursorX = payload.x
      rawCursorY = payload.y
      hasRawSample = true
      observed(rawCursorX, rawCursorY, now)

      // The helper runs at the armed cadence. During idle tracking, consume
      // every other sample to preserve the original 110 ms detector cadence
      // without stopping or restarting the process.
      if (payloadSampledAt !== undefined && lastSampleAt > 0
          && now - lastSampleAt < effectivePollIntervalMs - 2)
        return true

      var latency = payload.latencyMs
      if (typeof latency === "number" && isFinite(latency) && latency >= 0)
        lastLatencyMs = Math.round(latency)
      actualSampleIntervalMs = lastSampleAt > 0
        ? Math.max(0, Math.round(now - lastSampleAt)) : 0
      cursorX = payload.x
      cursorY = payload.y
      hasSample = true
      sampleCount += 1
      consecutiveFailureCount = 0
      lastSampleAt = now
      lastError = ""
      sampled(cursorX, cursorY, now)
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
      hasRawSample: hasRawSample,
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
      rawX: rawCursorX,
      rawY: rawCursorY,
      error: lastError
    }
  }

  onActiveChanged: {
    if (active) {
      root.ensureRunning()
    } else {
      launchPending = false
      if (cursorProcess.running) cursorProcess.running = false
      invalidate()
    }
  }

  Process {
    id: cursorProcess

    property double launchedAt: 0

    stdout: SplitParser {
      onRead: function(data) {
        if (root.active) root.applyPayload(data, Date.now())
      }
    }

    onStarted: {
      root.launchPending = false
      root.lastLatencyMs = cursorProcess.launchedAt > 0
        ? Math.max(0, Math.round(Date.now() - cursorProcess.launchedAt)) : 0
    }

    onExited: function(exitCode) {
      root.launchPending = false
      if (!root.active) return
      root.recordFailure("cursor position stream exited with status " + exitCode)
      retryTimer.restart()
    }
  }

  Timer {
    id: retryTimer
    interval: 180
    repeat: false
    onTriggered: root.ensureRunning()
  }
}
