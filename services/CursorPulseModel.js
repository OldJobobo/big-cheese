.pragma library

function parseScore(raw, allowEmptyDefault) {
  var text = String(raw === undefined || raw === null ? "" : raw).trim()
  if (text === "" && allowEmptyDefault)
    return { valid: true, value: 1 }
  if (!/^[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)$/.test(text))
    return { valid: false, value: 0 }
  var value = Number(text)
  if (!isFinite(value)) return { valid: false, value: 0 }
  return { valid: true, value: Math.max(0, Math.min(1, value)) }
}

function overlaySize(score, minimumPeakSize, maximumPeakSize) {
  var parsed = parseScore(score, false)
  if (!parsed.valid) return 0
  var lower = Math.max(1, Number(minimumPeakSize))
  var upper = Math.max(lower, Number(maximumPeakSize))
  return Math.round(lower + (upper - lower) * parsed.value)
}

function peakSize(score, baselineSize, minimumPeakSize, maximumPeakSize) {
  var lower = Math.max(Number(minimumPeakSize), Number(baselineSize) + 1)
  return overlaySize(score, lower, maximumPeakSize)
}

function clamp(value, minimum, maximum) {
  return Math.max(minimum, Math.min(maximum, Number(value) || 0))
}

function growthRate(strength) {
  return 12 + 48 * clamp(strength, 0, 1)
}

function growSize(size, elapsedMs, strength, maximumSize) {
  var current = Math.max(1, Number(size) || 1)
  var elapsed = clamp(elapsedMs, 0, 100)
  var maximum = Math.max(current, Number(maximumSize) || current)
  return Math.min(maximum,
    current + growthRate(strength) * elapsed / 1000)
}

function shrinkSize(size, baseSize, elapsedMs) {
  var base = Math.max(1, Number(baseSize) || 1)
  var current = Math.max(base, Number(size) || base)
  var elapsed = clamp(elapsedMs, 0, 100)
  // Exponential easing gives a fluid deceleration without a fixed animation
  // duration or an abrupt handoff to the normal cursor.
  return base + (current - base) * Math.exp(-elapsed / 360)
}
