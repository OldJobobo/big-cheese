import QtQuick

QtObject {
  id: root

  property bool enabled: true
  property int windowMs: 750
  property int cooldownMs: 1200
  property int minimumReversals: 3
  property real minimumTravel: 420
  property real minimumStep: 18

  property var samples: []
  property double lastTriggerAt: 0
  property int reversalCount: 0
  property real travel: 0

  signal shaken(real score)

  function reset() {
    samples = []
    reversalCount = 0
    travel = 0
  }

  function addSample(x, y, sampledAt) {
    if (!enabled) {
      reset()
      return
    }

    var next = samples.slice()
    next.push({ x: Number(x), y: Number(y), at: Number(sampledAt) })

    var cutoff = Number(sampledAt) - windowMs
    while (next.length > 0 && next[0].at < cutoff) next.shift()
    samples = next
    analyze(Number(sampledAt))
  }

  function analyze(now) {
    var reversals = 0
    var totalTravel = 0
    var previousDirection = 0

    for (var i = 1; i < samples.length; i += 1) {
      var dx = samples[i].x - samples[i - 1].x
      var dy = samples[i].y - samples[i - 1].y
      var distance = Math.sqrt(dx * dx + dy * dy)
      totalTravel += distance

      if (Math.abs(dx) < minimumStep || Math.abs(dx) < Math.abs(dy)) continue
      var direction = dx > 0 ? 1 : -1
      if (previousDirection !== 0 && direction !== previousDirection) reversals += 1
      previousDirection = direction
    }

    reversalCount = reversals
    travel = totalTravel

    if (reversals < minimumReversals || totalTravel < minimumTravel) return
    if (now - lastTriggerAt < cooldownMs) return

    lastTriggerAt = now
    var score = Math.min(1, Math.max(
      reversals / (minimumReversals + 2),
      totalTravel / (minimumTravel * 1.8)
    ))
    shaken(score)
    reset()
  }

  function status() {
    return {
      enabled: enabled,
      sampleWindowMs: windowMs,
      samples: samples.length,
      reversals: reversalCount,
      travel: Math.round(travel),
      lastTriggerAt: lastTriggerAt
    }
  }

  onEnabledChanged: {
    if (!enabled) reset()
  }
}
