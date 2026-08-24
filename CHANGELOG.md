# Changelog

All notable changes to Big Cheese are documented here.

## [Unreleased]

## [0.1.2] - 2026-08-24

- Added the active `cheese.toml` path to the panel as a compact link that opens
  the file in a window with the user's configured Omarchy editor.
- Added a minimal `grow` restart default and expanded the panel height so every
  control remains reachable without crowding the interface.

## [0.1.1] - 2026-08-23

- Replaced per-sample `hyprctl` launches with one persistent, read-only
  Hyprland cursor-position stream while preserving the 110/55 ms idle and
  active sampling cadence.
- Added short linear position interpolation to the standard vector pointer for
  smoother motion without changing click handling or cursor restoration, and
  matched its fill and outline directly to Omarchy accent/background colors.
- Added optional shake-driven Grow mode: continued movement enlarges the
  overlay in proportion to shake speed, then eases it back to its reveal size
  before restoring the normal cursor.
- Added an input-transparent, theme-aware solid mouse trail with smooth Bézier
  curves, `off`, `reveal`, and `always` modes, plus a cheddar-gold Easter egg
  treatment and a compact three-state panel control.
- Added an opt-in native-cursor tint prototype that preserves cursor shapes and
  hotspots, builds from Omarchy accent/background colors in the runtime
  directory, follows live Omarchy theme changes while active, restores the
  previous theme, leaves persistent configuration untouched, and shares one
  panel toggle with the enlarged cursor's Omarchy palette.
- Added a repository `VERSION` source of truth and a guarded release controller
  that keeps the manifest, QML service, and dated changelog release synchronized.

## [0.1.0] - 2026-08-22

- Added deterministic, warp-resistant horizontal shake detection with adaptive
  cursor sampling, cooldown, normalized scoring, and runtime telemetry.
- Added one crisp, theme-colored vector pointer with exact hotspot anchoring,
  input-transparent per-output surfaces, negative-origin monitor support, and
  a guarded compositor mask that prevents rings and doubled transition frames.
- Added crash-safe cursor restoration, same-position compositor refreshes, and
  stale-state recovery while preserving the user's prior cursor visibility.
- Added the concise `cheese.toml` configuration for startup state, shake effort,
  standard pointer size, and standard reveal duration.
- Added a monochrome, theme-colored cheese bar icon: left-click opens the native
  control panel, right-click toggles shake detection, and double-click enables
  the temporary full-color Easter egg.
- Added the rotated Big Cheese pointer, optimized for smooth tracking at twice
  the configured standard size and duration; Easter egg state resets when the
  shell restarts.
- Added the native identity panel, official tagline, shake control, and
  **Give some Cheddar** link to the official Ko-fi page.
- Added status, trigger, baseline refresh, recovery, enable/disable, and reset
  IPC commands, plus QML, helper-lifecycle, configuration, and contract tests.
- Added release metadata, licensing and attribution, security guidance,
  installation instructions, and marketplace preview artwork.
