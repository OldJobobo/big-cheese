#!/usr/bin/env python3
"""Check or prepare a synchronized Big Cheese release version."""

from __future__ import annotations

import argparse
from datetime import date
import json
import os
from pathlib import Path
import re
import sys

SEMVER = re.compile(r"^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$")
SERVICE_VERSION = re.compile(
    r'(?m)^(\s*readonly property string pluginVersion:\s*")([^"]+)("\s*)$'
)
RELEASE_HEADING = re.compile(r"(?m)^## \[([^]]+)] - (\d{4}-\d{2}-\d{2})$")
UNRELEASED = "## [Unreleased]"


def repository_root() -> Path:
    override = os.environ.get("BIG_CHEESE_ROOT")
    return Path(override) if override else Path(__file__).resolve().parents[1]


def parse_version(value: str) -> tuple[int, int, int]:
    match = SEMVER.fullmatch(value.strip())
    if not match:
        raise ValueError("version must use MAJOR.MINOR.PATCH without a v prefix")
    return tuple(int(part) for part in match.groups())


def version_text(root: Path) -> str:
    try:
        value = (root / "VERSION").read_text(encoding="utf-8").strip()
    except OSError as error:
        raise ValueError(f"VERSION could not be read: {error}") from error
    parse_version(value)
    return value


def release_state(root: Path) -> dict[str, str]:
    version = version_text(root)
    try:
        manifest = json.loads((root / "manifest.json").read_text(encoding="utf-8"))
        service = (root / "Service.qml").read_text(encoding="utf-8")
        changelog = (root / "CHANGELOG.md").read_text(encoding="utf-8")
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise ValueError(f"release metadata could not be read: {error}") from error
    service_versions = SERVICE_VERSION.findall(service)
    if len(service_versions) != 1:
        raise ValueError("Service.qml must contain exactly one pluginVersion property")
    releases = RELEASE_HEADING.findall(changelog)
    if not releases:
        raise ValueError("CHANGELOG.md has no dated release heading")
    if UNRELEASED not in changelog:
        raise ValueError("CHANGELOG.md is missing the Unreleased heading")
    return {
        "version": version,
        "manifest": str(manifest.get("version", "")),
        "service": service_versions[0][1],
        "changelog": releases[0][0],
        "releaseDate": releases[0][1],
    }


def check(root: Path) -> dict[str, str]:
    state = release_state(root)
    expected = state["version"]
    mismatches = [
        f"manifest.json={state['manifest']}" if state["manifest"] != expected else "",
        f"Service.qml={state['service']}" if state["service"] != expected else "",
        f"CHANGELOG.md={state['changelog']}" if state["changelog"] != expected else "",
    ]
    mismatches = [value for value in mismatches if value]
    if mismatches:
        raise ValueError(f"VERSION={expected} is out of sync with " + ", ".join(mismatches))
    return state


def unreleased_body(changelog: str) -> tuple[str, int, int]:
    marker = UNRELEASED + "\n"
    start = changelog.find(marker)
    if start < 0:
        raise ValueError("CHANGELOG.md is missing the Unreleased heading")
    body_start = start + len(marker)
    next_heading = changelog.find("\n## [", body_start)
    if next_heading < 0:
        raise ValueError("CHANGELOG.md has no release after Unreleased")
    body = changelog[body_start:next_heading].strip()
    if not body:
        raise ValueError("Unreleased has no entries to release")
    return body, body_start, next_heading


def prepare(root: Path, next_version: str, release_date: str) -> dict[str, str]:
    current = check(root)
    next_tuple = parse_version(next_version)
    current_tuple = parse_version(current["version"])
    if next_tuple <= current_tuple:
        raise ValueError(f"next version must be greater than {current['version']}")
    try:
        parsed_date = date.fromisoformat(release_date)
    except ValueError as error:
        raise ValueError("release date must use YYYY-MM-DD") from error

    manifest_path = root / "manifest.json"
    service_path = root / "Service.qml"
    changelog_path = root / "CHANGELOG.md"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    service = service_path.read_text(encoding="utf-8")
    changelog = changelog_path.read_text(encoding="utf-8")
    if re.search(rf"(?m)^## \[{re.escape(next_version)}] - ", changelog):
        raise ValueError(f"CHANGELOG.md already contains {next_version}")

    body, body_start, next_heading = unreleased_body(changelog)
    manifest["version"] = next_version
    next_service, substitutions = SERVICE_VERSION.subn(
        rf'\g<1>{next_version}\g<3>', service
    )
    if substitutions != 1:
        raise ValueError("Service.qml version could not be updated safely")
    release_block = (
        "\n"
        f"## [{next_version}] - {parsed_date.isoformat()}\n\n"
        f"{body}\n"
    )
    next_changelog = changelog[:body_start] + release_block + changelog[next_heading:]

    (root / "VERSION").write_text(next_version + "\n", encoding="utf-8")
    manifest_path.write_text(
        json.dumps(manifest, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    service_path.write_text(next_service, encoding="utf-8")
    changelog_path.write_text(next_changelog, encoding="utf-8")
    return check(root)


def parser() -> argparse.ArgumentParser:
    command = argparse.ArgumentParser(description=__doc__)
    subcommands = command.add_subparsers(dest="command", required=True)
    subcommands.add_parser("check", help="verify synchronized release metadata")
    prepare_command = subcommands.add_parser(
        "prepare", help="bump synchronized metadata and release Unreleased entries"
    )
    prepare_command.add_argument("version")
    prepare_command.add_argument("--date", default=date.today().isoformat())
    return command


def main() -> int:
    arguments = parser().parse_args()
    root = repository_root()
    try:
        state = (
            check(root)
            if arguments.command == "check"
            else prepare(root, arguments.version, arguments.date)
        )
    except ValueError as error:
        print(f"release check failed: {error}", file=sys.stderr)
        return 1
    print(
        f"Big Cheese {state['version']} · manifest, service, and changelog synchronized"
        f" · released {state['releaseDate']}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
