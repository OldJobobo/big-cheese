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
  Service.qml BarWidget.qml services/CursorTracker.qml \
  services/ShakeDetector.qml services/CursorPulse.qml \
  services/CursorLocator.qml
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

Verify all of the following:

- the pulse shows one sharp pointer with no ring or doubled transition frame;
- the pointer remains enlarged for two seconds and follows the real hotspot;
- the native cursor returns after the pulse;
- left click triggers and right click toggles the monochrome cheese bar widget;
- `failureCount` is zero and `lastError` is empty;
- `hyprctl configerrors` prints no errors.

## Tag

After committing the release, create an annotated tag matching the manifest:

```bash
git tag -a v0.1.0 -m "Big Cheese v0.1.0"
git push origin main --follow-tags
```

Publishing, pushing, and tagging are intentionally manual release-owner steps.
