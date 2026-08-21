import QtQuick
import Quickshell
import "services"

Item {
  id: root

  // Injected by the Omarchy Shell service loader.
  property var shell: null

  property bool enabled: true
  property double lastShakeAt: 0
  readonly property bool tracking: cursorTracker.active
  readonly property int sampleCount: cursorTracker.sampleCount

  signal shakeDetected(real score)

  function statusPayload() {
    return {
      enabled: enabled,
      tracking: tracking,
      sampleCount: sampleCount,
      lastShakeAt: lastShakeAt,
      detector: shakeDetector.status(),
      cursorTracker: cursorTracker.status()
    }
  }

  CursorTracker {
    id: cursorTracker
    active: root.enabled
    onSampled: function(x, y, sampledAt) {
      shakeDetector.addSample(x, y, sampledAt)
    }
  }

  ShakeDetector {
    id: shakeDetector
    enabled: root.enabled
    onShaken: function(score) {
      root.lastShakeAt = Date.now()
      root.shakeDetected(score)
    }
  }

  IpcHandler {
    target: "jobo-big-cheese"

    function status(): string {
      return JSON.stringify(root.statusPayload())
    }

    function enable(): string {
      root.enabled = true
      return "enabled"
    }

    function disable(): string {
      root.enabled = false
      return "disabled"
    }

    function reset(): string {
      shakeDetector.reset()
      return "reset"
    }
  }
}
