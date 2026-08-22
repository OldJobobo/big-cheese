import os
import shutil
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
HARNESS = ROOT / "tests" / "quickshell"


def test_cursor_tracker_under_quickshell_with_fake_hyprctl(tmp_path):
    fake_bin = tmp_path / "bin"
    fake_bin.mkdir()
    fake = fake_bin / "hyprctl"
    fake.write_text(
        """#!/usr/bin/env bash
set -euo pipefail
[[ ${1:-} == cursorpos && ${2:-} == -j ]]
sleep 0.08
printf '{"x":-1920,"y":360}\\n'
""",
        encoding="utf-8",
    )
    fake.chmod(0o755)

    config = tmp_path / "quickshell-test"
    config.mkdir()
    shutil.copy2(HARNESS / "shell.qml", config / "shell.qml")
    for source_name in ("CursorTracker.qml", "ShakeDetector.qml", "ShakeModel.js"):
        shutil.copy2(ROOT / "services" / source_name, config / source_name)

    runtime = tmp_path / "runtime"
    runtime.mkdir(mode=0o700)
    env = os.environ.copy()
    env.update(
        PATH=f"{fake_bin}:{env['PATH']}",
        XDG_RUNTIME_DIR=str(runtime),
        QT_QPA_PLATFORM="offscreen",
        NO_COLOR="1",
    )
    result = subprocess.run(
        ["qs", "--no-color", "-p", str(config)],
        env=env,
        capture_output=True,
        text=True,
        timeout=10,
    )
    output = result.stdout + result.stderr
    assert "TRACKER_TEST_PASS" in output, output
    assert "TRACKER_TEST_FAIL" not in output, output
    assert result.returncode == 0, output
