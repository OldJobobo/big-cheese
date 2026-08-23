import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "services"
import "services/CursorPulseModel.js" as CursorPulseModel

Item {
  id: root

  // Injected by the Omarchy Shell service loader.
  property var shell: null

  readonly property string pluginVersion: "0.1.1"
  property bool enabled: true
  property bool easterEggEnabled: false
  property string shakeEffort: "normal"
  property int configuredPointerSize: 72
  property int configuredDurationMs: 2000
  property string mouseTrail: "reveal"
  property bool growEnabled: false
  property var detectorConfig: ({
    minimumStep: 14,
    minimumReversals: 3,
    minimumHorizontalTravel: 360,
    armingSpeed: 450
  })
  property bool configReady: false
  property string configError: ""
  property bool nativeThemeCursorActive: false
  property string nativeThemeCursorError: ""
  property string nativeThemeCursorFill: ""
  property string nativeThemeCursorOutline: ""
  property string nativeThemeCursorBaseline: "default"
  property int nativeThemeCursorSize: 24
  property bool nativeThemeCursorEnablePending: false
  readonly property bool nativeThemeCursorBusy: themeCursorStatusProcess.running
    || themeCursorApplyProcess.running || themeCursorRestoreProcess.running
  readonly property string omarchyCursorFill: String(Color.accent)
  readonly property string omarchyCursorOutline: String(Color.background)
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
  readonly property string themeCursorHelperPath: localPath(
    Qt.resolvedUrl("scripts/theme-cursor.py"))

  signal shakeDetected(real score)

  function statusPayload() {
    return {
      version: pluginVersion,
      enabled: enabled,
      easterEggEnabled: easterEggEnabled,
      tracking: tracking,
      sampleCount: sampleCount,
      pollingIntervalMs: cursorTracker.effectivePollIntervalMs,
      lastShakeAt: lastShakeAt,
      baselineTheme: cursorPulse.baselineTheme,
      baselineSize: cursorPulse.baselineSize,
      pulseActive: cursorPulse.active,
      growEnabled: growEnabled,
      activePeakSize: Math.round(cursorPulse.activePeakSize),
      triggerCount: cursorPulse.triggerCount,
      failureCount: failureCount,
      lastError: lastError,
      config: {
        ready: configReady,
        path: configPath,
        shakeEffort: shakeEffort,
        pointerSize: configuredPointerSize,
        durationMs: configuredDurationMs,
        mouseTrail: mouseTrail,
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
      },
      nativeCursorTheme: {
        active: nativeThemeCursorActive,
        busy: nativeThemeCursorBusy,
        fill: nativeThemeCursorFill,
        outline: nativeThemeCursorOutline,
        baselineTheme: nativeThemeCursorBaseline,
        baselineSize: nativeThemeCursorSize,
        error: nativeThemeCursorError
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
    mouseTrail = String(payload.mouseTrail || "reveal")
    detectorConfig = payload.detector || detectorConfig
    configError = String(payload.error || "")
    configReady = true
    setEnabled(payload.startEnabled === true)
  }

  function requestPulse(score) {
    if (cursorPulse.active && growEnabled) {
      lastShakeAt = Date.now()
      shakeDetected(score)
      return true
    }
    if (!cursorPulse.pulse(score)) return false
    // Keep the shared read-only position stream alive; visual mode never
    // starts a second tracker.
    cursorTracker.ensureRunning()
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

  function setGrowEnabled(value) {
    growEnabled = value === true
  }

  function toggleGrowEnabled() {
    setGrowEnabled(!growEnabled)
  }

  function setMouseTrail(value) {
    var mode = String(value || "")
    if (mode !== "off" && mode !== "reveal" && mode !== "always")
      return false
    mouseTrail = mode
    return true
  }

  function probeNativeThemeCursor() {
    if (themeCursorHelperPath === "") return false
    if (nativeThemeCursorBusy) {
      themeCursorRefresh.restart()
      return false
    }
    themeCursorStatusProcess.command = [themeCursorHelperPath, "status"]
    themeCursorStatusProcess.running = true
    return true
  }

  function applyNativeThemeCursor() {
    if (!nativeThemeCursorActive || themeCursorHelperPath === "") return false
    if (themeCursorApplyProcess.running || themeCursorRestoreProcess.running) {
      themeCursorRefresh.restart()
      return false
    }
    nativeThemeCursorError = ""
    themeCursorApplyProcess.command = [
      themeCursorHelperPath,
      "apply",
      omarchyCursorFill,
      omarchyCursorOutline,
      nativeThemeCursorBaseline,
      String(nativeThemeCursorSize)
    ]
    themeCursorApplyProcess.running = true
    return true
  }

  function setNativeThemeCursor(value) {
    var next = value === true
    if (nativeThemeCursorBusy || themeCursorHelperPath === "") return false
    nativeThemeCursorError = ""
    if (next) {
      var discoveredTheme = String(
        cursorPulse ? cursorPulse.baselineTheme || "default" : "default")
      if (discoveredTheme !== "jobo-big-cheese-runtime")
        nativeThemeCursorBaseline = discoveredTheme
      if (nativeThemeCursorBaseline === ""
          || nativeThemeCursorBaseline === "jobo-big-cheese-runtime")
        nativeThemeCursorBaseline = "default"
      nativeThemeCursorSize = Math.max(1,
        Number(cursorPulse ? cursorPulse.baselineSize : nativeThemeCursorSize)
          || nativeThemeCursorSize || 24)
      nativeThemeCursorEnablePending = !nativeThemeCursorActive
      nativeThemeCursorActive = true
      if (applyNativeThemeCursor()) return true
      nativeThemeCursorActive = !nativeThemeCursorEnablePending
      nativeThemeCursorEnablePending = false
      return false
    }
    if (!nativeThemeCursorActive) return true
    themeCursorRestoreProcess.command = [themeCursorHelperPath, "restore"]
    themeCursorRestoreProcess.running = true
    return true
  }

  function toggleNativeThemeCursor() {
    return setNativeThemeCursor(!nativeThemeCursorActive)
  }

  function toggleEasterEgg() {
    easterEggEnabled = !easterEggEnabled
  }

  onOmarchyCursorFillChanged: themeCursorRefresh.restart()
  onOmarchyCursorOutlineChanged: themeCursorRefresh.restart()

  Component.onCompleted: {
    loadConfig()
    probeNativeThemeCursor()
  }

  Timer {
    id: themeCursorRefresh
    interval: 180
    repeat: false
    onTriggered: root.probeNativeThemeCursor()
  }

  Process {
    id: themeCursorStatusProcess
    stdout: StdioCollector { id: themeCursorStatusOutput; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.nativeThemeCursorActive = false
        return
      }
      try {
        var payload = JSON.parse(themeCursorStatusOutput.text)
        var state = payload.state || {}
        root.nativeThemeCursorActive = payload.ok === true && payload.active === true
        root.nativeThemeCursorFill = String(state.fill || "")
        root.nativeThemeCursorOutline = String(state.outline || "")
        root.nativeThemeCursorBaseline = String(state.baselineTheme || "default")
        root.nativeThemeCursorSize = Math.max(1, Number(state.baselineSize) || 24)
        if (root.nativeThemeCursorActive
            && (root.nativeThemeCursorFill !== root.omarchyCursorFill
              || root.nativeThemeCursorOutline !== root.omarchyCursorOutline))
          root.applyNativeThemeCursor()
      } catch (error) {
        root.nativeThemeCursorActive = false
      }
    }
  }

  Process {
    id: themeCursorApplyProcess
    stdout: StdioCollector { id: themeCursorApplyOutput; waitForEnd: true }
    onExited: function(exitCode) {
      try {
        var payload = JSON.parse(themeCursorApplyOutput.text)
        if (exitCode !== 0 || payload.ok !== true) {
          root.nativeThemeCursorError = String(payload.error || "cursor theme refresh failed")
          if (root.nativeThemeCursorEnablePending)
            root.nativeThemeCursorActive = false
          root.nativeThemeCursorEnablePending = false
          return
        }
        root.nativeThemeCursorActive = true
        root.nativeThemeCursorFill = String(payload.fill || root.omarchyCursorFill)
        root.nativeThemeCursorOutline = String(payload.outline || root.omarchyCursorOutline)
        root.nativeThemeCursorEnablePending = false
        root.nativeThemeCursorError = ""
      } catch (error) {
        root.nativeThemeCursorError = "cursor theme refresh returned invalid status"
      }
    }
  }

  Process {
    id: themeCursorRestoreProcess
    stdout: StdioCollector { id: themeCursorRestoreOutput; waitForEnd: true }
    onExited: function(exitCode) {
      try {
        var payload = JSON.parse(themeCursorRestoreOutput.text)
        if (exitCode !== 0 || payload.ok !== true) {
          root.nativeThemeCursorError = String(payload.error || "cursor theme restore failed")
          return
        }
        root.nativeThemeCursorActive = false
        root.nativeThemeCursorFill = ""
        root.nativeThemeCursorOutline = ""
        root.nativeThemeCursorEnablePending = false
        root.nativeThemeCursorError = ""
      } catch (error) {
        root.nativeThemeCursorError = "cursor theme restore returned invalid status"
      }
    }
  }

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
    onMotion: function(speed, sampledAt) {
      cursorPulse.addGrowthMotion(speed, sampledAt, root.detectorConfig.armingSpeed)
    }
  }

  CursorPulse {
    id: cursorPulse
    enabled: root.enabled
    minimumPeakSize: root.configuredPointerSize
    maximumPeakSize: root.configuredPointerSize
    durationMs: root.configuredDurationMs
    durationMultiplier: root.easterEggEnabled ? 2 : 1
    growEnabled: root.growEnabled
  }

  CursorLocator {
    id: cursorLocator
    cursorTracker: cursorTracker
    cursorPulse: cursorPulse
    enabled: root.enabled || cursorPulse.active
    easterEggEnabled: root.easterEggEnabled
    trailMode: root.mouseTrail
    useOmarchyPalette: root.nativeThemeCursorActive
    cursorTheme: root.nativeThemeCursorBaseline
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

    function growEnable(): string {
      root.setGrowEnabled(true)
      return "enabled"
    }

    function growDisable(): string {
      root.setGrowEnabled(false)
      return "disabled"
    }

    function themeCursorEnable(): string {
      return root.setNativeThemeCursor(true) ? "enabling" : "busy"
    }

    function themeCursorDisable(): string {
      return root.setNativeThemeCursor(false) ? "restoring" : "busy"
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
