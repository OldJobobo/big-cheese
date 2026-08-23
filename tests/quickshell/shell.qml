import QtQuick
import Quickshell
import "services"

ShellRoot {
  id: root
  property bool waitingForProcessSample: false
  property bool failed: false

  function fail(message) {
    if (failed) return
    failed = true
    console.error("TRACKER_TEST_FAIL: " + message)
    Qt.quit()
  }

  function check(condition, message) {
    if (!condition) {
      fail(message)
      return false
    }
    return true
  }

  ShakeDetector {
    id: detector
  }

  CursorTracker {
    id: tracker
    armed: detector.armed
    idlePollIntervalMs: 1000
    armedPollIntervalMs: 55
    onSampled: function(x, y, sampledAt) {
      if (root.failed || !root.waitingForProcessSample) return
      if (!root.check(x === -1920 && y === 360, "fake coordinates changed")) return
      if (!root.check(sampledAt > 0, "sample timestamp is missing")) return
      if (!root.check(tracker.launchCount === 1, "overlapping poll was launched")) return
      root.waitingForProcessSample = false
      tracker.active = false
      console.log("TRACKER_TEST_PASS")
      Qt.quit()
    }
    onSamplingInvalidated: detector.clearGesture()
  }

  function runTests() {
    if (!check(tracker.effectivePollIntervalMs === 1000, "idle interval is wrong")) return
    detector.addSample(0, 0, 0)
    detector.addSample(120, 0, 60)
    if (!check(detector.armed, "fast movement did not arm detector")) return
    if (!check(tracker.effectivePollIntervalMs === 55, "armed interval is wrong")) return

    if (!check(tracker.applyPayload('{"x":-1280,"y":240}', 1000), "valid payload rejected")) return
    if (!check(tracker.cursorX === -1280 && tracker.cursorY === 240, "negative coordinates changed")) return
    if (!check(!tracker.applyPayload('bad-json', 1100), "malformed payload accepted")) return
    if (!check(tracker.hasSample, "one failure invalidated a fresh sample")) return
    if (!check(!tracker.applyPayload('{}', 1200), "coordinate-free payload accepted")) return
    if (!check(!tracker.hasSample && tracker.failureCount === 2, "repeated failures did not invalidate")) return
    if (!check(!detector.armed, "repeated tracker failures did not clear detector")) return
    if (!check(tracker.effectivePollIntervalMs === 1000, "failure left tracker at armed interval")) return

    if (!check(!tracker.applyPayload('{"x":null,"y":1}', 1300), "null coordinate accepted")) return
    if (!check(!tracker.applyPayload('{"x":"1","y":1}', 1300), "text coordinate accepted")) return
    if (!check(!tracker.applyPayload('{"x":false,"y":1}', 1300), "boolean coordinate accepted")) return
    if (!check(!tracker.applyPayload('{"x":1,"y":1}', null), "null timestamp accepted")) return
    if (!check(!tracker.applyPayload('{"x":1,"y":1}', ""), "blank timestamp accepted")) return
    if (!check(!tracker.applyPayload('{"x":1,"y":1}', false), "boolean timestamp accepted")) return
    if (!check(!tracker.applyPayload('{"x":1,"y":1}', "1300"), "text timestamp accepted")) return

    tracker.sampleCount = 0
    tracker.launchCount = 0
    tracker.clearErrors()
    root.waitingForProcessSample = true
    tracker.active = true
    tracker.ensureRunning()
    if (!check(tracker.launchCount === 1,
        "activation launched " + tracker.launchCount + " cursor streams: "
          + tracker.lastError + " (" + tracker.helperPath + ")")) return
    if (!check(!tracker.poll(), "overlapping poll was not rejected")) return
  }

  Timer {
    interval: 1
    running: true
    repeat: false
    onTriggered: root.runTests()
  }

  Timer {
    interval: 3000
    running: true
    repeat: false
    onTriggered: root.fail("timed out waiting for fake hyprctl")
  }
}
