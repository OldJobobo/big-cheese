# Changelog

All notable changes to Big Cheese are documented here.

## [0.1.0] - 2026-08-21

- Added deterministic, warp-resistant horizontal shake detection with a bounded
  rolling window, cooldown, normalized score, and headless behavior tests.
- Added adaptive single-process cursor sampling with idle and armed intervals,
  plus latency, launch, sample, and failure telemetry.
- Added a crisp vector pointer overlay with exact hotspot anchoring,
  input-transparent per-output surfaces, negative-origin monitor mapping, a
  score-derived 48–72 px size, and fill/outline colors detected from the active
  Xcursor theme's default arrow.
- Added a guarded compositor-cursor mask with same-position refresh and a short
  compositor-settle handshake at both ends; live transition capture on the
  verified Hyprland version shows no stacked native and overlay pointers. The
  helper restores the user's previous visibility setting after
  the two-second pulse and can recover stale runtime state after interruption.
- Kept native `setcursor` resizing as a disabled legacy fallback because
  client-owned cursor surfaces can remain cached after theme-size changes.
- Added a compact monochrome cheese bar icon with manual locate,
  enable/disable controls, state tooltips, and pulse feedback.
- Added status, manual trigger, baseline refresh, recovery, enable/disable, and
  reset IPC commands.
- Added QML model tests, Quickshell integration harnesses, helper lifecycle
  regression coverage, installation guidance, and tuning documentation.
