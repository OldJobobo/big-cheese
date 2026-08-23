import importlib.util
import json
from pathlib import Path

import pytest


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "release.py"


def load_module():
    spec = importlib.util.spec_from_file_location("big_cheese_release", SCRIPT)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def write_release_fixture(root: Path, version="0.1.0", unreleased="- Added trails."):
    (root / "VERSION").write_text(version + "\n", encoding="utf-8")
    (root / "manifest.json").write_text(
        json.dumps({"schemaVersion": 1, "version": version}, indent=2) + "\n",
        encoding="utf-8",
    )
    (root / "Service.qml").write_text(
        f'Item {{\n  readonly property string pluginVersion: "{version}"\n}}\n',
        encoding="utf-8",
    )
    (root / "CHANGELOG.md").write_text(
        "# Changelog\n\n"
        "## [Unreleased]\n\n"
        f"{unreleased}\n\n"
        f"## [{version}] - 2026-08-22\n\n"
        "- Initial release.\n",
        encoding="utf-8",
    )


def test_repository_release_metadata_is_synchronized():
    module = load_module()

    state = module.check(ROOT)

    expected = (ROOT / "VERSION").read_text(encoding="utf-8").strip()
    assert state["version"] == expected
    assert state["manifest"] == expected
    assert state["service"] == expected
    assert state["changelog"] == expected


def test_check_reports_cross_file_version_drift(tmp_path):
    module = load_module()
    write_release_fixture(tmp_path)
    manifest = json.loads((tmp_path / "manifest.json").read_text(encoding="utf-8"))
    manifest["version"] = "0.1.1"
    (tmp_path / "manifest.json").write_text(json.dumps(manifest), encoding="utf-8")

    with pytest.raises(ValueError, match=r"manifest\.json=0\.1\.1"):
        module.check(tmp_path)


def test_prepare_updates_all_metadata_and_releases_unreleased_entries(tmp_path):
    module = load_module()
    write_release_fixture(tmp_path, unreleased="- Added a solid trail.\n- Added panel modes.")

    state = module.prepare(tmp_path, "0.1.1", "2026-08-23")

    assert state["version"] == "0.1.1"
    assert state["releaseDate"] == "2026-08-23"
    assert (tmp_path / "VERSION").read_text(encoding="utf-8") == "0.1.1\n"
    assert json.loads((tmp_path / "manifest.json").read_text(encoding="utf-8"))["version"] == "0.1.1"
    assert 'pluginVersion: "0.1.1"' in (tmp_path / "Service.qml").read_text(encoding="utf-8")
    changelog = (tmp_path / "CHANGELOG.md").read_text(encoding="utf-8")
    assert "## [Unreleased]\n\n## [0.1.1] - 2026-08-23" in changelog
    assert "- Added a solid trail.\n- Added panel modes." in changelog
    assert changelog.index("## [0.1.1]") < changelog.index("## [0.1.0]")


def test_prepare_rejects_empty_unreleased_section(tmp_path):
    module = load_module()
    write_release_fixture(tmp_path, unreleased="")

    with pytest.raises(ValueError, match="Unreleased has no entries"):
        module.prepare(tmp_path, "0.1.1", "2026-08-23")
