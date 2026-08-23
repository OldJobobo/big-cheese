import QtQuick
import QtTest
import "../../services/CursorPulseModel.js" as CursorPulseModel

TestCase {
  name: "CursorPulseModel"

  function test_malformedExplicitScoresAreRejected() {
    var malformed = ["", "cheese", "1.2.3", "NaN", "Infinity", "--1"]
    for (var i = 0; i < malformed.length; i += 1)
      verify(!CursorPulseModel.parseScore(malformed[i], false).valid)
  }

  function test_explicitScoresAreClamped() {
    compare(CursorPulseModel.parseScore("-4", false).value, 0)
    compare(CursorPulseModel.parseScore(".5", false).value, 0.5)
    compare(CursorPulseModel.parseScore("8", false).value, 1)
  }

  function test_emptyDefaultScoreIsOne() {
    var parsed = CursorPulseModel.parseScore("", true)
    verify(parsed.valid)
    compare(parsed.value, 1)
  }

  function test_overlaySizeUsesFixedVisualRange() {
    compare(CursorPulseModel.overlaySize(0, 48, 72), 48)
    compare(CursorPulseModel.overlaySize(0.5, 48, 72), 60)
    compare(CursorPulseModel.overlaySize(1, 48, 72), 72)
  }

  function test_nativePeakSizeStillAccountsForBaseline() {
    compare(CursorPulseModel.peakSize(0, 24, 48, 72), 48)
    compare(CursorPulseModel.peakSize(1, 24, 48, 72), 72)
    compare(CursorPulseModel.peakSize(0.5, 60, 48, 72), 67)
  }

  function test_fast_shaking_grows_faster_than_slow_shaking() {
    var slow = CursorPulseModel.growSize(72, 100, 0.2, 144)
    var fast = CursorPulseModel.growSize(72, 100, 1, 144)
    verify(slow > 72)
    verify(fast > slow)
    compare(CursorPulseModel.growSize(143, 100, 1, 144), 144)
  }

  function test_growth_shrinks_fluidly_toward_the_base_size() {
    var first = CursorPulseModel.shrinkSize(144, 72, 16)
    var later = CursorPulseModel.shrinkSize(first, 72, 100)
    verify(first < 144)
    verify(first > 72)
    verify(later < first)
    verify(later > 72)
    compare(CursorPulseModel.shrinkSize(72, 72, 100), 72)
  }
}
