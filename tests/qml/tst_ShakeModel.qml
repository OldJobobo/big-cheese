import QtQuick
import QtTest
import "../../services/ShakeModel.js" as ShakeModel

TestCase {
  name: "ShakeModel"

  function config() {
    return {
      windowMs: 800,
      maxSampleGapMs: 220,
      minimumStep: 14,
      minimumReversals: 3,
      minimumHorizontalTravel: 360,
      horizontalDominance: 1.15,
      maximumSegmentContribution: 180,
      armingSpeed: 450,
      cooldownMs: 1400
    }
  }

  function feed(points, state) {
    var current = state || ShakeModel.initialState(0)
    var triggers = []
    for (var i = 0; i < points.length; i += 1) {
      var result = ShakeModel.addSample(current, points[i], config())
      current = result.state
      if (result.triggered) triggers.push(result.score)
    }
    return { state: current, triggers: triggers }
  }

  function gesture(startAt, offset) {
    var x = Number(offset) || 0
    return [
      { x: x, y: 10, at: startAt },
      { x: x + 120, y: 12, at: startAt + 60 },
      { x: x, y: 9, at: startAt + 120 },
      { x: x + 120, y: 11, at: startAt + 180 },
      { x: x, y: 10, at: startAt + 240 }
    ]
  }

  function test_fastAlternatingGestureTriggersOnce() {
    var result = feed(gesture(0, 0))
    compare(result.triggers.length, 1)
    verify(result.triggers[0] >= 0 && result.triggers[0] <= 1)
    compare(result.state.samples.length, 0)
  }

  function test_singleFastSwipeDoesNotTrigger() {
    var result = feed([
      { x: 0, y: 0, at: 0 },
      { x: 180, y: 1, at: 50 },
      { x: 340, y: 2, at: 100 }
    ])
    compare(result.triggers.length, 0)
  }

  function test_slowMovementOutsideWindowDoesNotTrigger() {
    var result = feed([
      { x: 0, y: 0, at: 0 },
      { x: 120, y: 0, at: 300 },
      { x: 0, y: 0, at: 600 },
      { x: 120, y: 0, at: 900 },
      { x: 0, y: 0, at: 1200 }
    ])
    compare(result.triggers.length, 0)
    compare(result.state.reversals, 0)
  }

  function test_tinyJitterDoesNotTrigger() {
    var points = []
    for (var i = 0; i < 20; i += 1)
      points.push({ x: i % 2 === 0 ? 0 : 5, y: 0, at: i * 30 })
    compare(feed(points).triggers.length, 0)
  }

  function test_mostlyVerticalMovementDoesNotTrigger() {
    var result = feed([
      { x: 0, y: 0, at: 0 },
      { x: 40, y: 140, at: 60 },
      { x: 0, y: 280, at: 120 },
      { x: 40, y: 420, at: 180 },
      { x: 0, y: 560, at: 240 }
    ])
    compare(result.triggers.length, 0)
    verify(result.state.verticalTravel > result.state.horizontalTravel)
  }

  function test_pointerWarpDoesNotTrigger() {
    var result = feed([
      { x: 0, y: 0, at: 0 },
      { x: 10000, y: 0, at: 10 }
    ])
    compare(result.triggers.length, 0)
    compare(result.state.horizontalTravel, 180)
  }

  function test_negativeGlobalCoordinatesWork() {
    var result = feed(gesture(0, -1600))
    compare(result.triggers.length, 1)
  }

  function test_staleGapResetsGesture() {
    var result = feed([
      { x: 0, y: 0, at: 0 },
      { x: 120, y: 0, at: 60 },
      { x: 0, y: 0, at: 120 },
      { x: 120, y: 0, at: 500 },
      { x: 0, y: 0, at: 560 },
      { x: 120, y: 0, at: 620 }
    ])
    compare(result.triggers.length, 0)
    compare(result.state.reversals, 1)
  }

  function test_cooldownSuppressesImmediateRetrigger() {
    var first = feed(gesture(0, 0))
    compare(first.triggers.length, 1)
    var second = feed(gesture(400, 0), first.state)
    compare(second.triggers.length, 0)
  }

  function test_laterGestureTriggersAfterCooldown() {
    var first = feed(gesture(0, 0))
    var blocked = feed(gesture(400, 0), first.state)
    var later = feed(gesture(1800, -400), blocked.state)
    compare(later.triggers.length, 1)
  }

  function test_invalidSampleIsRejectedWithoutChangingState_data() {
    return [
      { tag: "text-coordinate", sample: { x: "12", y: 0, at: 10 } },
      { tag: "blank-coordinate", sample: { x: "", y: 0, at: 10 } },
      { tag: "null-coordinate", sample: { x: null, y: 0, at: 10 } },
      { tag: "boolean-coordinate", sample: { x: false, y: 0, at: 10 } },
      { tag: "text-timestamp", sample: { x: 1, y: 0, at: "10" } },
      { tag: "blank-timestamp", sample: { x: 1, y: 0, at: "" } },
      { tag: "null-timestamp", sample: { x: 1, y: 0, at: null } },
      { tag: "boolean-timestamp", sample: { x: 1, y: 0, at: false } }
    ]
  }

  function test_invalidSampleIsRejectedWithoutChangingState(data) {
    var state = ShakeModel.initialState(0)
    var result = ShakeModel.addSample(state, data.sample, config())
    verify(!result.accepted)
    compare(result.state.samples.length, 0)
  }
}
