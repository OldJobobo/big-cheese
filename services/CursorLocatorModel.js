.pragma library

function finiteNumber(value, fallback) {
  var numeric = Number(value)
  return isFinite(numeric) ? numeric : fallback
}

function localPosition(globalX, globalY, screenX, screenY) {
  return {
    x: finiteNumber(globalX, -1) - finiteNumber(screenX, 0),
    y: finiteNumber(globalY, -1) - finiteNumber(screenY, 0)
  }
}

function contains(localX, localY, width, height) {
  var x = finiteNumber(localX, -1)
  var y = finiteNumber(localY, -1)
  var w = Math.max(0, finiteNumber(width, 0))
  var h = Math.max(0, finiteNumber(height, 0))
  return x >= 0 && y >= 0 && x < w && y < h
}

function pointerGeometry(localX, localY, requestedSize) {
  var size = Math.max(1, finiteNumber(requestedSize, 48))
  var hotSpotX = size * 3 / 64
  var hotSpotY = size * 2 / 64
  return {
    x: finiteNumber(localX, 0) - hotSpotX,
    y: finiteNumber(localY, 0) - hotSpotY,
    width: size * 46 / 64,
    height: size,
    hotSpotX: hotSpotX,
    hotSpotY: hotSpotY
  }
}
