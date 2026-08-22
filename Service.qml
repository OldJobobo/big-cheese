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
  property string shakeEffort: "normal"
  property int configuredPointerSize: 72
  property int configuredDurationMs: 2000
  property var detectorConfig: ({
    minimumStep: 14,
    minimumReversals: 3,
    minimumHorizontalTravel: 360,
    armingSpeed: 450
  })
  property bool configReady: false
  property string configError: ""
  property double lastShakeAt: 0
  readonly property bool tracking: cursorTracker.active
  readonly property int sampleCount: cursorTracker.sampleCount
  readonly property bool pulseActive: cursorPulse.active
  readonly property bool pulseReady: cursorPulse.ready
  readonly property int failureCount: cursorPulse.failureCount
    + cursorTracker.failureCount + (configError !== "" ? 1 : 0)
  readonly property string lastError: cursorPulse.lastError !== ""
    ? cursorPulse.lastError
    : cursorTracker.lastError !== "" ? cursorTracker.lastError : configError
  readonly property string configPath: localPath(Qt.resolvedUrl("cheese.toml"))
  readonly property string configReaderPath: localPath(
    Qt.resolvedUrl("scripts/cheese-config.py"))

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
      config: {
        ready: configReady,
        path: configPath,
        shakeEffort: shakeEffort,
        pointerSize: configuredPointerSize,
        durationMs: configuredDurationMs,
        error: configError
      },
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

  function localPath(url) {
    var value = String(url || "")
    if (value.indexOf("file://") !== 0) return ""
    try {
      var path = decodeURIComponent(value.substring(7))
      return path.indexOf("/") === 0 ? path : ""
    } catch (error) {
      return ""
    }
  }

  function loadConfig() {
    if (configProcess.running) return false
    if (configPath === "" || configReaderPath === "") {
      configError = "cheese.toml path is invalid"
      return false
    }
    configReady = false
    configError = ""
    configProcess.command = [configReaderPath, configPath]
    configProcess.running = true
    return true
  }

  function applyConfig(payload) {
    shakeEffort = String(payload.shakeEffort || "normal")
    configuredPointerSize = Number(payload.pointerSize) || 72
    configuredDurationMs = Number(payload.durationMs) || 2000
    detectorConfig = payload.detector || detectorConfig
    configError = String(payload.error || "")
    configReady = true
    setEnabled(payload.startEnabled === true)
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

  Component.onCompleted: loadConfig()

  Process {
    id: configProcess
    stdout: StdioCollector { id: configOutput; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.configError = "cheese.toml could not be read"
        return
      }
      try {
        root.applyConfig(JSON.parse(configOutput.text))
      } catch (error) {
        root.configError = "cheese.toml returned invalid settings"
      }
    }
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
    minimumStep: root.detectorConfig.minimumStep
    minimumReversals: root.detectorConfig.minimumReversals
    minimumHorizontalTravel: root.detectorConfig.minimumHorizontalTravel
    armingSpeed: root.detectorConfig.armingSpeed
    onShaken: function(score) {
      root.requestPulse(score)
    }
  }

  CursorPulse {
    id: cursorPulse
    enabled: root.enabled
    minimumPeakSize: root.configuredPointerSize
    maximumPeakSize: root.configuredPointerSize
    durationMs: root.configuredDurationMs
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
