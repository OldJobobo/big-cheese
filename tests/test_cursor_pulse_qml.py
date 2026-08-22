import os
import shutil
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
HARNESS = ROOT / "tests" / "quickshell-pulse" / "shell.qml"


def test_visual_pulse_applies_duration_multiplier_without_native_resize(tmp_path):
    config = tmp_path / "quickshell-test"
    services = config / "services"
    scripts = config / "scripts"
    services.mkdir(parents=True)
    scripts.mkdir()
    shutil.copy2(HARNESS, config / "shell.qml")
    for source_name in ("CursorPulse.qml", "CursorPulseModel.js"):
        shutil.copy2(ROOT / "services" / source_name, services / source_name)

    helper_log = tmp_path / "helper.log"
    helper = scripts / "cursor-pulse.sh"
    helper.write_text(
        """#!/usr/bin/env bash
set -euo pipefail
printf '%s\\n' "$*" >>"$PULSE_TEST_LOG"
case ${1:-} in
  recover) printf '{"state":"idle","recovered":false}\\n' ;;
  status) printf '{"state":"idle"}\\n' ;;
  mask) printf 'masked\n'; sleep 0.1; printf 'restoring\n'; sleep 0.04 ;;
  pulse) exit 99 ;;
  *) exit 64 ;;
esac
""",
        encoding="utf-8",
    )
    helper.chmod(0o755)

    runtime = tmp_path / "runtime"
    runtime.mkdir(mode=0o700)
    env = os.environ.copy()
    env.update(
        QT_QPA_PLATFORM="offscreen",
        NO_COLOR="1",
        XDG_RUNTIME_DIR=str(runtime),
        PULSE_TEST_LOG=str(helper_log),
    )

    result = subprocess.run(
        ["qs", "--no-color", "-p", str(config)],
        env=env,
        capture_output=True,
        text=True,
        timeout=10,
    )
    output = result.stdout + result.stderr
    assert "PULSE_QML_TEST_PASS" in output, output
    assert "PULSE_QML_TEST_FAIL" not in output, output
    assert result.returncode == 0, output

    helper_calls = helper_log.read_text(encoding="utf-8").splitlines()
    assert helper_calls == ["recover", "mask 200"], helper_calls
