# Big Cheese

Shake the pointer to make it impossible to lose.

Big Cheese is an experimental Omarchy Shell service plugin inspired by macOS’s
**Shake mouse pointer to locate** accessibility feature. It samples Hyprland’s
global cursor position and recognizes quick horizontal direction reversals.

## Project status

The initial scaffold includes:

- the `jobo.big-cheese` Omarchy plugin manifest;
- one shared `hyprctl cursorpos -j` sampler;
- a bounded shake-detection window with travel, reversal, and cooldown guards;
- an IPC status endpoint for development and tuning.

Temporary cursor enlargement and restoration are the next implementation slice.

## Local installation

From this repository root:

```bash
omarchy plugin add "file://$(pwd)" --enable --yes
```

Inspect the service:

```bash
omarchy-shell jobo-big-cheese status | jq
```

Disable or re-enable detection at runtime:

```bash
omarchy-shell jobo-big-cheese disable
omarchy-shell jobo-big-cheese enable
```

Omarchy plugins execute unsandboxed inside the long-running shell process.
Review third-party plugin code before enabling it.

## Layout

```text
manifest.json                Omarchy plugin contract
Service.qml                  Service lifecycle and IPC
services/CursorTracker.qml   Shared Hyprland cursor sampler
services/ShakeDetector.qml   Shake recognition state machine
tests/                       Contract tests
```

## Detection defaults

| Setting | Default |
|---|---:|
| Poll interval | 120 ms |
| Detection window | 750 ms |
| Required horizontal reversals | 3 |
| Required pointer travel | 420 px |
| Cooldown | 1200 ms |

These are starting values, not calibrated accessibility defaults.
