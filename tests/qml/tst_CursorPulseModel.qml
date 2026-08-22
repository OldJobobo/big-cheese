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
}
