# Big Cheese — One-Shot Implementation Plan

## Goal

Turn the existing `jobo.big-cheese` service scaffold into a reliable Omarchy
Shell plugin that reproduces the useful part of macOS’s **Shake mouse pointer
to locate** behavior:

1. sample the global Hyprland pointer position without intercepting input;
2. recognize an intentional rapid left/right shake;
3. temporarily enlarge the active cursor;
4. restore the exact baseline theme and size automatically;
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

### Enlargement

On trigger:

- derive a peak size from the shake score;
- clamp it to a sensible range, initially `48–72 px` for a `24 px` baseline;
- call `hyprctl setcursor <theme> <peak-size>` once;
- hold the large cursor for approximately `900 ms`;
- restore the captured baseline theme and size exactly once.

The first release should use one clean size jump. Repeated `setcursor` reloads
to fake a smooth ramp are explicitly out of scope because they add compositor
work and can visibly flicker. A later visual-only overlay can provide smoother
animation if wanted.

### Retriggering and lifecycle

- Ignore or coalesce triggers while a pulse is active.
- Keep the detector cooldown longer than the enlargement duration.
- Disabling the service stops polling and clears detector history.
- A detached pulse helper owns restoration so a Quickshell hot reload does not
  strand the cursor at the enlarged size.
- Startup performs stale-state recovery if a previous helper died before
  restoring the cursor.

## Architecture

```text
Service.qml
├── CursorTracker.qml       global position samples
├── ShakeDetector.qml       QML adapter and detector state
│   └── ShakeModel.js       deterministic detection algorithm
└── CursorPulse.qml         baseline discovery + pulse lifecycle
    └── scripts/cursor-pulse.sh

IPC: omarchy-shell jobo-big-cheese <command>
```

Keep exactly one cursor sampler and one pulse owner. Per-output windows are not
needed because the compositor cursor itself is being resized.

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

Add an `armed` input bound from `ShakeDetector.armed`, then expose
`effectivePollIntervalMs`. This reduces steady-state process launches while
collecting enough samples once a fast movement begins.

Also:

- record `lastSampleAt` and actual sample interval;
- invalidate stale samples after repeated failures;
- retain global coordinates unchanged, including negative monitor origins;
- expose launch count, failure count, last latency, and effective interval in
  `status()`;
- avoid animation or smoothing—the detector must consume raw coordinates.

### 4. Add `services/CursorPulse.qml`

This component owns cursor baseline discovery and the enlargement state machine.
It must not perform shake detection.

Properties:

```qml
property int minimumPeakSize: 48
property int maximumPeakSize: 72
property int durationMs: 900
property bool active: false
property string baselineTheme: "default"
property int baselineSize: 24
property int activePeakSize: 0
property int triggerCount: 0
property int failureCount: 0
property string lastError: ""
```

Baseline discovery order:

Theme:

1. `Quickshell.env("HYPRCURSOR_THEME")`;
2. `Quickshell.env("XCURSOR_THEME")`;
3. `gsettings get org.gnome.desktop.interface cursor-theme`;
4. literal `default`.

Size:

1. valid positive `HYPRCURSOR_SIZE`;
2. valid positive `XCURSOR_SIZE`;
3. `gsettings get org.gnome.desktop.interface cursor-size`;
4. `24`.

Normalize the quoted `gsettings` theme output and reject invalid, empty, or
non-positive size values. Probe once at startup and expose an IPC refresh path.
Do not mutate environment variables.

`pulse(score)` should:

1. refuse a pulse when disabled, baseline discovery is incomplete, or another
   pulse is active;
2. map score to the clamped peak-size range;
3. mark the pulse active before launching work;
4. invoke the detached helper with argument-array execution, never shell-string
   interpolation;
5. start a local watchdog slightly longer than the requested duration;
6. update telemetry from the helper’s completion marker or recovery probe;
7. clear `active` when restoration is known complete or the watchdog recovers it.

The helper URL should be resolved relative to `CursorPulse.qml` with
`Qt.resolvedUrl("../scripts/cursor-pulse.sh")`, converted from a local file URL
without accepting arbitrary input.

### 5. Add `scripts/cursor-pulse.sh`

Use Bash with strict mode:

```bash
#!/usr/bin/env bash
set -euo pipefail
```

Arguments must be positional and validated:

```text
cursor-pulse.sh pulse <theme> <baseline-size> <peak-size> <duration-ms>
cursor-pulse.sh recover
cursor-pulse.sh status
```

Runtime files belong under:

```text
${XDG_RUNTIME_DIR:-/tmp}/jobo-big-cheese-${UID}/
```

The helper must:

- create the runtime directory with mode `0700`;
- serialize access with `flock`;
- validate theme as a non-empty argument and sizes/duration as bounded integers;
- write a recovery marker atomically before enlargement;
- record PID, baseline theme, baseline size, peak size, and deadline;
- install `EXIT`, `INT`, `TERM`, and `HUP` traps that restore the baseline;
- run `hyprctl setcursor "$theme" "$peak_size"`;
- sleep for the requested fractional duration;
- run `hyprctl setcursor "$theme" "$baseline_size"`;
- remove the marker only after successful restoration;
- return non-zero and retain enough state for recovery when enlargement or
  restoration fails.

`recover` should inspect a marker, determine whether its recorded helper PID is
still alive, and restore only when the owner is gone or its deadline is stale.
It must be idempotent.

Use a detached launch so the helper survives a Quickshell code reload long
enough to restore the cursor. The service should run `recover` on startup and
before accepting the first pulse.

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
trigger [score]       manually test enlargement; score defaults to 1
refresh-baseline      rerun theme/size discovery
recover               run stale pulse recovery
```

Manual `trigger` must use the same `CursorPulse` path as a detected shake. Clamp
its optional score and reject malformed values.

When disabled during an active pulse, do not kill the detached helper; let it
restore on schedule.

### 7. Update manifest and documentation

Keep the plugin service-only and `keepLoaded` by virtue of the Omarchy service
loader. Do not add a bar widget or panel.

Update:

- `README.md` — remove the scaffold warning, describe behavior, requirements,
  install, commands, tuning defaults, limitations, and uninstall behavior;
- `CHANGELOG.md` — record the first working implementation;
- `manifest.json` — keep version `0.1.0` until release and refine the description
  only if needed;
- `.gitignore` — include test and local runtime artifacts only; runtime state
  itself lives under `$XDG_RUNTIME_DIR` and should never enter the repository.

Document that applications using custom client-owned cursor surfaces may not
respond identically to compositor-provided cursor shapes.

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
- negative coordinates survive unchanged.

### Pulse helper tests

Run `scripts/cursor-pulse.sh` against a fake `hyprctl` that records argv.
Verify:

- call order is enlarge then restore;
- theme remains one argument even if it contains spaces;
- baseline and peak sizes are passed exactly;
- invalid sizes/durations are rejected before calling `hyprctl`;
- the marker exists during a pulse and disappears after restoration;
- TERM executes restoration through the trap;
- `recover` restores a stale marker once;
- `recover` is idempotent;
- lock contention cannot run two pulses concurrently.

Keep helper tests short by using tiny test durations.

### Service contract tests

Verify:

- manifest ID and service entry point;
- only one `CursorTracker`, `ShakeDetector`, and `CursorPulse` instance exist;
- every documented IPC command exists;
- shake and manual trigger share `CursorPulse.pulse()`;
- disabling clears detection but does not issue a second cursor mutation path.

## Validation commands

Run from `~/Projects/big-cheese`:

```bash
python -m json.tool manifest.json >/dev/null
qmllint -I /usr/lib/qt6/qml \
  Service.qml \
  services/CursorTracker.qml \
  services/ShakeDetector.qml \
  services/CursorPulse.qml
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

3. Run the manual pulse endpoint first and visually confirm enlargement and
   exact restoration:

   ```bash
   omarchy-shell jobo-big-cheese trigger 1
   ```

4. Verify restoration over desktop, native Wayland applications, XWayland
   applications, window borders, and resize cursors.
5. Shake deliberately on each monitor, including monitors with negative global
   origins.
6. Check false positives during normal browsing, text selection, window drag,
   gaming-style fast movement, and monitor crossing.
7. Trigger a pulse, then force a shell plugin rescan; verify the detached helper
   still restores the cursor.
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

- a deliberate shake reliably enlarges the cursor on the live Omarchy session;
- normal motion does not produce obvious false positives during a practical
  desktop test;
- enlargement restores the baseline theme and size after every tested path;
- Quickshell reload during a pulse does not strand the large cursor;
- only one cursor polling process can be active at a time;
- idle polling remains at or below roughly ten launches per second and armed
  polling lasts only for the gesture window;
- all automated tests, JSON validation, QML linting, and shell syntax/static
  checks pass;
- `status` exposes enough telemetry to tune failures without adding debug
  logging to the hot path;
- README installation and IPC examples match the shipped implementation.

## Explicit non-goals for v0.1.0

- smooth animated cursor-size interpolation;
- a fullscreen visual halo or spotlight overlay;
- a settings panel or bar widget;
- modifying Hyprland Lua configuration;
- reading raw `/dev/input` devices;
- supporting compositors other than Hyprland;
- persisting tuning settings beyond source defaults.

These can be considered only after the basic shake, resize, and restoration
path is dependable.
