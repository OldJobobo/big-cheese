import json
import os
from pathlib import Path
import struct
import subprocess


ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / "scripts" / "cursor-palette.py"
IMAGE_TYPE = 0xFFFD0002


def write_xcursor(path, size, pixels):
    width = height = size
    assert len(pixels) == width * height
    toc_position = 28
    header = struct.pack("<4sIII", b"Xcur", 16, 0x00010000, 1)
    toc = struct.pack("<III", IMAGE_TYPE, size, toc_position)
    chunk = struct.pack(
        "<9I", 36, IMAGE_TYPE, size, 1, width, height, 1, 1, 0
    )
    path.parent.mkdir(parents=True)
    path.write_bytes(header + toc + chunk + struct.pack(f"<{len(pixels)}I", *pixels))


def run_palette(tmp_path, theme):
    env = os.environ.copy()
    env.update(
        {
            "HOME": str(tmp_path / "home"),
            "XDG_DATA_HOME": str(tmp_path / "data"),
            "XDG_DATA_DIRS": str(tmp_path / "empty"),
        }
    )
    result = subprocess.run(
        [str(HELPER), theme, "72"],
        env=env,
        text=True,
        capture_output=True,
        check=True,
    )
    return json.loads(result.stdout)


def test_extracts_fill_and_outline_from_active_theme(tmp_path):
    fill = 0xFF181818
    stroke = 0xFFFFFFFF
    transparent = 0x00000000
    pixels = [fill] * 90 + [stroke] * 35 + [transparent] * 19
    cursor = tmp_path / "data/icons/test-cursor/cursors/default"
    write_xcursor(cursor, 12, pixels)

    payload = run_palette(tmp_path, "test-cursor")

    assert payload == {
        "fill": "#181818",
        "stroke": "#ffffff",
        "detected": True,
        "theme": "test-cursor",
    }


def test_falls_back_safely_when_theme_has_no_xcursor_asset(tmp_path):
    payload = run_palette(tmp_path, "missing-cursor")

    assert payload["fill"] == "#111318"
    assert payload["stroke"] == "#f8fafc"
    assert payload["detected"] is False
