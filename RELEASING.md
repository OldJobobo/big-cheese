# Releasing Big Cheese

Big Cheese follows semantic versioning. A release is cut only from a clean
worktree after the repository and installed-plugin checks below pass.

## Prepare

1. Finish and review the summary under `Unreleased` in `CHANGELOG.md`.
2. Run `./scripts/release.py prepare x.y.z --date YYYY-MM-DD`. This updates
   `VERSION`, `manifest.json`, `Service.qml`, and the dated changelog heading as
   one guarded operation; it does not commit, tag, or push.
3. Run `./scripts/release.py check` and review the resulting diff.
4. Confirm `README.md` matches the shipped defaults and dependencies.
5. Confirm `LICENSE` and `manifest.json` declare the same license.

## Validate

Run from the repository root:

```bash
./scripts/release.py check
python -m json.tool manifest.json >/dev/null
omarchy plugin validate .
qmllint -I /usr/lib/qt6/qml \
  Service.qml BarWidget.qml Panel.qml \
  services/CursorTracker.qml services/ShakeDetector.qml \
  services/CursorPulse.qml services/CursorLocator.qml
./tests/run-qml-tests.sh -o -,txt
python -m pytest -q tests
shellcheck scripts/cursor-pulse.sh
python -m py_compile scripts/*.py
git diff --check
git status --short
```

The final `git status --short` must be empty after committing the release.

## Live smoke test

Install or update the checkout, then restart the shell so QML caches cannot
retain an older component:

```bash
omarchy plugin add "file://$(pwd)" --enable --yes  # first install only
omarchy restart shell
omarchy-shell jobo-big-cheese status | jq
omarchy-shell jobo-big-cheese trigger
```

Verify all of the following with the default `cheese.toml`:

- a shake shows one sharp 72 px pointer and a theme-accented glowing trail for
  two seconds, with no ring or doubled transition frame;
- the pointer follows the real hotspot and the native cursor returns cleanly;
- left-click opens the compact panel, the trail selector changes modes, the
  cursor-color theme toggle updates both pointer sizes and restores cleanly,
  and **Give some Cheddar** opens the official Ko-fi page;
- right-click disables and re-enables shake detection;
- double-click enables the full-color icon, and the next shake shows the
  rotated 144 px cheese pointer for four seconds;
- restarting the shell restores the monochrome icon and standard pointer mode;
- `mouse_trail = "off"` disables the effect and `"always"` follows the native
  pointer without intercepting input;
- `failureCount` is zero, `lastError` is empty, and `hyprctl configerrors`
  prints no errors;
- `./scripts/theme-cursor.py apply-omarchy` temporarily recolors normal cursor
  shapes, and `./scripts/theme-cursor.py restore` restores the recorded theme
  and removes its runtime files and discovery symlink.

## Tag

After committing the release, create an annotated tag matching `VERSION`:

```bash
version=$(cat VERSION)
git tag -a "v${version}" -m "Big Cheese v${version}"
git push origin main --follow-tags
```

Publishing, pushing, and tagging are intentionally manual release-owner steps.
