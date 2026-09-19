import json
import subprocess

import pytest
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
        "shakeEnabled": True,
        "growEnabled": False,
        "shakeEffort": "normal",
        "pointerSize": 72,
        "durationMs": 2000,
        "mouseTrail": "reveal",
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
        "shake_enabled = false\n"
        "grow = true\n"
        'shake_effort = "gentle"\n'
        "pointer_size = 96\n"
        "big_for_seconds = 3.5\n"
        'mouse_trail = "always"\n',
        encoding="utf-8",
    )

    payload = read_config(config)

    assert payload["startEnabled"] is False
    assert payload["shakeEnabled"] is False
    assert payload["growEnabled"] is True
    assert payload["shakeEffort"] == "gentle"
    assert payload["pointerSize"] == 96
    assert payload["durationMs"] == 3500
    assert payload["mouseTrail"] == "always"
    assert payload["detector"]["minimumReversals"] == 2
    assert payload["error"] == ""


@pytest.mark.parametrize("start_enabled", [True, False])
@pytest.mark.parametrize("shake_enabled", [True, False])
def test_shake_setting_is_independent_of_master_switch(tmp_path, start_enabled, shake_enabled):
    config = tmp_path / "cheese.toml"
    config.write_text(
        f"start_enabled = {str(start_enabled).lower()}\n"
        f"shake_enabled = {str(shake_enabled).lower()}\n",
        encoding="utf-8",
    )
    payload = read_config(config)
    assert payload["startEnabled"] is start_enabled
    assert payload["shakeEnabled"] is shake_enabled
    assert payload["error"] == ""


def test_omitted_shake_setting_preserves_existing_behavior(tmp_path):
    config = tmp_path / "cheese.toml"
    config.write_text("start_enabled = true\n", encoding="utf-8")
    payload = read_config(config)
    assert payload["shakeEnabled"] is True
    assert payload["error"] == ""


@pytest.mark.parametrize("value", ['"false"', "0", "1", "[]", "{}"])
def test_invalid_shake_setting_falls_back_with_error(tmp_path, value):
    config = tmp_path / "cheese.toml"
    config.write_text(f"shake_enabled = {value}\n", encoding="utf-8")
    payload = read_config(config)
    assert payload["shakeEnabled"] is True
    assert payload["error"] == "shake_enabled must be true or false"


def test_bad_values_fall_back_safely_and_explain_the_problem(tmp_path):
    config = tmp_path / "cheese.toml"
    config.write_text(
        "start_enabled = 1\n"
        'grow = "huge"\n'
        'shake_effort = "gouda"\n'
        "pointer_size = 400\n"
        "big_for_seconds = 20\n"
        'mouse_trail = "sparkles"\n'
        "mystery_rind = true\n",
        encoding="utf-8",
    )

    payload = read_config(config)

    assert payload["startEnabled"] is True
    assert payload["growEnabled"] is False
    assert payload["shakeEffort"] == "normal"
    assert payload["pointerSize"] == 72
    assert payload["durationMs"] == 2000
    assert payload["mouseTrail"] == "reveal"
    assert "unknown setting: mystery_rind" in payload["error"]
    assert "grow must be true or false" in payload["error"]
    assert "mouse_trail must be off, reveal, or always" in payload["error"]
    assert "shake_effort must be gentle, normal, or workout" in payload["error"]
