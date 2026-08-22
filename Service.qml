import QtQuick
import Quickshell
import Quickshell.Io
import "services"
import "services/CursorPulseModel.js" as CursorPulseModel

Item {
  id: root

  // Injected by the Omarchy Shell service loader.
  property var shell: null

  readonly property string pluginVersion: "0.1.0"
  property bool enabled: true
  property double lastShakeAt: 0
  readonly property bool tracking: cursorTracker.active
  readonly property int sampleCount: cursorTracker.sampleCount
  readonly property bool pulseActive: cursorPulse.active
  readonly property bool pulseReady: cursorPulse.ready
  readonly property int failureCount: cursorPulse.failureCount + cursorTracker.failureCount
  readonly property string lastError: cursorPulse.lastError !== ""
    ? cursorPulse.lastError : cursorTracker.lastError

  signal shakeDetected(real score)

  function statusPayload() {
    return {
      version: pluginVersion,
      enabled: enabled,
      tracking: tracking,
      sampleCount: sampleCount,
      pollingIntervalMs: cursorTracker.effectivePollIntervalMs,
      lastShakeAt: lastShakeAt,
      baselineTheme: cursorPulse.baselineTheme,
      baselineSize: cursorPulse.baselineSize,
      pulseActive: cursorPulse.active,
      activePeakSize: cursorPulse.activePeakSize,
      triggerCount: cursorPulse.triggerCount,
      failureCount: failureCount,
      lastError: lastError,
      detector: shakeDetector.status(),
      cursorTracker: cursorTracker.status(),
      cursorPulse: cursorPulse.status(),
      cursorPalette: {
        detected: cursorLocator.paletteDetected,
        theme: cursorLocator.paletteTheme,
        fill: String(cursorLocator.pointerFill),
        stroke: String(cursorLocator.pointerStroke)
      }
    }
  }

  function requestPulse(score) {
    if (!cursorPulse.pulse(score)) return false
    // Refresh the shared global position immediately; visual mode never starts
    // a cursor-size helper or a second tracker.
    cursorTracker.poll()
    lastShakeAt = Date.now()
    shakeDetected(score)
    return true
  }

  function setEnabled(value) {
    enabled = value === true
    if (!enabled) shakeDetector.reset()
  }

  function toggleEnabled() {
    setEnabled(!enabled)
  }

  CursorTracker {
    id: cursorTracker
    active: root.enabled || cursorPulse.active
    armed: shakeDetector.armed || cursorPulse.active
    onSampled: function(x, y, sampledAt) {
      shakeDetector.addSample(x, y, sampledAt)
    }
    onSamplingInvalidated: shakeDetector.clearGesture()
  }

  ShakeDetector {
    id: shakeDetector
    enabled: root.enabled
    onShaken: function(score) {
      root.requestPulse(score)
    }
  }

  CursorPulse {
    id: cursorPulse
    enabled: root.enabled
  }

  CursorLocator {
    id: cursorLocator
    cursorTracker: cursorTracker
    cursorPulse: cursorPulse
    enabled: root.enabled || cursorPulse.active
  }

  IpcHandler {
    target: "jobo-big-cheese"

    function status(): string {
      return JSON.stringify(root.statusPayload())
    }

    function enable(): string {
      root.setEnabled(true)
      return "enabled"
    }

    function disable(): string {
      root.setEnabled(false)
      return "disabled"
    }

    function reset(): string {
      shakeDetector.reset()
      cursorTracker.clearErrors()
      cursorPulse.clearErrors()
      return "reset"
    }

    function trigger(): string {
      return root.requestPulse(1) ? "triggered" : "rejected: " + cursorPulse.lastError
    }

    // Quickshell IPC methods have fixed arity, so an explicit score uses a
    // separate method while `trigger` remains the zero-argument default.
    function triggerScore(score: string): string {
      var parsed = CursorPulseModel.parseScore(score, false)
      if (!parsed.valid) return "invalid score"
      return root.requestPulse(parsed.value)
        ? "triggered" : "rejected: " + cursorPulse.lastError
    }

    // QML IPC methods must be valid JavaScript identifiers, so this cannot use
    // the hyphenated `refresh-baseline` spelling from the original plan.
    function refreshBaseline(): string {
      return cursorPulse.refreshBaseline() ? "refreshing" : "busy"
    }

    function recover(): string {
      return cursorPulse.recover("manual") ? "recovering" : "busy"
    }
  }
}
