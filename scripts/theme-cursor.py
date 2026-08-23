#!/usr/bin/env python3
"""Build, apply, and restore a temporary Omarchy-colored Xcursor theme."""

from __future__ import annotations

import configparser
import fcntl
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import sys
import tomllib
from typing import Any

IMAGE_TYPE = 0xFFFD0002
RUNTIME_THEME = "jobo-big-cheese-runtime"
CURSOR_NAMES = ("default", "left_ptr", "arrow")


def icon_roots() -> list[Path]:
    override = os.environ.get("BIG_CHEESE_ICON_ROOT")
    if override:
        return [Path(override)]
    home = Path.home()
    roots = [Path(os.environ.get("XDG_DATA_HOME", home / ".local/share")) / "icons"]
    roots.append(home / ".icons")
    for value in os.environ.get("XDG_DATA_DIRS", "/usr/local/share:/usr/share").split(":"):
        if value:
            roots.append(Path(value) / "icons")
    return list(dict.fromkeys(roots))


def runtime_icon_root() -> Path:
    override = os.environ.get("BIG_CHEESE_RUNTIME_ICON_ROOT")
    if override:
        return Path(override)
    return icon_roots()[0]


def state_path() -> Path:
    override = os.environ.get("BIG_CHEESE_CURSOR_STATE")
    if override:
        return Path(override)
    runtime = Path(os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}"))
    return runtime / "jobo-big-cheese" / "cursor-theme.json"


def runtime_theme_path() -> Path:
    override = os.environ.get("BIG_CHEESE_RUNTIME_THEME_PATH")
    if override:
        return Path(override)
    return state_path().parent / "cursor-theme"


def remove_path(path: Path) -> None:
    if path.is_symlink() or path.is_file():
        path.unlink(missing_ok=True)
    elif path.is_dir():
        shutil.rmtree(path)


def inherited_themes(directory: Path) -> list[str]:
    parser = configparser.ConfigParser(interpolation=None, strict=False)
    try:
        parser.read(directory / "index.theme", encoding="utf-8")
        raw = parser.get("Icon Theme", "Inherits", fallback="")
    except (OSError, configparser.Error):
        return []
    return [name.strip() for name in raw.replace(";", ",").split(",") if name.strip()]


def resolve_theme(theme: str) -> tuple[Path, str]:
    queue = [theme or "default"]
    seen: set[str] = set()
    while queue:
        name = queue.pop(0)
        if not name or name in seen or len(seen) >= 32:
            continue
        seen.add(name)
        for root in icon_roots():
            directory = root / name
            cursors = directory / "cursors"
            if cursors.is_dir() and any((cursors / cursor).exists() for cursor in CURSOR_NAMES):
                return directory, name
            if directory.is_dir():
                queue.extend(inherited_themes(directory))
    if "Adwaita" not in seen:
        return resolve_theme("Adwaita")
    raise FileNotFoundError(f"cursor theme not found: {theme or 'default'}")


def omarchy_colors() -> tuple[str, str]:
    override = os.environ.get("BIG_CHEESE_COLORS_FILE")
    path = Path(override) if override else (
        Path.home() / ".local/state/omarchy/current/theme/colors.toml"
    )
    try:
        payload = tomllib.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, tomllib.TOMLDecodeError) as error:
        raise ValueError(f"Omarchy colors could not be read: {error}") from error
    fill = str(payload.get("accent") or payload.get("cursor") or "")
    outline = str(payload.get("background") or "")
    parse_hex(fill)
    parse_hex(outline)
    return fill, outline


def parse_hex(value: str) -> tuple[int, int, int]:
    raw = value.strip().removeprefix("#")
    if len(raw) != 6 or any(character not in "0123456789abcdefABCDEF" for character in raw):
        raise ValueError("colors must use six-digit hex notation")
    return tuple(int(raw[offset : offset + 2], 16) for offset in (0, 2, 4))


def image_ranges(data: bytes) -> list[tuple[int, int]]:
    if len(data) < 16 or data[:4] != b"Xcur":
        return []
    _, header_size, _, toc_count = struct.unpack_from("<4sIII", data)
    if header_size < 16 or toc_count > 4096 or header_size + toc_count * 12 > len(data):
        return []
    ranges: list[tuple[int, int]] = []
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
        ranges.append((pixel_start, pixel_count))
    return ranges


def recolor_cursor(
    data: bytes,
    fill: tuple[int, int, int],
    outline: tuple[int, int, int],
    cache: dict[int, int] | None = None,
) -> tuple[bytes, int]:
    ranges = image_ranges(data)
    if not ranges:
        return data, 0
    output = bytearray(data)
    replacements = cache if cache is not None else {}
    changed = 0
    for pixel_start, pixel_count in ranges:
        pixels = memoryview(output)[pixel_start : pixel_start + pixel_count * 4].cast("I")
        for index, pixel in enumerate(pixels):
            alpha = (pixel >> 24) & 0xFF
            if alpha == 0:
                continue
            replacement = replacements.get(pixel)
            if replacement is None:
                red = (pixel >> 16) & 0xFF
                green = (pixel >> 8) & 0xFF
                blue = pixel & 0xFF
                # Xcursor surfaces are premultiplied ARGB. Integer luminance
                # plus a shared source-pixel cache keeps a full theme rebuild
                # quick without adding a runtime image dependency.
                premultiplied_luminance = (red * 54 + green * 183 + blue * 19) // 256
                luminance = min(255, premultiplied_luminance * 255 // alpha)
                mapped = [
                    (fill[channel] * (255 - luminance) + outline[channel] * luminance)
                    * alpha
                    // 65025
                    for channel in range(3)
                ]
                replacement = (
                    (alpha << 24)
                    | (mapped[0] << 16)
                    | (mapped[1] << 8)
                    | mapped[2]
                )
                replacements[pixel] = replacement
            pixels[index] = replacement
            changed += 1
    return bytes(output), changed


def build_theme(source: Path, destination: Path, fill_hex: str, outline_hex: str) -> dict[str, Any]:
    fill = parse_hex(fill_hex)
    outline = parse_hex(outline_hex)
    source_cursors = source / "cursors"
    if not source_cursors.is_dir():
        raise FileNotFoundError(f"cursor directory not found: {source_cursors}")
    if destination.exists() or destination.is_symlink():
        shutil.rmtree(destination)
    shutil.copytree(source_cursors, destination / "cursors", symlinks=True)
    files = 0
    pixels = 0
    replacements: dict[int, int] = {}
    for cursor in (destination / "cursors").iterdir():
        if cursor.is_symlink() or not cursor.is_file():
            continue
        original = cursor.read_bytes()
        recolored, changed = recolor_cursor(original, fill, outline, replacements)
        if changed == 0:
            continue
        cursor.write_bytes(recolored)
        files += 1
        pixels += changed
    if files == 0:
        raise RuntimeError("source theme contains no readable Xcursor images")
    (destination / "index.theme").write_text(
        "[Icon Theme]\n"
        "Name=Big Cheese Runtime\n"
        "Comment=Temporary Omarchy-colored cursor theme\n"
        f"Inherits={source.name}\n",
        encoding="utf-8",
    )
    return {"files": files, "pixels": pixels}


def read_state() -> dict[str, Any] | None:
    path = state_path()
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError):
        return None
    return payload if isinstance(payload, dict) else None


def write_state(payload: dict[str, Any]) -> None:
    path = state_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(".tmp")
    temporary.write_text(json.dumps(payload, separators=(",", ":")) + "\n", encoding="utf-8")
    temporary.chmod(0o600)
    os.replace(temporary, path)


def refresh_cursor_image(executable: str) -> None:
    try:
        position = subprocess.run(
            [executable, "-j", "cursorpos"],
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            timeout=2,
        )
        payload = json.loads(position.stdout) if position.returncode == 0 else {}
        x = payload.get("x")
        y = payload.get("y")
        if isinstance(x, bool) or isinstance(y, bool) or not isinstance(x, (int, float)) or not isinstance(y, (int, float)):
            return
        x = round(x)
        y = round(y)
        dispatch = subprocess.run(
            [executable, "dispatch", f"hl.dsp.cursor.move({{ x = {x}, y = {y} }})"],
            check=False,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=2,
        )
        if dispatch.returncode != 0:
            subprocess.run(
                [executable, "dispatch", "movecursor", str(x), str(y)],
                check=False,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                timeout=2,
            )
    except (OSError, ValueError, json.JSONDecodeError, subprocess.SubprocessError):
        return


def set_cursor(theme: str, size: int) -> None:
    executable = os.environ.get("BIG_CHEESE_HYPRCTL", "hyprctl")
    completed = subprocess.run(
        [executable, "setcursor", theme, str(size)],
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=3,
    )
    if completed.returncode != 0:
        message = completed.stderr.strip() or completed.stdout.strip() or "hyprctl setcursor failed"
        raise RuntimeError(message)
    refresh_cursor_image(executable)


def apply_theme(fill: str, outline: str, baseline_theme: str, baseline_size: int) -> dict[str, Any]:
    if baseline_size < 1 or baseline_size > 512:
        raise ValueError("cursor size must be from 1 to 512")
    existing = read_state()
    if existing:
        baseline_theme = str(existing.get("baselineTheme") or baseline_theme)
        baseline_size = int(existing.get("baselineSize") or baseline_size)
        source_name = str(existing.get("sourceTheme") or baseline_theme)
    else:
        source_name = baseline_theme
    if baseline_theme == RUNTIME_THEME:
        raise ValueError("runtime theme cannot be used as the baseline")
    source, resolved_source = resolve_theme(source_name)
    root = runtime_icon_root()
    root.mkdir(parents=True, exist_ok=True)
    target = root / RUNTIME_THEME
    theme_store = runtime_theme_path()
    theme_store.parent.mkdir(parents=True, exist_ok=True)
    staging = theme_store.parent / f".cursor-theme.{os.getpid()}.tmp"
    temporary_link = root / f".{RUNTIME_THEME}.{os.getpid()}.tmp"
    try:
        stats = build_theme(source, staging, fill, outline)
        remove_path(theme_store)
        os.replace(staging, theme_store)
        remove_path(temporary_link)
        temporary_link.symlink_to(theme_store, target_is_directory=True)
        remove_path(target)
        os.replace(temporary_link, target)
        state = {
            "version": 1,
            "baselineTheme": baseline_theme,
            "baselineSize": baseline_size,
            "sourceTheme": resolved_source,
            "fill": fill,
            "outline": outline,
            "themePath": str(theme_store),
            "linkPath": str(target),
        }
        write_state(state)
        try:
            # Hyprland and client toolkits may retain surfaces when a theme is
            # rebuilt under the same name. Bounce through the recorded baseline
            # so a palette change always creates a fresh cursor manager.
            if existing:
                set_cursor(baseline_theme, baseline_size)
            set_cursor(RUNTIME_THEME, baseline_size)
        except Exception:
            if not existing:
                state_path().unlink(missing_ok=True)
                remove_path(target)
                remove_path(theme_store)
            raise
        return {"active": True, "theme": RUNTIME_THEME, **state, **stats}
    finally:
        remove_path(staging)
        remove_path(temporary_link)


def restore_theme() -> dict[str, Any]:
    state = read_state()
    target = runtime_icon_root() / RUNTIME_THEME
    theme_store = runtime_theme_path()
    if not state:
        remove_path(target)
        remove_path(theme_store)
        return {"active": False, "restored": False}
    baseline_theme = str(state.get("baselineTheme") or "default")
    baseline_size = int(state.get("baselineSize") or 24)
    set_cursor(baseline_theme, baseline_size)
    remove_path(target)
    remove_path(theme_store)
    state_path().unlink(missing_ok=True)
    return {
        "active": False,
        "restored": True,
        "theme": baseline_theme,
        "size": baseline_size,
    }


def status() -> dict[str, Any]:
    state = read_state()
    return {
        "active": state is not None,
        "state": state or {},
        "themePresent": (runtime_icon_root() / RUNTIME_THEME).is_dir(),
        "runtimeFilesPresent": runtime_theme_path().is_dir(),
    }


def locked(operation):
    lock = state_path().with_suffix(".lock")
    lock.parent.mkdir(parents=True, exist_ok=True)
    with lock.open("a+", encoding="utf-8") as handle:
        fcntl.flock(handle.fileno(), fcntl.LOCK_EX)
        return operation()


def usage() -> str:
    return (
        "usage: theme-cursor.py apply FILL OUTLINE BASELINE SIZE | "
        "apply-omarchy [BASELINE SIZE] | restore | status"
    )


def main() -> int:
    if len(sys.argv) < 2:
        print(usage(), file=sys.stderr)
        return 2
    action = sys.argv[1]
    try:
        if action == "apply" and len(sys.argv) == 6:
            payload = locked(lambda: apply_theme(sys.argv[2], sys.argv[3], sys.argv[4], int(sys.argv[5])))
        elif action == "apply-omarchy" and len(sys.argv) in (2, 4):
            fill, outline = omarchy_colors()
            baseline = sys.argv[2] if len(sys.argv) == 4 else "default"
            size = int(sys.argv[3]) if len(sys.argv) == 4 else 24
            payload = locked(lambda: apply_theme(fill, outline, baseline, size))
        elif action == "restore" and len(sys.argv) == 2:
            payload = locked(restore_theme)
        elif action == "status" and len(sys.argv) == 2:
            payload = status()
        else:
            print(usage(), file=sys.stderr)
            return 2
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        print(json.dumps({"ok": False, "error": str(error)}, separators=(",", ":")))
        return 1
    print(json.dumps({"ok": True, **payload}, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
