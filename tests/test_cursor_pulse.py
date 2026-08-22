import base64
import json
import os
import signal
import subprocess
import time
from pathlib import Path

import pytest


ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / "scripts" / "cursor-pulse.sh"


def wait_until(predicate, timeout=2.0):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if predicate():
            return
        time.sleep(0.01)
    raise AssertionError("condition was not met before timeout")


@pytest.fixture
def helper_env(tmp_path):
    fake_bin = tmp_path / "bin"
    fake_bin.mkdir()
    log = tmp_path / "hyprctl.log"
    fake = fake_bin / "hyprctl"
    fake.write_text(
        """#!/usr/bin/env bash
set -euo pipefail
printf '%s\\0' "$@" >>"$HYPRCTL_LOG"
printf '\\n' >>"$HYPRCTL_LOG"
case ${1:-} in
  -j)
    if [[ ${2:-} == getoption && ${3:-} == cursor:invisible ]]; then
      printf '{"option":"cursor:invisible","bool":%s,"set":false}\n' "${HYPRCTL_CURSOR_INVISIBLE:-false}"
    fi
    ;;
  cursorpos)
    printf '%s\\n' "${HYPRCTL_CURSORPOS:--1920, 360}"
    ;;
  dispatch)
    if [[ ${HYPRCTL_FAIL_LUA_DISPATCH:-0} == 1 && ${2:-} == hl.dsp.cursor.move* ]]; then
      exit 1
    fi
    if [[ ${HYPRCTL_FAIL_DISPATCH:-0} == 1 ]]; then
      exit 1
    fi
    ;;
  setcursor)
    if [[ -n ${HYPRCTL_SLEEP_SIZE:-} && ${3:-} == "$HYPRCTL_SLEEP_SIZE" ]]; then
      sleep 0.3
    fi
    if [[ -n ${HYPRCTL_FAIL_SIZE:-} && ${3:-} == "$HYPRCTL_FAIL_SIZE" ]]; then
      exit 1
    fi
    ;;
esac
""",
        encoding="utf-8",
    )
    fake.chmod(0o755)
    runtime = tmp_path / "runtime"
    runtime.mkdir()
    env = os.environ.copy()
    env.update(
        PATH=f"{fake_bin}:{env['PATH']}",
        XDG_RUNTIME_DIR=str(runtime),
        HYPRCTL_LOG=str(log),
    )
    return env, runtime, log


def invocations(log):
    if not log.exists():
        return []
    return [
        [part.decode() for part in line.split(b"\0") if part]
        for line in log.read_bytes().splitlines()
        if line
    ]


def calls(log):
    return [argument for invocation in invocations(log) for argument in invocation]


def run_helper(env, *arguments, check=True):
    return subprocess.run(
        [str(HELPER), *map(str, arguments)],
        env=env,
        check=check,
        capture_output=True,
        text=True,
        timeout=5,
    )


def runtime_root(runtime):
    return runtime / f"jobo-big-cheese-{os.getuid()}"


def marker_path(runtime):
    return runtime_root(runtime) / "pulse.state"


def mask_marker_path(runtime):
    return runtime_root(runtime) / "mask.state"


def outcome_path(runtime):
    return runtime_root(runtime) / "pulse.outcome"


def write_marker(runtime, **overrides):
    values = {
        "version": "1",
        "pid": str(os.getpid()),
        "theme_b64": base64.b64encode(b"Stale Theme").decode(),
        "baseline_size": "24",
        "peak_size": "72",
        "deadline_ms": "1",
    }
    values.update({key: str(value) for key, value in overrides.items()})
    marker = marker_path(runtime)
    marker.parent.mkdir(mode=0o700, exist_ok=True)
    marker.write_text(
        "".join(f"{key}={value}\n" for key, value in values.items()),
        encoding="utf-8",
    )
    return marker


def test_mask_hides_native_cursor_then_restores_original_visibility(helper_env):
    env, runtime, log = helper_env
    run_helper(env, "mask", 20)

    lua = "hl.dsp.cursor.move({ x = -1920, y = 360 })"
    assert invocations(log) == [
        ["-j", "getoption", "cursor:invisible"],
        ["eval", "hl.config { cursor = { invisible = true } }"],
        ["cursorpos"],
        ["dispatch", lua],
        ["eval", "hl.config { cursor = { invisible = false } }"],
        ["cursorpos"],
        ["dispatch", lua],
    ]
    assert not (runtime_root(runtime) / "mask.state").exists()


def test_deleted_mask_marker_still_restores_process_baseline(helper_env):
    env, runtime, log = helper_env
    process = subprocess.Popen(
        [str(HELPER), "mask", "250"],
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    wait_until(
        lambda: mask_marker_path(runtime).exists()
        and ["eval", "hl.config { cursor = { invisible = true } }"]
        in invocations(log)
    )
    mask_marker_path(runtime).unlink()

    assert process.wait(timeout=3) != 0
    assert [call for call in invocations(log) if call[0] == "eval"][-1] == [
        "eval", "hl.config { cursor = { invisible = false } }"
    ]


def test_mask_preserves_an_already_hidden_cursor(helper_env):
    env, _, log = helper_env
    env["HYPRCTL_CURSOR_INVISIBLE"] = "true"
    run_helper(env, "mask", 20)

    assert [call for call in invocations(log) if call[0] == "eval"] == [
        ["eval", "hl.config { cursor = { invisible = true } }"],
        ["eval", "hl.config { cursor = { invisible = true } }"],
    ]


def test_pulse_enlarges_then_restores_with_theme_as_one_argument(helper_env):
    env, runtime, log = helper_env
    run_helper(env, "pulse", "Theme With Spaces", 24, 60, 20)

    assert invocations(log) == [
        ["setcursor", "Theme With Spaces", "60"],
        ["cursorpos"],
        ["dispatch", "hl.dsp.cursor.move({ x = -1920, y = 360 })"],
        ["setcursor", "Theme With Spaces", "24"],
        ["cursorpos"],
        ["dispatch", "hl.dsp.cursor.move({ x = -1920, y = 360 })"],
    ]
    assert not marker_path(runtime).exists()
    status = json.loads(run_helper(env, "status").stdout)
    assert status["state"] == "idle"
    assert status["outcome"] == "success"
    assert status["completedAtMs"] >= status["startedAtMs"] > 0


@pytest.mark.parametrize(
    "arguments",
    [
        ("pulse", "", 24, 60, 20),
        ("pulse", "default", "nope", 60, 20),
        ("pulse", "default", 24, 0, 20),
        ("pulse", "default", 24, 60, 0),
        ("pulse", "default", 24, 60, 60001),
        ("pulse", "default", "18446744073709551640", 60, 20),
        ("pulse", "default", 24, "18446744073709551688", 20),
        ("pulse", "default", 24, 60, "18446744073709611616"),
    ],
)
def test_invalid_arguments_are_rejected_before_hyprctl(helper_env, arguments):
    env, _, log = helper_env
    result = run_helper(env, *arguments, check=False)
    assert result.returncode != 0
    assert calls(log) == []


def test_marker_exists_during_pulse_and_disappears_after_restore(helper_env):
    env, runtime, log = helper_env
    process = subprocess.Popen(
        [str(HELPER), "pulse", "default", "24", "52", "250"],
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    marker = marker_path(runtime)
    wait_until(marker.exists)
    wait_until(lambda: len(invocations(log)) >= 3)
    status = json.loads(run_helper(env, "status").stdout)
    assert status["state"] == "active"
    assert status["baselineSize"] == 24
    recovery = json.loads(run_helper(env, "recover").stdout)
    assert recovery["state"] == "active"
    assert len(invocations(log)) == 3
    assert process.wait(timeout=3) == 0
    assert not marker.exists()


def test_term_restores_through_exit_trap(helper_env):
    env, runtime, log = helper_env
    process = subprocess.Popen(
        [str(HELPER), "pulse", "default", "24", "64", "2000"],
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    wait_until(lambda: marker_path(runtime).exists() and len(invocations(log)) >= 3)
    process.send_signal(signal.SIGTERM)
    assert process.wait(timeout=3) != 0
    assert invocations(log)[-3:] == [
        ["setcursor", "default", "24"],
        ["cursorpos"],
        ["dispatch", "hl.dsp.cursor.move({ x = -1920, y = 360 })"],
    ]
    assert not marker_path(runtime).exists()


def test_second_signal_does_not_interrupt_restoration(helper_env):
    env, runtime, log = helper_env
    sleeping_env = env.copy()
    sleeping_env["HYPRCTL_SLEEP_SIZE"] = "24"
    process = subprocess.Popen(
        [str(HELPER), "pulse", "default", "24", "64", "2000"],
        env=sleeping_env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    wait_until(lambda: marker_path(runtime).exists() and len(invocations(log)) >= 3)
    process.send_signal(signal.SIGTERM)
    wait_until(lambda: len(invocations(log)) >= 4, timeout=3.0)
    process.send_signal(signal.SIGHUP)

    assert process.wait(timeout=3) != 0
    assert invocations(log)[-3:] == [
        ["setcursor", "default", "24"],
        ["cursorpos"],
        ["dispatch", "hl.dsp.cursor.move({ x = -1920, y = 360 })"],
    ]
    assert not marker_path(runtime).exists()


def test_recover_restores_stale_marker_once_and_is_idempotent(helper_env):
    env, runtime, log = helper_env
    marker = write_marker(runtime)

    first = json.loads(run_helper(env, "recover").stdout)
    second = json.loads(run_helper(env, "recover").stdout)
    assert first == {"state": "idle", "recovered": True}
    assert second == {"state": "idle", "recovered": False}
    assert invocations(log) == [
        ["setcursor", "Stale Theme", "24"],
        ["cursorpos"],
        ["dispatch", "hl.dsp.cursor.move({ x = -1920, y = 360 })"],
    ]
    assert not marker.exists()


def test_concurrent_pulse_is_rejected_without_second_enlargement(helper_env):
    env, runtime, log = helper_env
    first = subprocess.Popen(
        [str(HELPER), "pulse", "default", "24", "58", "300"],
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    wait_until(lambda: marker_path(runtime).exists() and len(invocations(log)) >= 3)
    second = run_helper(env, "pulse", "default", 24, 70, 20, check=False)
    assert second.returncode != 0
    assert first.wait(timeout=3) == 0
    assert invocations(log) == [
        ["setcursor", "default", "58"],
        ["cursorpos"],
        ["dispatch", "hl.dsp.cursor.move({ x = -1920, y = 360 })"],
        ["setcursor", "default", "24"],
        ["cursorpos"],
        ["dispatch", "hl.dsp.cursor.move({ x = -1920, y = 360 })"],
    ]


def test_terminal_outcome_is_published_before_another_pulse_can_start(helper_env):
    env, runtime, log = helper_env
    fake_bin = Path(env["PATH"].split(os.pathsep, 1)[0])
    fake_date = fake_bin / "date"
    fake_date.write_text(
        """#!/usr/bin/env bash
set -euo pipefail
count=0
if [[ -f $DATE_CALL_COUNT_FILE ]]; then
  read -r count <"$DATE_CALL_COUNT_FILE"
fi
count=$((count + 1))
printf '%s\n' "$count" >"$DATE_CALL_COUNT_FILE"
if [[ $count == "$DATE_PAUSE_CALL" ]]; then
  : >"$DATE_PAUSE_READY"
  while [[ ! -e $DATE_PAUSE_RELEASE ]]; do sleep 0.01; done
fi
exec /usr/bin/date "$@"
""",
        encoding="utf-8",
    )
    fake_date.chmod(0o755)

    delayed_env = env.copy()
    delayed_env.update(
        DATE_CALL_COUNT_FILE=str(runtime / "date-count"),
        DATE_PAUSE_CALL="2",
        DATE_PAUSE_READY=str(runtime / "date-pause-ready"),
        DATE_PAUSE_RELEASE=str(runtime / "date-pause-release"),
    )
    ready = Path(delayed_env["DATE_PAUSE_READY"])
    release = Path(delayed_env["DATE_PAUSE_RELEASE"])
    first = subprocess.Popen(
        [str(HELPER), "pulse", "default", "24", "58", "20"],
        env=delayed_env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )

    try:
        wait_until(ready.exists, timeout=3.0)
        assert not marker_path(runtime).exists()
        second = run_helper(
            delayed_env, "pulse", "default", 24, 70, 20, check=False
        )
        assert second.returncode != 0
        assert "another cursor operation is active" in second.stderr
    finally:
        release.touch()

    assert first.wait(timeout=3) == 0
    status = json.loads(run_helper(env, "status").stdout)
    assert status["outcome"] == "success"
    assert [call for call in invocations(log) if call[0] == "setcursor"] == [
        ["setcursor", "default", "58"],
        ["setcursor", "default", "24"],
    ]


def test_failed_restoration_keeps_marker_for_later_recovery(helper_env):
    env, runtime, log = helper_env
    failing_env = env.copy()
    failing_env["HYPRCTL_FAIL_SIZE"] = "24"
    result = run_helper(
        failing_env, "pulse", "default", 24, 60, 20, check=False
    )
    assert result.returncode != 0
    assert marker_path(runtime).exists()

    recovered = json.loads(run_helper(env, "recover").stdout)
    assert recovered == {"state": "idle", "recovered": True}
    assert not marker_path(runtime).exists()
    assert invocations(log)[-3:] == [
        ["setcursor", "default", "24"],
        ["cursorpos"],
        ["dispatch", "hl.dsp.cursor.move({ x = -1920, y = 360 })"],
    ]


def test_enlargement_failure_records_failed_terminal_outcome(helper_env):
    env, runtime, log = helper_env
    failing_env = env.copy()
    failing_env["HYPRCTL_FAIL_SIZE"] = "60"

    result = run_helper(
        failing_env, "pulse", "default", 24, 60, 20, check=False
    )

    assert result.returncode != 0
    assert not marker_path(runtime).exists()
    status = json.loads(run_helper(env, "status").stdout)
    assert status["state"] == "idle"
    assert status["outcome"] == "failed"
    assert status["completedAtMs"] >= status["startedAtMs"] > 0
    assert invocations(log) == [
        ["setcursor", "default", "60"],
        ["setcursor", "default", "24"],
        ["cursorpos"],
        ["dispatch", "hl.dsp.cursor.move({ x = -1920, y = 360 })"],
    ]


@pytest.mark.parametrize(
    ("field", "value"),
    [
        ("pid", "0"),
        ("pid", "999999999999999999999"),
        ("baseline_size", "18446744073709551640"),
        ("peak_size", "18446744073709551688"),
        ("deadline_ms", "999999999999999999999999"),
        ("theme_b64", "A" * 4097),
    ],
)
def test_crafted_invalid_markers_are_rejected_without_hyprctl(
    helper_env, field, value
):
    env, runtime, log = helper_env
    write_marker(runtime, **{field: value})

    status = run_helper(env, "status", check=False)
    recovery = run_helper(env, "recover", check=False)

    assert status.returncode != 0
    assert json.loads(status.stdout) == {"state": "invalid"}
    assert recovery.returncode != 0
    assert json.loads(recovery.stdout) == {
        "state": "invalid",
        "recovered": False,
    }
    assert calls(log) == []


def test_lua_dispatch_uses_safe_legacy_fallback(helper_env):
    env, _, log = helper_env
    fallback_env = env.copy()
    fallback_env["HYPRCTL_FAIL_LUA_DISPATCH"] = "1"

    run_helper(fallback_env, "pulse", "default", 24, 60, 20)

    lua = "hl.dsp.cursor.move({ x = -1920, y = 360 })"
    assert invocations(log) == [
        ["setcursor", "default", "60"],
        ["cursorpos"],
        ["dispatch", lua],
        ["dispatch", "movecursor", "-1920", "360"],
        ["setcursor", "default", "24"],
        ["cursorpos"],
        ["dispatch", lua],
        ["dispatch", "movecursor", "-1920", "360"],
    ]


def test_malformed_cursor_position_fails_visible_pulse_and_recovers(helper_env):
    env, runtime, log = helper_env
    malformed_env = env.copy()
    malformed_env["HYPRCTL_CURSORPOS"] = "not coordinates"

    result = run_helper(
        malformed_env, "pulse", "default", 24, 60, 20, check=False
    )

    assert result.returncode != 0
    assert marker_path(runtime).exists()
    assert "outcome=failed" in outcome_path(runtime).read_text(encoding="utf-8")
    assert invocations(log) == [
        ["setcursor", "default", "60"],
        ["cursorpos"],
        ["setcursor", "default", "24"],
        ["cursorpos"],
    ]

    recovered = json.loads(run_helper(env, "recover").stdout)
    assert recovered == {"state": "idle", "recovered": True}
    assert not marker_path(runtime).exists()
    assert invocations(log)[-3:] == [
        ["setcursor", "default", "24"],
        ["cursorpos"],
        ["dispatch", "hl.dsp.cursor.move({ x = -1920, y = 360 })"],
    ]


def test_invalid_outcome_does_not_block_recovery_readiness(helper_env):
    env, runtime, log = helper_env
    root = runtime_root(runtime)
    root.mkdir(mode=0o700)
    outcome_path(runtime).write_text("invalid\n", encoding="utf-8")

    recovered = json.loads(run_helper(env, "recover").stdout)

    assert recovered == {"state": "idle", "recovered": False}
    assert not outcome_path(runtime).exists()
    assert calls(log) == []


@pytest.mark.parametrize(
    "child_name", ["pulse.state", "pulse.outcome", "pulse.lock", "mask.state"]
)
def test_symlinked_runtime_child_files_are_rejected(helper_env, child_name):
    env, runtime, log = helper_env
    root = runtime_root(runtime)
    root.mkdir(mode=0o700)
    target = runtime / "outside"
    target.write_text("untouched", encoding="utf-8")
    (root / child_name).symlink_to(target)

    result = run_helper(env, "status", check=False)

    assert result.returncode != 0
    assert target.read_text(encoding="utf-8") == "untouched"
    assert calls(log) == []
