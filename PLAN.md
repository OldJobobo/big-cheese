# Big Cheese — One-Shot Implementation Plan

> Historical implementation plan for v0.1.0. The shipped source, README, and
> tests are authoritative where completed implementation details differ.

## Goal

Turn the existing `jobo.big-cheese` service scaffold into a reliable Omarchy
Shell plugin that reproduces the useful part of macOS’s **Shake mouse pointer
to locate** behavior:

1. sample the global Hyprland pointer position without intercepting input;
2. recognize an intentional rapid left/right shake;
3. temporarily render a large pointer at the exact active hotspot;
4. remove the visual pointer automatically and restore prior cursor visibility;
5. remain safe across repeated triggers, plugin reloads, command failures, and
   multi-monitor layouts.

The implementation should be complete in one development pass: model, runtime
wiring, helper, tests, documentation, and live verification.

## Current baseline

The scaffold already provides:

- `manifest.json` — service plugin ID `jobo.big-cheese`;
- `Service.qml` — lifecycle, IPC, cursor tracker, and shake detector wiring;
- `services/CursorTracker.qml` — one guarded `hyprctl cursorpos -j` polling
  process shared by the service;
- `services/ShakeDetector.qml` — a bounded horizontal-reversal detector;
- `tests/test_contracts.py` — initial manifest and file contracts.

The installed system currently exposes:

```text
hyprctl cursorpos
hyprctl setcursor <theme> <size>
HYPRCURSOR_SIZE=24
XCURSOR_SIZE=24
GNOME cursor theme=default
GNOME cursor size=24
```

No fullscreen input surface is needed. Big Cheese will use the same global
cursor-position polling strategy already proven by Desktop Ambience.

## Product behavior

### Trigger

A deliberate horizontal shake should trigger when all of these are true inside
a rolling time window:

- at least three meaningful horizontal direction reversals;
- enough total horizontal travel;
- horizontal movement dominates vertical movement;
- samples are recent and contiguous;
- the cooldown has expired.

Ordinary pointer travel, a single fast swipe, crossing monitors, small hand
jitter, and pointer warps must not trigger it.

### Visual locate pulse

On trigger:

- derive a display size from the shake score and clamp it to `48–72 px`;
- immediately show a crisp white pointer with a strong dark outline whose tip
  is anchored to the exact real cursor hotspot;
- follow live cursor samples for approximately `2 seconds`;
- remove the overlay once and restore the compositor cursor's prior visibility.

The pulse contains no locate ring. Hyprland's native cursor is masked for the
short overlay lifetime so live capture shows exactly one pointer. Native
`setcursor` resizing is explicitly not the supported default because Hyprland
can cache client-owned cursor surfaces after enlargement and restoration.

### Retriggering and lifecycle

- Ignore or coalesce triggers while a pulse is active.
- Keep the detector cooldown longer than the enlargement duration.
- Disabling the service stops polling and clears detector history.
- A QML timer owns the visual overlay lifetime; a guarded helper process owns
  native cursor masking and restores the previous visibility if QML reloads.
- Startup performs stale-state recovery only for installations upgraded from
  the disabled native-helper implementation.

## Architecture

```text
Service.qml
├── CursorTracker.qml       shared global position samples
├── ShakeDetector.qml       QML adapter and detector state
│   └── ShakeModel.js       deterministic detection algorithm
├── CursorPulse.qml         visual pulse lifecycle + legacy recovery
├── CursorLocator.qml       per-output input-transparent pointer surfaces
│   └── CursorLocatorModel.js  coordinate and hotspot geometry
└── scripts/cursor-pulse.sh disabled native fallback + migration recovery
BarWidget.qml               pointer status and direct service controls

IPC: omarchy-shell jobo-big-cheese <command>
```

Keep exactly one cursor sampler and one pulse owner. Pre-create one transparent,
input-empty overlay surface per output while enabled so activation is immediate.

## File-by-file implementation

### 1. Add `services/ShakeModel.js`

Move the calculation out of `ShakeDetector.qml` into a deterministic JS model
that accepts plain state and a new sample and returns plain state plus an
optional trigger.

Model state:

```js
{
  samples: [],
  armed: false,
  reversals: 0,
  horizontalTravel: 0,
  verticalTravel: 0,
  peakSpeed: 0,
  lastDirection: 0,
  lastTriggerAt: 0
}
```

Each sample is `{ x, y, at }`.

Algorithm:

1. Reject non-finite coordinates or timestamps.
2. If the gap from the previous sample exceeds `maxSampleGapMs`, clear the
   rolling gesture before accepting the new point.
3. Append the sample and remove samples older than `windowMs`.
4. For every adjacent pair, calculate `dx`, `dy`, distance, and `dt`.
5. Ignore steps smaller than `minimumStep`.
6. Treat a step as horizontal only when
   `abs(dx) >= abs(dy) * horizontalDominance`.
7. Derive direction from the sign of `dx`; increment reversals only when a
   meaningful horizontal direction changes.
8. Cap each segment’s travel contribution so a compositor warp or monitor jump
   cannot satisfy the travel threshold by itself.
9. Arm high-frequency tracking after the first meaningful fast horizontal
   segment.
10. Trigger only when reversal, travel, dominance, time-window, and cooldown
    requirements all pass.
11. Calculate a normalized `0..1` score from reversal excess, horizontal travel,
    and peak speed.
12. Clear gesture samples after triggering while retaining `lastTriggerAt`.

Initial tuning constants:

| Constant | Initial value |
|---|---:|
| `windowMs` | 800 ms |
| `maxSampleGapMs` | 220 ms |
| `minimumStep` | 14 px |
| `minimumReversals` | 3 |
| `minimumHorizontalTravel` | 360 px |
| `horizontalDominance` | 1.15 |
| `maximumSegmentContribution` | 180 px |
| `armingSpeed` | 450 px/s |
| `cooldownMs` | 1400 ms |

These values are calibration starting points, not sacred constants.

### 2. Refactor `services/ShakeDetector.qml`

Turn the component into a small adapter around `ShakeModel.js`.

Responsibilities:

- own user-facing thresholds;
- hold the current model state;
- expose `addSample(x, y, sampledAt)` and `reset()`;
- emit `shaken(score)`;
- expose `armed`, `reversalCount`, `travel`, and `lastTriggerAt`;
- return useful detector telemetry from `status()`;
- clear state immediately when disabled.

Do not duplicate detection math in QML after introducing the JS model.

### 3. Make `services/CursorTracker.qml` adaptive

Preserve its single-process guard: never start another `hyprctl` request while
one is running.

Use two polling rates:

- `idlePollIntervalMs: 110` while no gesture is armed;
- `armedPollIntervalMs: 55` for the short armed window.

Add an `armed` input bound from `ShakeDetector.armed || CursorPulse.active`,
then expose `effectivePollIntervalMs`. This reduces steady-state process
launches while collecting enough samples once a fast movement begins and while
the visual pointer follows the live cursor.

Also:

- record `lastSampleAt` and actual sample interval;
- invalidate stale samples after repeated failures;
- retain global coordinates unchanged, including negative monitor origins;
- expose launch count, failure count, last latency, and effective interval in
  `status()`;
- avoid animation or smoothing—the detector must consume raw coordinates.

### 4. Add `services/CursorPulse.qml` and `services/CursorLocator.qml`

`CursorPulse` owns a timer-driven visual pulse state machine and no shake
recognition. Overlay mode is the default and exposes one `ready` property that
is true immediately; it does not wait for legacy baseline discovery or helper
recovery. `pulse(score)` rejects malformed scores, disabled state, and overlap;
maps the clamped score to 48–72 px; sets `active` before returning; and records
trigger, completion, outcome, and failure telemetry when the 2 second timer ends.
Normal overlay pulses invoke only the guarded compositor-mask helper and never
invoke `setcursor`.

`CursorLocator` receives the existing shared `CursorTracker` and `CursorPulse`.
It creates one transparent `PanelWindow` per `Quickshell.screens`, using
`WlrLayer.Overlay`, `ExclusionMode.Ignore`, `WlrKeyboardFocus.None`, and an empty
`Region` mask. Surfaces remain mapped while enabled. Convert global cursor
coordinates to each screen's local coordinates, including negative origins,
and draw a white pointer with a strong dark outline whose tip is exactly on the
real hotspot. No ring or second pointer may sit behind it. The overlay must
follow the pointer at the armed polling interval and intercept no input.

### 5. Retain `scripts/cursor-pulse.sh` for masking and migration recovery

Native resizing is explicitly disabled by default because Hyprland can cache
active client-owned cursor surfaces after `setcursor`. Keep this hardened helper
to mask the compositor cursor during normal overlays, restore stale markers from
older installations, and support an opt-in native-resize fallback.

Use Bash with strict mode:

```bash
#!/usr/bin/env bash
set -euo pipefail
```

Arguments must be positional and validated:

```text
cursor-pulse.sh mask <duration-ms>
cursor-pulse.sh pulse <theme> <baseline-size> <peak-size> <duration-ms>
cursor-pulse.sh recover
cursor-pulse.sh status
```

Runtime files belong under:

```text
${XDG_RUNTIME_DIR:-/tmp}/jobo-big-cheese-${UID}/
```

The helper must:

- mask and restore compositor cursor visibility for normal overlay pulses;
- create the runtime directory with mode `0700`;
- serialize access with `flock`;
- validate theme as a non-empty argument and sizes/duration as bounded integers;
- write a recovery marker atomically before enlargement;
- record PID, baseline theme, baseline size, peak size, and deadline;
- atomically record a timestamped terminal success/failure outcome so detached
  enlargement failures cannot be reported as successful completions;
- install `EXIT`, `INT`, `TERM`, and `HUP` traps that restore the baseline;
- run `hyprctl setcursor "$theme" "$peak_size"`;
- strictly parse the current signed integer cursor coordinates and dispatch that
  unchanged absolute position so Hyprland refreshes the active cursor image;
- sleep for the requested fractional duration;
- run `hyprctl setcursor "$theme" "$baseline_size"` and force the same safe
  same-position refresh;
- remove the marker only after successful visible restoration;
- return non-zero and retain enough state for recovery when enlargement or
  restoration fails.

`recover` should inspect a marker, determine whether its recorded helper PID is
still alive, and restore only when the owner is gone or its deadline is stale.
It must be idempotent.

A native fallback launch remains detached so it can survive a Quickshell reload
long enough to restore the cursor. The service runs `recover` on startup for
migration safety. Visual pulses are accepted immediately and launch only the
helper's guarded `mask` command; they never launch native `setcursor` resizing.

Do not use `sudo`, write outside the runtime directory, or edit Hyprland config.

### 6. Wire `Service.qml`

Add `CursorPulse` and connect the existing signal:

```qml
onShaken: function(score) {
  if (cursorPulse.pulse(score)) {
    root.lastShakeAt = Date.now()
    root.shakeDetected(score)
  }
}
```

Bind tracker arming to detector arming. Keep polling active only while the
service is enabled.

Expose minimal readonly pulse-ready, pulse-active, failure, and error properties
for the bar widget, plus shared `setEnabled`, `toggleEnabled`, and `requestPulse`
methods so widget controls do not duplicate service or IPC state.

Expand `statusPayload()` with:

- plugin version;
- enabled/tracking state;
- current polling interval;
- detector telemetry;
- discovered baseline theme and size;
- pulse active state and active peak size;
- trigger/failure counts and last error.

IPC contract:

```text
status               JSON runtime state
enable               enable sampling and detection
disable              stop sampling and clear gesture state
reset                 clear detector history and errors
trigger               manually show the large pointer at score 1
triggerScore <score>  show a clamped 48..72 px visual pointer
refreshBaseline       rerun legacy fallback discovery
recover               run legacy stale-state recovery
```

Quickshell exposes QML method identifiers directly and IPC methods have fixed
arity. The installed-compatible API therefore uses `refreshBaseline` rather
than an identifier containing a hyphen, plus separate zero- and one-argument
trigger methods. Both manual trigger methods must use the same `CursorPulse`
path as a detected shake. Clamp explicit finite scores and reject malformed
values.

When disabled during an active visual pulse, let its short timer finish; the
helper process must still restore the native cursor visibility.

### 7. Update manifest and documentation

Keep one long-lived service owner and add one compact `bar-widget` entry point.
The widget uses `bar.shell.serviceFor("jobo.big-cheese")`, defaults to the right
section, and allows only one instance. Its supported Font Awesome mouse-pointer
monochrome cheese icon manually locates on left click, toggles the service on right click,
and shows a restrained active pulse.
Do not add a popup or settings panel.

Update:

- `README.md` — remove the scaffold warning, describe behavior, requirements,
  install, commands, tuning defaults, limitations, and uninstall behavior;
- `CHANGELOG.md` — record the first working implementation;
- `manifest.json` — keep version `0.1.0` until release and declare both the
  service and bar-widget entry points;
- `.gitignore` — include test and local runtime artifacts only; runtime state
  itself lives under `$XDG_RUNTIME_DIR` and should never enter the repository.

Document that native `setcursor` resizing is disabled because custom
client-owned cursor surfaces can cache both enlargement and restoration.

## Automated tests

### Detector model tests

Add behavior tests covering:

1. three fast alternating horizontal reversals trigger once;
2. a single fast swipe does not trigger;
3. slow left/right movement outside the window does not trigger;
4. tiny jitter does not trigger;
5. mostly vertical movement does not trigger;
6. a large one-segment pointer warp does not trigger;
7. negative global coordinates work;
8. a stale sample gap resets the gesture;
9. cooldown suppresses immediate retriggering;
10. a later valid gesture triggers after cooldown;
11. score always remains within `0..1`.

Prefer a headless QML harness that exercises the actual JS/QML model. Keep
Python contract tests for manifest and source-level invariants, but do not claim
behavioral coverage from string matching alone.

### Cursor tracker tests

Use a fake `hyprctl` executable earlier in `PATH` to return deterministic JSON.
Verify:

- valid samples emit coordinates and timestamps;
- malformed JSON increments failure state;
- overlapping polls are prevented;
- idle and armed intervals switch correctly;
- repeated failures clear an armed detector and return polling to idle;
- non-numeric coordinates and timestamps are rejected;
- negative coordinates survive unchanged.

### Visual locator tests

Verify pure score-to-size and geometry behavior, exact hotspot anchoring,
negative-origin and horizontal/vertical monitor mapping, half-open output
bounds, input transparency, pre-created overlay ownership, one guarded mask
helper invocation in default mode, timer completion telemetry, and high-rate
tracker binding while the overlay is active.

### Legacy pulse helper tests

Run `scripts/cursor-pulse.sh` against a fake `hyprctl` that records argv.
Verify:

- call order is enlarge, same-position refresh, restore, and refresh;
- negative coordinates survive strict parsing and Lua-dispatch interpolation;
- malformed coordinates fail the visible pulse and retain recoverable state;
- legacy `movecursor` dispatch is a bounded fallback;
- theme remains one argument even if it contains spaces;
- baseline and peak sizes are passed exactly;
- invalid, overlong, and overflow-sized numeric values are rejected before
  calling `hyprctl`;
- crafted invalid markers and symlinked runtime child files are rejected;
- the marker exists during a pulse and disappears after restoration;
- terminal outcomes distinguish successful pulses from safely restored failures;
- TERM executes restoration through the trap;
- `recover` restores a stale marker once;
- `recover` is idempotent;
- lock contention cannot run two pulses concurrently.

Keep helper tests short by using tiny test durations.

### Service contract tests

Verify:

- manifest ID plus service and bar-widget entry points;
- only one `CursorTracker`, `ShakeDetector`, `CursorPulse`, and `CursorLocator` instance exists;
- the bar widget reuses the shared service and owns no `IpcHandler`;
- every documented IPC command exists;
- shake and manual trigger share `CursorPulse.pulse()`;
- disabling clears detection but does not issue a second cursor mutation path.

## Validation commands

Run from `~/Projects/big-cheese`:

```bash
python -m json.tool manifest.json >/dev/null
omarchy plugin validate .
qmllint -I /usr/lib/qt6/qml \
  Service.qml \
  BarWidget.qml \
  services/CursorTracker.qml \
  services/ShakeDetector.qml \
  services/CursorPulse.qml \
  services/CursorLocator.qml
./tests/run-qml-tests.sh -o -,txt
python -m pytest -q tests
shellcheck scripts/cursor-pulse.sh
```

If `shellcheck` is not installed, run `bash -n scripts/cursor-pulse.sh` and note
that static shell analysis remains outstanding rather than installing a package
without approval.

## Live verification

After automated tests pass:

1. Install from the local Git checkout:

   ```bash
   omarchy plugin add "file://$(pwd)" --enable --yes
   ```

2. Confirm healthy idle state:

   ```bash
   omarchy-shell jobo-big-cheese status | jq
   ```

3. Run the manual pulse endpoint first and capture before/during/after frames.
   Confirm that the large overlay pointer appears at the exact hotspot during
   the pulse and disappears after about 2 seconds:

   ```bash
   omarchy-shell jobo-big-cheese trigger
   omarchy-shell jobo-big-cheese triggerScore 1
   ```

4. Verify the screenshot-visible overlay over desktop, native Wayland,
   XWayland, window borders, and resize cursors without input interception.
5. Shake deliberately on each monitor, including monitors with negative global
   origins.
6. Check false positives during normal browsing, text selection, window drag,
   gaming-style fast movement, and monitor crossing.
7. Trigger a pulse, then force a shell plugin rescan; verify no native cursor
   state is stranded and the overlay can trigger again after reload.
8. Test disable/enable and verify polling launch count stops while disabled.
9. Inspect Hyprland configuration health without changing it:

   ```bash
   hyprctl configerrors
   ```

10. Tune thresholds only from observed telemetry, then rerun all detector tests.

Do not edit `/usr/share/omarchy/`. Development remains in this repository and
installation uses Omarchy’s plugin workflow.

## Acceptance criteria

Implementation is complete when:

- a deliberate shake reliably shows the large pointer overlay on the live Omarchy session;
- normal motion does not produce obvious false positives during a practical
  desktop test;
- screenshot bounds prove the overlay appears during the pulse and disappears afterward;
- normal pulses make zero native `setcursor` mutations;
- Quickshell reload during a pulse cannot strand native cursor state;
- only one cursor polling process can be active at a time;
- idle polling remains at or below roughly ten launches per second and armed
  polling lasts only for the gesture window;
- all automated tests, JSON validation, QML linting, and shell syntax/static
  checks pass;
- `status` exposes enough telemetry to tune failures without adding debug
  logging to the hot path;
- README installation and IPC examples match the shipped implementation.

## Explicit non-goals for v0.1.0

- native cursor-surface resizing as the default path;
- fullscreen dimming, spotlight effects, or locate rings;
- a settings or popup panel;
- persistent Hyprland Lua configuration changes;
- reading raw `/dev/input` devices;
- supporting compositors other than Hyprland;
- persisting tuning settings beyond source defaults.

These can be considered only after the basic shake and visual locate path is
dependable.
