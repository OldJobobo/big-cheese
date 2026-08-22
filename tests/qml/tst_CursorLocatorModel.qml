import QtQuick
import QtTest
import "../../services/CursorLocatorModel.js" as CursorLocatorModel

TestCase {
  name: "CursorLocatorModel"

  function test_mapsGlobalCoordinatesToNegativeOriginMonitor() {
    var local = CursorLocatorModel.localPosition(700, -1000, 640, -1080)
    compare(local.x, 60)
    compare(local.y, 80)
    verify(CursorLocatorModel.contains(local.x, local.y, 1920, 1080))
  }

  function test_mapsGlobalCoordinatesToHorizontalMonitor() {
    var local = CursorLocatorModel.localPosition(2620, -700, 2560, -798)
    compare(local.x, 60)
    compare(local.y, 98)
    verify(CursorLocatorModel.contains(local.x, local.y, 2560, 1440))
  }

  function test_outputBoundsAreHalfOpen() {
    verify(CursorLocatorModel.contains(0, 0, 2560, 1440))
    verify(CursorLocatorModel.contains(2559, 1439, 2560, 1440))
    verify(!CursorLocatorModel.contains(-1, 0, 2560, 1440))
    verify(!CursorLocatorModel.contains(2560, 0, 2560, 1440))
  }

  function test_pointerTipIsAnchoredToExactHotspot() {
    var geometry = CursorLocatorModel.pointerGeometry(100, 200, 64)
    compare(geometry.x + geometry.hotSpotX, 100)
    compare(geometry.y + geometry.hotSpotY, 200)
    compare(geometry.width, 46)
    compare(geometry.height, 64)
  }
}
