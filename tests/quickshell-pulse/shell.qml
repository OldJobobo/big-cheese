import QtQuick
import Quickshell
import "services"

ShellRoot {
  id: root
  property bool failed: false
  property bool pulseStarted: false
  property bool sawRestoringState: false

  function fail(message) {
    if (failed) return
    failed = true
    console.error("PULSE_QML_TEST_FAIL: " + message)
    Qt.quit()
  }

  function check(condition, message) {
    if (!condition) {
      fail(message)
      return false
    }
    return true
  }

  CursorPulse {
    id: cursorPulse
    durationMs: 100
  }

  Timer {
    interval: 20
    repeat: true
    running: true
    onTriggered: {
      if (root.failed) return
      if (!root.pulseStarted) {
        if (!root.check(cursorPulse.ready, "visual pulse was blocked on helper readiness")) return
        if (!root.check(cursorPulse.mode === "overlay", "overlay mode is not the default")) return
        if (!root.check(!cursorPulse.nativeResizeEnabled, "native resizing is unexpectedly enabled")) return

        cursorPulse.enabled = false
        if (!root.check(!cursorPulse.pulse(1), "disabled pulse was accepted")) return
        if (!root.check(cursorPulse.lastError === "service is disabled", "disabled refusal was not reported")) return
        cursorPulse.enabled = true
        cursorPulse.clearErrors()

        if (!root.check(cursorPulse.pulse(0.5), "visual pulse was rejected")) return
        if (!root.check(cursorPulse.active, "pulse did not become active before display")) return
        if (!root.check(cursorPulse.activePeakSize === 60, "score did not map to 48..72 overlay range")) return
        if (!root.check(!cursorPulse.pulse(1), "overlapping pulse was accepted")) return
        root.pulseStarted = true
        return
      }

      if (cursorPulse.active) {
        if (cursorPulse.visualFinished) {
          root.sawRestoringState = true
          if (!root.check(!cursorPulse.overlayReady,
              "overlay remained visible while restoration was pending")) return
        }
        return
      }
      if (!root.check(root.sawRestoringState,
          "pulse completed before restoration was observed")) return
      if (!root.check(cursorPulse.triggerCount === 1, "trigger telemetry is wrong")) return
      if (!root.check(cursorPulse.completionCount === 1, "completion telemetry is wrong")) return
      if (!root.check(cursorPulse.failureCount === 0, "visual pulse recorded a failure")) return
      if (!root.check(cursorPulse.lastOutcome === "success", "success outcome was not recorded")) return
      if (!root.check(cursorPulse.lastOutcomeAt >= cursorPulse.pulseStartedAt, "outcome timestamp is wrong")) return
      if (!root.check(cursorPulse.activePeakSize === 0, "peak size was not cleared")) return
      if (!root.check(!cursorPulse.markerObserved, "visual pulse unexpectedly observed a helper marker")) return
      console.log("PULSE_QML_TEST_PASS")
      Qt.quit()
    }
  }

  Timer {
    interval: 2000
    repeat: false
    running: true
    onTriggered: root.fail("timed out waiting for visual CursorPulse")
  }
}
