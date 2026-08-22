#!/usr/bin/env python3
"""Read Big Cheese's tiny TOML config and emit normalized JSON."""

from __future__ import annotations

import json
import sys
import tomllib
from pathlib import Path
from typing import Any

DEFAULTS = {
    "start_enabled": True,
    "shake_effort": "normal",
    "pointer_size": 72,
    "big_for_seconds": 2.0,
}

SHAKE_PRESETS = {
    "gentle": {
        "minimumStep": 9,
        "minimumReversals": 2,
        "minimumHorizontalTravel": 240,
        "armingSpeed": 320,
    },
    "normal": {
        "minimumStep": 14,
        "minimumReversals": 3,
        "minimumHorizontalTravel": 360,
        "armingSpeed": 450,
    },
    "workout": {
        "minimumStep": 18,
        "minimumReversals": 4,
        "minimumHorizontalTravel": 520,
        "armingSpeed": 600,
    },
}


def _number(value: Any) -> float | None:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    return float(value)


def read_config(path: Path) -> dict[str, Any]:
    errors: list[str] = []
    values = dict(DEFAULTS)

    try:
        loaded = tomllib.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, tomllib.TOMLDecodeError) as error:
        loaded = {}
        errors.append(f"cheese.toml: {error}")

    unknown = sorted(set(loaded) - set(DEFAULTS))
    if unknown:
        errors.append("unknown setting" + ("s" if len(unknown) > 1 else "") + ": " + ", ".join(unknown))

    enabled = loaded.get("start_enabled", DEFAULTS["start_enabled"])
    if isinstance(enabled, bool):
        values["start_enabled"] = enabled
    else:
        errors.append("start_enabled must be true or false")

    effort = loaded.get("shake_effort", DEFAULTS["shake_effort"])
    if isinstance(effort, str) and effort in SHAKE_PRESETS:
        values["shake_effort"] = effort
    else:
        errors.append("shake_effort must be gentle, normal, or workout")

    pointer_size = _number(loaded.get("pointer_size", DEFAULTS["pointer_size"]))
    if pointer_size is not None and pointer_size.is_integer() and 48 <= pointer_size <= 128:
        values["pointer_size"] = int(pointer_size)
    else:
        errors.append("pointer_size must be a whole number from 48 to 128")

    seconds = _number(loaded.get("big_for_seconds", DEFAULTS["big_for_seconds"]))
    if seconds is not None and 0.5 <= seconds <= 5.0:
        values["big_for_seconds"] = seconds
    else:
        errors.append("big_for_seconds must be from 0.5 to 5.0")

    return {
        "startEnabled": values["start_enabled"],
        "shakeEffort": values["shake_effort"],
        "pointerSize": values["pointer_size"],
        "durationMs": round(values["big_for_seconds"] * 1000),
        "detector": SHAKE_PRESETS[values["shake_effort"]],
        "error": "; ".join(errors),
    }


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: cheese-config.py PATH", file=sys.stderr)
        return 2
    print(json.dumps(read_config(Path(sys.argv[1])), separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
