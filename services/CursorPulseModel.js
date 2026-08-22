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
