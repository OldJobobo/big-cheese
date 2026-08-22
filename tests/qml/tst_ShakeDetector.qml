import QtQuick
import QtTest
import "../../services"

TestCase {
  name: "ShakeDetector"

  ShakeDetector {
    id: detector
  }

  function feedGesture(startAt) {
    detector.addSample(0, 10, startAt)
    detector.addSample(120, 12, startAt + 60)
    detector.addSample(0, 9, startAt + 120)
    detector.addSample(120, 11, startAt + 180)
    detector.addSample(0, 10, startAt + 240)
  }

  function init() {
    detector.enabled = true
    detector.reset()
  }

  function test_clearGesturePreservesCooldown() {
    feedGesture(1000)
    compare(detector.lastTriggerAt, 1240)
    detector.clearGesture()
    compare(detector.lastTriggerAt, 1240)
    compare(detector.modelState.samples.length, 0)
  }

  function test_publicResetClearsCooldownAndGesture() {
    feedGesture(1000)
    verify(detector.lastTriggerAt > 0)
    detector.reset()
    compare(detector.lastTriggerAt, 0)
    compare(detector.modelState.samples.length, 0)
    verify(!detector.armed)
  }

  function test_disableClearsCooldownAndGesture() {
    feedGesture(1000)
    verify(detector.lastTriggerAt > 0)
    detector.enabled = false
    compare(detector.lastTriggerAt, 0)
    compare(detector.modelState.samples.length, 0)
    verify(!detector.armed)
  }
}
