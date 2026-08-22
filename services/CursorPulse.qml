import QtQuick
import Quickshell
import Quickshell.Io
import "CursorPulseModel.js" as CursorPulseModel

Item {
  id: root

  property bool enabled: true
  // Native resizing is retained only for stale-state recovery and an explicit
  // fallback. Hyprland may cache client-owned cursor surfaces after setcursor.
  property bool nativeResizeEnabled: false
  property int minimumPeakSize: 48
  property int maximumPeakSize: 72
  property int durationMs: 2000
  property real durationMultiplier: 1
  property int activeDurationMs: 0
  property bool active: false
  property string baselineTheme: "default"
  property int baselineSize: 24
  property int activePeakSize: 0
  property int triggerCount: 0
  property int completionCount: 0
  property int recoveryCount: 0
  property int failureCount: 0
  property string lastError: ""
  property string discoveryStatus: "pending"
  property bool baselineReady: false
  property bool recoveryReady: false
  property bool markerObserved: false
  property bool overlayReady: false
  property bool visualFinished: false
  property double pulseStartedAt: 0
  property string lastOutcome: ""
  property double lastOutcomeAt: 0
  property string recoveryReason: ""

  readonly property bool ready: nativeResizeEnabled
    ? (baselineReady && recoveryReady) : recoveryReady
  readonly property string mode: nativeResizeEnabled ? "native" : "overlay"
  readonly property string helperPath: helperPathFromUrl(
    Qt.resolvedUrl("../scripts/cursor-pulse.sh"))

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

  function normalizeTheme(raw) {
    var value = String(raw || "").trim()
    if (value.length >= 2) {
      var first = value.charAt(0)
      var last = value.charAt(value.length - 1)
      if ((first === "'" && last === "'") || (first === "\"" && last === "\""))
        value = value.substring(1, value.length - 1).trim()
    }
    return value
  }

  function positiveSize(raw) {
    var value = String(raw || "").trim()
    if (!/^[0-9]+$/.test(value)) return 0
    var size = Number(value)
    return isFinite(size) && size > 0 && size <= 512 ? Math.round(size) : 0
  }

  function effectiveDurationMs() {
    var base = Math.max(1, Number(durationMs) || 2000)
    var multiplier = Math.max(1, Number(durationMultiplier) || 1)
    return Math.round(base * multiplier)
  }

  function setFailure(message) {
    failureCount += 1
    lastError = String(message || "cursor pulse failed")
  }

  function clearErrors() {
    lastError = ""
  }

  function refreshBaseline() {
    if (active || discoveryStatus === "probing") return false
    discoveryStatus = "probing"
    baselineReady = false
    lastError = ""

    var theme = normalizeTheme(Quickshell.env("HYPRCURSOR_THEME"))
    if (theme === "") theme = normalizeTheme(Quickshell.env("XCURSOR_THEME"))
    if (theme !== "") {
      baselineTheme = theme
      continueSizeDiscovery()
    } else {
      themeProbe.command = ["gsettings", "get", "org.gnome.desktop.interface", "cursor-theme"]
      themeProbe.running = true
    }
    return true
  }

  function continueSizeDiscovery() {
    var size = positiveSize(Quickshell.env("HYPRCURSOR_SIZE"))
    if (size === 0) size = positiveSize(Quickshell.env("XCURSOR_SIZE"))
    if (size > 0) {
      baselineSize = size
      finishDiscovery()
    } else {
      sizeProbe.command = ["gsettings", "get", "org.gnome.desktop.interface", "cursor-size"]
      sizeProbe.running = true
    }
  }

  function finishDiscovery() {
    if (normalizeTheme(baselineTheme) === "") baselineTheme = "default"
    if (positiveSize(baselineSize) === 0) baselineSize = 24
    discoveryStatus = "ready"
    baselineReady = true
  }

  function pulse(rawScore) {
    var parsedScore = CursorPulseModel.parseScore(rawScore, false)
    if (!parsedScore.valid) {
      lastError = "score must be a finite number"
      return false
    }
    if (!enabled) {
      lastError = "service is disabled"
      return false
    }
    if (active) {
      lastError = "cursor pulse is already active"
      return false
    }
    if (maskProcess.running) {
      lastError = "cursor mask restoration is still finishing"
      return false
    }

    var score = parsedScore.value
    if (!nativeResizeEnabled) {
      if (!recoveryReady || recoveryProcess.running) {
        lastError = "cursor recovery is still finishing"
        return false
      }
      if (helperPath === "") {
        setFailure("cursor helper path is invalid")
        return false
      }
      activePeakSize = CursorPulseModel.overlaySize(
        score, minimumPeakSize, maximumPeakSize)
      activeDurationMs = effectiveDurationMs()
      active = true
      overlayReady = false
      visualFinished = false
      pulseStartedAt = Date.now()
      lastOutcome = ""
      lastOutcomeAt = 0
      markerObserved = false
      lastError = ""
      triggerCount += 1
      // The helper acknowledges only after Hyprland has hidden its cursor.
      // Locator rendering waits for that acknowledgement, eliminating even a
      // one-frame doubled pointer at pulse startup.
      maskProcess.command = [helperPath, "mask", String(activeDurationMs)]
      maskProcess.running = true
      return true
    }

    if (!recoveryReady) {
      lastError = "cursor recovery has not completed"
      return false
    }
    if (!baselineReady) {
      lastError = "cursor baseline is not ready"
      return false
    }
    if (helperPath === "") {
      setFailure("cursor helper path is invalid")
      return false
    }
    if (baselineSize >= maximumPeakSize) {
      lastError = "baseline cursor size is already at or above the pulse maximum"
      return false
    }

    activePeakSize = CursorPulseModel.peakSize(
      score, baselineSize, minimumPeakSize, maximumPeakSize)
    activeDurationMs = effectiveDurationMs()
    active = true
    markerObserved = false
    pulseStartedAt = Date.now()
    lastOutcome = ""
    lastOutcomeAt = 0
    lastError = ""
    try {
      Quickshell.execDetached([
        helperPath,
        "pulse",
        baselineTheme,
        String(baselineSize),
        String(activePeakSize),
        String(activeDurationMs)
      ])
      triggerCount += 1
      watchdogTimer.restart()
      return true
    } catch (error) {
      active = false
      activePeakSize = 0
      activeDurationMs = 0
      setFailure(error)
      return false
    }
  }

  function probePulseStatus() {
    if (helperPath === "" || statusProbe.running) return false
    statusProbe.command = [helperPath, "status"]
    statusProbe.running = true
    return true
  }

  function recover(reason) {
    if (helperPath === "" || recoveryProcess.running) return false
    recoveryReason = String(reason || "manual")
    recoveryProcess.command = [helperPath, "recover"]
    recoveryProcess.running = true
    return true
  }

  function completePulse(success, message, outcome, completedAt) {
    watchdogTimer.stop()
    active = false
    overlayReady = false
    visualFinished = false
    activePeakSize = 0
    activeDurationMs = 0
    lastOutcome = String(outcome || (success ? "success" : "failed"))
    lastOutcomeAt = Number(completedAt) || Date.now()
    if (success) {
      completionCount += 1
      lastError = ""
    } else {
      setFailure(message)
    }
  }

  function correlatedOutcome(payload) {
    var outcome = String(payload.outcome || "")
    var startedAt = Number(payload.startedAtMs)
    var completedAt = Number(payload.completedAtMs)
    if ((outcome !== "success" && outcome !== "failed")
        || !isFinite(startedAt) || !isFinite(completedAt)
        || startedAt < pulseStartedAt || completedAt < startedAt)
      return null
    return { name: outcome, completedAt: completedAt }
  }

  function parseHelperOutput(raw) {
    try {
      return JSON.parse(String(raw || "{}"))
    } catch (error) {
      return { state: "invalid" }
    }
  }

  function status() {
    return {
      enabled: enabled,
      ready: ready,
      mode: mode,
      nativeResizeEnabled: nativeResizeEnabled,
      active: active,
      overlayReady: overlayReady,
      visualFinished: visualFinished,
      activePeakSize: activePeakSize,
      durationMs: durationMs,
      durationMultiplier: durationMultiplier,
      activeDurationMs: activeDurationMs,
      baselineReady: baselineReady,
      discoveryStatus: discoveryStatus,
      baselineTheme: baselineTheme,
      baselineSize: baselineSize,
      recoveryReady: recoveryReady,
      markerObserved: markerObserved,
      triggerCount: triggerCount,
      completionCount: completionCount,
      recoveryCount: recoveryCount,
      failureCount: failureCount,
      lastOutcome: lastOutcome,
      lastOutcomeAt: lastOutcomeAt,
      error: lastError
    }
  }

  Component.onCompleted: {
    if (!recover("startup")) setFailure("cursor helper path is invalid")
  }

  Process {
    id: maskProcess

    stdout: SplitParser {
      onRead: function(data) {
        if (!root.active) return
        var state = String(data).trim()
        if (state === "masked" && !root.overlayReady) {
          root.overlayReady = true
          visualPulseTimer.restart()
        } else if (state === "restoring" && root.overlayReady) {
          // Drop the overlay before the helper reveals the native cursor.
          visualPulseTimer.stop()
          root.overlayReady = false
          root.visualFinished = true
        }
      }
    }

    onExited: function(exitCode) {
      if (!root.active) {
        if (exitCode !== 0)
          root.setFailure("cursor mask restoration failed")
        return
      }
      if (exitCode !== 0) {
        root.completePulse(false, "cursor mask restoration failed")
      } else if (root.visualFinished) {
        root.completePulse(true, "", "success", Date.now())
      } else if (!root.overlayReady) {
        root.completePulse(false, "cursor mask did not become ready")
      } else {
        root.completePulse(false, "cursor mask ended before the visual pulse")
      }
    }
  }

  Timer {
    id: visualPulseTimer
    interval: root.activeDurationMs + 500
    repeat: false
    // If the helper stalls, keep the overlay visible rather than leaving the
    // user with no cursor. The helper's eventual exit remains authoritative.
    onTriggered: root.setFailure("cursor mask exceeded its visual deadline")
  }

  Timer {
    interval: 120
    repeat: true
    running: root.active && root.nativeResizeEnabled
    onTriggered: root.probePulseStatus()
  }

  Timer {
    id: watchdogTimer
    interval: root.activeDurationMs + 450
    repeat: false
    onTriggered: {
      if (!root.recover("watchdog"))
        root.completePulse(false, "cursor watchdog could not start recovery")
    }
  }

  Timer {
    id: recoveryRetryTimer
    interval: 180
    repeat: false
    onTriggered: root.recover(root.recoveryReason || "startup")
  }

  Process {
    id: themeProbe
    stdout: StdioCollector { id: themeOutput; waitForEnd: true }
    onExited: function(exitCode) {
      var theme = exitCode === 0 ? root.normalizeTheme(themeOutput.text) : ""
      root.baselineTheme = theme !== "" ? theme : "default"
      root.continueSizeDiscovery()
    }
  }

  Process {
    id: sizeProbe
    stdout: StdioCollector { id: sizeOutput; waitForEnd: true }
    onExited: function(exitCode) {
      var size = exitCode === 0 ? root.positiveSize(sizeOutput.text) : 0
      root.baselineSize = size > 0 ? size : 24
      root.finishDiscovery()
    }
  }

  Process {
    id: statusProbe
    stdout: StdioCollector { id: statusOutput; waitForEnd: true }
    onExited: function(exitCode) {
      if (!root.active) return
      var payload = root.parseHelperOutput(statusOutput.text)
      var state = String(payload.state || "invalid")
      if (exitCode === 0 && (state === "active" || state === "stale")) {
        root.markerObserved = true
        if (state === "stale") root.recover("watchdog")
        return
      }
      if (exitCode === 0 && state === "idle") {
        var outcome = root.correlatedOutcome(payload)
        if (outcome !== null) {
          root.completePulse(
            outcome.name === "success",
            outcome.name === "success" ? "" : "cursor enlargement failed",
            outcome.name,
            outcome.completedAt)
        } else if (Date.now() - root.pulseStartedAt > root.activeDurationMs + 300) {
          root.completePulse(false, "cursor helper produced no correlated outcome")
        }
        return
      }
      if (Date.now() - root.pulseStartedAt > root.activeDurationMs)
        root.recover("watchdog")
    }
  }

  Process {
    id: recoveryProcess
    stdout: StdioCollector { id: recoveryOutput; waitForEnd: true }
    onExited: function(exitCode) {
      var reason = root.recoveryReason
      var payload = root.parseHelperOutput(recoveryOutput.text)
      var state = String(payload.state || "invalid")

      if (exitCode === 0 && state === "idle") {
        root.recoveryReady = true
        if (payload.recovered === true) root.recoveryCount += 1
        if (root.active && root.nativeResizeEnabled) {
          var outcome = root.correlatedOutcome(payload)
          if (outcome !== null) {
            root.completePulse(
              outcome.name === "success",
              outcome.name === "success" ? "" : "cursor enlargement failed",
              outcome.name,
              outcome.completedAt)
          } else if (payload.recovered === true) {
            root.completePulse(false, "cursor pulse required recovery", "recovered", Date.now())
          } else {
            root.probePulseStatus()
          }
        }
        if (reason === "startup" && root.discoveryStatus === "pending")
          root.refreshBaseline()
        return
      }

      if ((exitCode === 0 && state === "active") || state === "busy") {
        root.recoveryReady = false
        recoveryRetryTimer.restart()
        return
      }

      root.recoveryReady = false
      if (root.active && root.nativeResizeEnabled)
        root.completePulse(false, "cursor recovery failed")
      else if (reason === "startup" || root.nativeResizeEnabled)
        root.setFailure("cursor recovery failed")
    }
  }
}
