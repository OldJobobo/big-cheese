import QtQuick
import "ShakeModel.js" as ShakeModel

QtObject {
  id: root

  property bool enabled: true
  property int windowMs: 800
  property int maxSampleGapMs: 220
  property real minimumStep: 14
  property int minimumReversals: 3
  property real minimumHorizontalTravel: 360
  property real horizontalDominance: 1.15
  property real maximumSegmentContribution: 180
  property real armingSpeed: 450
  property int cooldownMs: 1400

  property var modelState: ShakeModel.initialState(0)
  readonly property bool armed: Boolean(modelState.armed)
  readonly property int reversalCount: Number(modelState.reversals) || 0
  readonly property real travel: Number(modelState.horizontalTravel) || 0
  readonly property real verticalTravel: Number(modelState.verticalTravel) || 0
  readonly property real peakSpeed: Number(modelState.peakSpeed) || 0
  readonly property double lastTriggerAt: Number(modelState.lastTriggerAt) || 0

  signal shaken(real score)

  function config() {
    return {
      windowMs: windowMs,
      maxSampleGapMs: maxSampleGapMs,
      minimumStep: minimumStep,
      minimumReversals: minimumReversals,
      minimumHorizontalTravel: minimumHorizontalTravel,
      horizontalDominance: horizontalDominance,
      maximumSegmentContribution: maximumSegmentContribution,
      armingSpeed: armingSpeed,
      cooldownMs: cooldownMs
    }
  }

  function clearGesture() {
    modelState = ShakeModel.initialState(lastTriggerAt)
  }

  function reset() {
    modelState = ShakeModel.initialState(0)
  }

  function addSample(x, y, sampledAt) {
    if (!enabled) {
      reset()
      return
    }

    var result = ShakeModel.addSample(
      modelState,
      { x: x, y: y, at: sampledAt },
      config())
    modelState = result.state
    if (result.triggered) shaken(result.score)
  }

  function status() {
    return {
      enabled: enabled,
      armed: armed,
      sampleWindowMs: windowMs,
      maxSampleGapMs: maxSampleGapMs,
      samples: modelState.samples.length,
      reversals: reversalCount,
      horizontalTravel: Math.round(travel),
      verticalTravel: Math.round(verticalTravel),
      peakSpeed: Math.round(peakSpeed),
      lastTriggerAt: lastTriggerAt,
      thresholds: {
        minimumStep: minimumStep,
        minimumReversals: minimumReversals,
        minimumHorizontalTravel: minimumHorizontalTravel,
        horizontalDominance: horizontalDominance,
        maximumSegmentContribution: maximumSegmentContribution,
        armingSpeed: armingSpeed,
        cooldownMs: cooldownMs
      }
    }
  }

  onEnabledChanged: {
    if (!enabled) reset()
  }
}
