#!/usr/bin/env python3
"""Extract dominant fill and outline colors from an Xcursor arrow."""

from __future__ import annotations

import configparser
import json
import os
from pathlib import Path
import struct
import sys
from collections import Counter

IMAGE_TYPE = 0xFFFD0002
FALLBACK = {"fill": "#111318", "stroke": "#f8fafc", "detected": False}
CURSOR_NAMES = ("default", "left_ptr", "arrow")


def icon_roots() -> list[Path]:
    home = Path.home()
    roots = [Path(os.environ.get("XDG_DATA_HOME", home / ".local/share")) / "icons"]
    roots.append(home / ".icons")
    for value in os.environ.get("XDG_DATA_DIRS", "/usr/local/share:/usr/share").split(":"):
        if value:
            roots.append(Path(value) / "icons")
    return list(dict.fromkeys(roots))


def theme_directories(theme: str) -> list[Path]:
    return [root / theme for root in icon_roots() if (root / theme).is_dir()]


def inherited_themes(directory: Path) -> list[str]:
    parser = configparser.ConfigParser(interpolation=None, strict=False)
    try:
        parser.read(directory / "index.theme", encoding="utf-8")
        raw = parser.get("Icon Theme", "Inherits", fallback="")
    except (OSError, configparser.Error):
        return []
    return [name.strip() for name in raw.replace(";", ",").split(",") if name.strip()]


def find_cursor(theme: str) -> tuple[Path | None, str]:
    queue = [theme or "default"]
    seen: set[str] = set()
    while queue:
        name = queue.pop(0)
        if not name or name in seen or len(seen) >= 32:
            continue
        seen.add(name)
        directories = theme_directories(name)
        for directory in directories:
            for cursor_name in CURSOR_NAMES:
                candidate = directory / "cursors" / cursor_name
                if candidate.exists():
                    return candidate.resolve(), name
        for directory in directories:
            queue.extend(inherited_themes(directory))

    # Bare "default" themes commonly rely on the toolkit's Adwaita fallback.
    if "Adwaita" not in seen:
        return find_cursor("Adwaita")
    return None, theme or "default"


def image_chunks(data: bytes) -> list[tuple[int, list[int]]]:
    if len(data) < 16 or data[:4] != b"Xcur":
        return []
    _, header_size, _, toc_count = struct.unpack_from("<4sIII", data)
    if header_size < 16 or toc_count > 4096 or header_size + toc_count * 12 > len(data):
        return []

    chunks: list[tuple[int, list[int]]] = []
    for index in range(toc_count):
        chunk_type, subtype, position = struct.unpack_from(
            "<III", data, header_size + index * 12
        )
        if chunk_type != IMAGE_TYPE or position + 36 > len(data):
            continue
        values = struct.unpack_from("<9I", data, position)
        chunk_header, actual_type, actual_subtype, _, width, height, *_ = values
        pixel_count = width * height
        pixel_start = position + chunk_header
        pixel_end = pixel_start + pixel_count * 4
        if (
            actual_type != IMAGE_TYPE
            or actual_subtype != subtype
            or chunk_header < 36
            or width == 0
            or height == 0
            or pixel_count > 16_777_216
            or pixel_end > len(data)
        ):
            continue
        pixels = list(struct.unpack_from(f"<{pixel_count}I", data, pixel_start))
        chunks.append((subtype, pixels))
    return chunks


def quantize(channel: int) -> int:
    return min(255, ((channel + 4) // 8) * 8)


def palette(pixels: list[int]) -> tuple[str, str] | None:
    colors: Counter[tuple[int, int, int]] = Counter()
    for pixel in pixels:
        alpha = pixel >> 24
        if alpha < 128:
            continue
        rgb = (
            quantize((pixel >> 16) & 0xFF),
            quantize((pixel >> 8) & 0xFF),
            quantize(pixel & 0xFF),
        )
        colors[rgb] += alpha
    if not colors:
        return None

    fill = colors.most_common(1)[0][0]
    candidates = []
    for color, weight in colors.items():
        distance_squared = sum((color[i] - fill[i]) ** 2 for i in range(3))
        if distance_squared >= 80**2:
            candidates.append((weight * distance_squared, weight, color))
    if not candidates:
        return None
    stroke = max(candidates)[2]
    to_hex = lambda color: "#" + "".join(f"{channel:02x}" for channel in color)
    return to_hex(fill), to_hex(stroke)


def main() -> int:
    if len(sys.argv) not in (2, 3):
        print("usage: cursor-palette.py <theme> [target-size]", file=sys.stderr)
        return 2
    theme = sys.argv[1].strip() or "default"
    if len(theme) > 512 or "/" in theme or "\x00" in theme:
        print(json.dumps(FALLBACK))
        return 1
    try:
        target_size = max(1, min(512, int(sys.argv[2]))) if len(sys.argv) == 3 else 72
    except ValueError:
        print(json.dumps(FALLBACK))
        return 2

    path, resolved_theme = find_cursor(theme)
    if path is None:
        print(json.dumps({**FALLBACK, "theme": theme}))
        return 0
    try:
        chunks = image_chunks(path.read_bytes())
    except OSError:
        chunks = []
    if not chunks:
        print(json.dumps({**FALLBACK, "theme": resolved_theme}))
        return 0

    _, pixels = min(chunks, key=lambda chunk: (abs(chunk[0] - target_size), -chunk[0]))
    detected = palette(pixels)
    if detected is None:
        print(json.dumps({**FALLBACK, "theme": resolved_theme}))
        return 0
    fill, stroke = detected
    print(
        json.dumps(
            {
                "fill": fill,
                "stroke": stroke,
                "detected": True,
                "theme": resolved_theme,
            },
            separators=(",", ":"),
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
