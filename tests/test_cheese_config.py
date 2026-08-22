import json
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
READER = ROOT / "scripts" / "cheese-config.py"


def read_config(path: Path) -> dict:
    result = subprocess.run(
        [str(READER), str(path)],
        check=True,
        capture_output=True,
        text=True,
    )
    return json.loads(result.stdout)


def test_shipped_config_uses_normal_defaults():
    payload = read_config(ROOT / "cheese.toml")

    assert payload == {
        "startEnabled": True,
        "shakeEffort": "normal",
        "pointerSize": 72,
        "durationMs": 2000,
        "detector": {
            "minimumStep": 14,
            "minimumReversals": 3,
            "minimumHorizontalTravel": 360,
            "armingSpeed": 450,
        },
        "error": "",
    }


def test_custom_config_selects_clear_user_facing_settings(tmp_path):
    config = tmp_path / "cheese.toml"
    config.write_text(
        "start_enabled = false\n"
        'shake_effort = "gentle"\n'
        "pointer_size = 96\n"
        "big_for_seconds = 3.5\n",
        encoding="utf-8",
    )

    payload = read_config(config)

    assert payload["startEnabled"] is False
    assert payload["shakeEffort"] == "gentle"
    assert payload["pointerSize"] == 96
    assert payload["durationMs"] == 3500
    assert payload["detector"]["minimumReversals"] == 2
    assert payload["error"] == ""


def test_bad_values_fall_back_safely_and_explain_the_problem(tmp_path):
    config = tmp_path / "cheese.toml"
    config.write_text(
        "start_enabled = 1\n"
        'shake_effort = "gouda"\n'
        "pointer_size = 400\n"
        "big_for_seconds = 20\n"
        "mystery_rind = true\n",
        encoding="utf-8",
    )

    payload = read_config(config)

    assert payload["startEnabled"] is True
    assert payload["shakeEffort"] == "normal"
    assert payload["pointerSize"] == 72
    assert payload["durationMs"] == 2000
    assert "unknown setting: mystery_rind" in payload["error"]
    assert "shake_effort must be gentle, normal, or workout" in payload["error"]
