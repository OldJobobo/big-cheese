# Releasing Big Cheese

Big Cheese follows semantic versioning. A release is cut only from a clean
worktree after the repository and installed-plugin checks below pass.

## Prepare

1. Update `manifest.json` and `Service.qml` to the same version.
2. Move changelog entries from `Unreleased` to `[x.y.z] - YYYY-MM-DD`.
3. Confirm `README.md` matches the shipped defaults and dependencies.
4. Confirm `LICENSE` and `manifest.json` declare the same license.

## Validate

Run from the repository root:

```bash
python -m json.tool manifest.json >/dev/null
omarchy plugin validate .
qmllint -I /usr/lib/qt6/qml \
  Service.qml BarWidget.qml Panel.qml \
  services/CursorTracker.qml services/ShakeDetector.qml \
  services/CursorPulse.qml services/CursorLocator.qml
./tests/run-qml-tests.sh -o -,txt
python -m pytest -q tests
shellcheck scripts/cursor-pulse.sh
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

- a shake shows one sharp 72 px pointer for two seconds, with no ring or
  doubled transition frame;
- the pointer follows the real hotspot and the native cursor returns cleanly;
- left-click opens the compact panel and **Give some Cheddar** opens the
  official Ko-fi page;
- right-click disables and re-enables shake detection;
- double-click enables the full-color icon, and the next shake shows the
  rotated 144 px cheese pointer for four seconds;
- restarting the shell restores the monochrome icon and standard pointer mode;
- `failureCount` is zero, `lastError` is empty, and `hyprctl configerrors`
  prints no errors.

## Tag

After committing the release, create an annotated tag matching the manifest:

```bash
git tag -a v0.1.0 -m "Big Cheese v0.1.0"
git push origin main --follow-tags
```

Publishing, pushing, and tagging are intentionally manual release-owner steps.
