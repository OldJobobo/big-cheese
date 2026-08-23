import importlib.util
import json
import os
from pathlib import Path
import stat
import struct


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "theme-cursor.py"
IMAGE_TYPE = 0xFFFD0002


def load_module():
    spec = importlib.util.spec_from_file_location("theme_cursor", SCRIPT)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def xcursor_fixture(pixels=(0xFF000000, 0xFFFFFFFF)) -> bytes:
    header_size = 16
    position = header_size + 12
    header = struct.pack("<4sIII", b"Xcur", header_size, 0x00010000, 1)
    toc = struct.pack("<III", IMAGE_TYPE, 24, position)
    chunk = struct.pack(
        "<9I",
        36,
        IMAGE_TYPE,
        24,
        1,
        len(pixels),
        1,
        1,
        0,
        0,
    )
    return header + toc + chunk + struct.pack(f"<{len(pixels)}I", *pixels)


def configure_runtime(monkeypatch, tmp_path):
    icon_root = tmp_path / "icons"
    state = tmp_path / "runtime" / "cursor-theme.json"
    command_log = tmp_path / "hyprctl.log"
    hyprctl = tmp_path / "hyprctl"
    hyprctl.write_text(
        "#!/bin/sh\n"
        "printf '%s\\n' \"$*\" >> \"$BIG_CHEESE_TEST_LOG\"\n"
        "if [ \"$1\" = -j ] && [ \"$2\" = cursorpos ]; then\n"
        "  printf '%s\\n' '{\"x\":10,\"y\":20}'\n"
        "fi\n",
        encoding="utf-8",
    )
    hyprctl.chmod(hyprctl.stat().st_mode | stat.S_IXUSR)
    monkeypatch.setenv("BIG_CHEESE_ICON_ROOT", str(icon_root))
    monkeypatch.setenv("BIG_CHEESE_RUNTIME_ICON_ROOT", str(icon_root))
    monkeypatch.setenv("BIG_CHEESE_CURSOR_STATE", str(state))
    monkeypatch.setenv("BIG_CHEESE_HYPRCTL", str(hyprctl))
    monkeypatch.setenv("BIG_CHEESE_TEST_LOG", str(command_log))
    return icon_root, state, command_log


def test_omarchy_colors_use_accent_and_background(monkeypatch, tmp_path):
    module = load_module()
    colors = tmp_path / "colors.toml"
    colors.write_text(
        'accent = "#13c1dc"\nbackground = "#061221"\n',
        encoding="utf-8",
    )
    monkeypatch.setenv("BIG_CHEESE_COLORS_FILE", str(colors))

    assert module.omarchy_colors() == ("#13c1dc", "#061221")


def test_recolor_cursor_preserves_container_and_maps_fill_and_outline():
    module = load_module()
    source = xcursor_fixture()

    recolored, changed = module.recolor_cursor(source, (0x12, 0x34, 0x56), (0xAB, 0xCD, 0xEF))

    assert changed == 2
    assert recolored[:64] == source[:64]
    assert struct.unpack_from("<2I", recolored, 64) == (0xFF123456, 0xFFABCDEF)


def test_build_theme_preserves_aliases_and_hotspots(tmp_path):
    module = load_module()
    source = tmp_path / "Adwaita"
    cursors = source / "cursors"
    cursors.mkdir(parents=True)
    (cursors / "default").write_bytes(xcursor_fixture())
    (cursors / "left_ptr").symlink_to("default")
    destination = tmp_path / "runtime-theme"

    result = module.build_theme(source, destination, "#13c1dc", "#061221")

    assert result == {"files": 1, "pixels": 2}
    assert (destination / "cursors" / "left_ptr").is_symlink()
    assert os.readlink(destination / "cursors" / "left_ptr") == "default"
    data = (destination / "cursors" / "default").read_bytes()
    assert struct.unpack_from("<2I", data, 64) == (0xFF13C1DC, 0xFF061221)
    assert "Inherits=Adwaita" in (destination / "index.theme").read_text(encoding="utf-8")


def test_apply_and_restore_are_isolated_and_restore_the_baseline(monkeypatch, tmp_path):
    module = load_module()
    icon_root, state_path, command_log = configure_runtime(monkeypatch, tmp_path)
    source = icon_root / "Adwaita" / "cursors"
    source.mkdir(parents=True)
    (source / "default").write_bytes(xcursor_fixture())
    (source / "left_ptr").symlink_to("default")

    applied = module.apply_theme("#13c1dc", "#061221", "default", 24)

    assert applied["active"] is True
    assert applied["sourceTheme"] == "Adwaita"
    assert (icon_root / module.RUNTIME_THEME / "cursors" / "default").is_file()
    state = json.loads(state_path.read_text(encoding="utf-8"))
    assert state["baselineTheme"] == "default"
    assert state["baselineSize"] == 24

    reapplied = module.apply_theme("#78824b", "#222222", "ignored", 99)
    assert reapplied["baselineTheme"] == "default"
    assert reapplied["baselineSize"] == 24

    restored = module.restore_theme()

    assert restored == {"active": False, "restored": True, "theme": "default", "size": 24}
    assert not (icon_root / module.RUNTIME_THEME).exists()
    assert not state_path.exists()
    calls = command_log.read_text(encoding="utf-8").splitlines()
    assert [call for call in calls if call.startswith("setcursor ")] == [
        "setcursor jobo-big-cheese-runtime 24",
        "setcursor default 24",
        "setcursor jobo-big-cheese-runtime 24",
        "setcursor default 24",
    ]
    assert calls.count("-j cursorpos") == 4
    assert calls.count("dispatch hl.dsp.cursor.move({ x = 10, y = 20 })") == 4
