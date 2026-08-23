.pragma library

function initialState(lastTriggerAt) {
  return {
    samples: [],
    armed: false,
    reversals: 0,
    horizontalTravel: 0,
    verticalTravel: 0,
    peakSpeed: 0,
    lastDirection: 0,
    lastTriggerAt: Number(lastTriggerAt) || 0
  }
}

function finiteNumber(value) {
  return typeof value === "number" && isFinite(value) ? value : null
}

function clamp(value, minimum, maximum) {
  return Math.max(minimum, Math.min(maximum, value))
}

function normalizedConfig(config) {
  var source = config || {}
  return {
    windowMs: Math.max(1, Number(source.windowMs) || 800),
    maxSampleGapMs: Math.max(1, Number(source.maxSampleGapMs) || 220),
    minimumStep: Math.max(0, Number(source.minimumStep) || 14),
    minimumReversals: Math.max(1, Number(source.minimumReversals) || 3),
    minimumHorizontalTravel: Math.max(1, Number(source.minimumHorizontalTravel) || 360),
    horizontalDominance: Math.max(1, Number(source.horizontalDominance) || 1.15),
    maximumSegmentContribution: Math.max(1, Number(source.maximumSegmentContribution) || 180),
    armingSpeed: Math.max(1, Number(source.armingSpeed) || 450),
    cooldownMs: Math.max(0, Number(source.cooldownMs) || 1400)
  }
}

function analyze(samples, config, lastTriggerAt) {
  var reversals = 0
  var horizontalTravel = 0
  var verticalTravel = 0
  var peakSpeed = 0
  var previousDirection = 0
  var armed = false

  for (var i = 1; i < samples.length; i += 1) {
    var dx = samples[i].x - samples[i - 1].x
    var dy = samples[i].y - samples[i - 1].y
    var dt = samples[i].at - samples[i - 1].at
    var distance = Math.sqrt(dx * dx + dy * dy)

    if (dt <= 0 || distance < config.minimumStep) continue

    var absX = Math.abs(dx)
    var absY = Math.abs(dy)
    if (absX >= absY * config.horizontalDominance) {
      var contribution = Math.min(absX, config.maximumSegmentContribution)
      var speed = contribution / dt * 1000
      var direction = dx > 0 ? 1 : -1

      horizontalTravel += contribution
      peakSpeed = Math.max(peakSpeed, speed)
      if (speed >= config.armingSpeed) armed = true
      if (previousDirection !== 0 && direction !== previousDirection)
        reversals += 1
      previousDirection = direction
    } else {
      verticalTravel += Math.min(absY, config.maximumSegmentContribution)
    }
  }

  return {
    samples: samples,
    armed: armed,
    reversals: reversals,
    horizontalTravel: horizontalTravel,
    verticalTravel: verticalTravel,
    peakSpeed: peakSpeed,
    lastDirection: previousDirection,
    lastTriggerAt: lastTriggerAt
  }
}

function scoreFor(state, config) {
  var reversalScore = clamp(
    state.reversals / Math.max(config.minimumReversals + 2, 1), 0, 1)
  var travelScore = clamp(
    state.horizontalTravel / (config.minimumHorizontalTravel * 1.75), 0, 1)
  var speedScore = clamp(
    state.peakSpeed / (config.armingSpeed * 3), 0, 1)
  return clamp((reversalScore + travelScore + speedScore) / 3, 0, 1)
}

function addSample(previousState, sample, rawConfig) {
  var config = normalizedConfig(rawConfig)
  var state = previousState || initialState(0)
  var x = finiteNumber(sample && sample.x)
  var y = finiteNumber(sample && sample.y)
  var at = finiteNumber(sample && sample.at)

  if (x === null || y === null || at === null)
    return { state: state, triggered: false, score: 0, accepted: false, motionSpeed: 0 }

  var samples = Array.isArray(state.samples) ? state.samples.slice() : []
  var lastTriggerAt = Number(state.lastTriggerAt) || 0
  var motionSpeed = 0
  if (samples.length > 0) {
    var previous = samples[samples.length - 1]
    var gap = at - previous.at
    if (gap <= 0 || gap > config.maxSampleGapMs) {
      samples = []
    } else {
      var motionX = Math.abs(x - previous.x)
      var motionY = Math.abs(y - previous.y)
      var motionDistance = Math.sqrt(motionX * motionX + motionY * motionY)
      if (motionDistance >= config.minimumStep
          && motionX >= motionY * config.horizontalDominance)
        motionSpeed = Math.min(motionX, config.maximumSegmentContribution)
          / gap * 1000
    }
  }

  samples.push({ x: x, y: y, at: at })
  var cutoff = at - config.windowMs
  while (samples.length > 0 && samples[0].at < cutoff) samples.shift()

  var next = analyze(samples, config, lastTriggerAt)
  var dominancePass = next.horizontalTravel >=
    next.verticalTravel * config.horizontalDominance
  var cooldownPass = lastTriggerAt <= 0 || at - lastTriggerAt >= config.cooldownMs
  var trigger = next.armed
    && next.reversals >= config.minimumReversals
    && next.horizontalTravel >= config.minimumHorizontalTravel
    && dominancePass
    && cooldownPass

  if (!trigger)
    return {
      state: next,
      triggered: false,
      score: 0,
      accepted: true,
      motionSpeed: motionSpeed
    }

  var score = scoreFor(next, config)
  var cleared = initialState(at)
  return {
    state: cleared,
    triggered: true,
    score: score,
    accepted: true,
    motionSpeed: motionSpeed
  }
}
