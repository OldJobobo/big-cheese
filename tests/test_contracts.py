import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def test_manifest_declares_big_cheese_service():
    manifest = json.loads((ROOT / "manifest.json").read_text(encoding="utf-8"))

    assert manifest["schemaVersion"] == 1
    assert manifest["id"] == "jobo.big-cheese"
    assert manifest["kinds"] == ["service"]
    assert manifest["entryPoints"]["service"] == "Service.qml"


def test_service_scaffold_files_exist():
    assert (ROOT / "Service.qml").is_file()
    assert (ROOT / "services" / "CursorTracker.qml").is_file()
    assert (ROOT / "services" / "ShakeDetector.qml").is_file()
