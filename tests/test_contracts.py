import json
import re
import struct
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SERVICE = (ROOT / "Service.qml").read_text(encoding="utf-8")
TRACKER = (ROOT / "services" / "CursorTracker.qml").read_text(encoding="utf-8")
DETECTOR = (ROOT / "services" / "ShakeDetector.qml").read_text(encoding="utf-8")
PULSE = (ROOT / "services" / "CursorPulse.qml").read_text(encoding="utf-8")
LOCATOR = (ROOT / "services" / "CursorLocator.qml").read_text(encoding="utf-8")
BAR_WIDGET = (ROOT / "BarWidget.qml").read_text(encoding="utf-8")
PANEL = (ROOT / "Panel.qml").read_text(encoding="utf-8")
HELPER = (ROOT / "scripts" / "cursor-pulse.sh").read_text(encoding="utf-8")
VERSION = (ROOT / "VERSION").read_text(encoding="utf-8").strip()


def test_manifest_declares_service_and_bar_widget():
    manifest = json.loads((ROOT / "manifest.json").read_text(encoding="utf-8"))

    assert manifest["schemaVersion"] == 1
    assert manifest["id"] == "jobo.big-cheese"
    assert manifest["version"] == VERSION
    assert manifest["license"] == "MIT"
    assert f'readonly property string pluginVersion: "{VERSION}"' in SERVICE
    assert (ROOT / "LICENSE").is_file()
    assert manifest["kinds"] == ["service", "bar-widget"]
    assert manifest["entryPoints"] == {
        "service": "Service.qml",
        "barWidget": "BarWidget.qml",
    }
    assert manifest["barWidget"]["defaultSection"] == "right"
    assert manifest["barWidget"]["allowMultiple"] is False


def test_complete_runtime_files_exist():
    for relative in (
        "VERSION",
        "Service.qml",
        "BarWidget.qml",
        "Panel.qml",
        "cheese.toml",
        "assets/the-big-cheese.png",
        "services/CursorTracker.qml",
        "services/ShakeDetector.qml",
        "services/ShakeModel.js",
        "services/CursorPulse.qml",
        "services/CursorPulseModel.js",
        "services/CursorLocator.qml",
        "services/CursorLocatorModel.js",
        "scripts/cursor-pulse.sh",
        "scripts/cursor-palette.py",
        "scripts/cursor-position.py",
        "scripts/cheese-config.py",
        "scripts/theme-cursor.py",
        "scripts/release.py",
    ):
        assert (ROOT / relative).is_file()


def test_service_loads_the_short_toml_config_into_runtime_components():
    assert 'Qt.resolvedUrl("cheese.toml")' in SERVICE
    assert 'Qt.resolvedUrl("scripts/cheese-config.py")' in SERVICE
    assert "configProcess.command = [configReaderPath, configPath]" in SERVICE
    assert "minimumStep: root.detectorConfig.minimumStep" in SERVICE
    assert "minimumReversals: root.detectorConfig.minimumReversals" in SERVICE
    assert "minimumPeakSize: root.configuredPointerSize" in SERVICE
    assert "maximumPeakSize: root.configuredPointerSize" in SERVICE
    assert "durationMs: root.configuredDurationMs" in SERVICE
    assert "trailMode: root.mouseTrail" in SERVICE
    assert 'Qt.resolvedUrl("scripts/theme-cursor.py")' in SERVICE
    assert "onOmarchyCursorFillChanged: themeCursorRefresh.restart()" in SERVICE
    assert "onOmarchyCursorOutlineChanged: themeCursorRefresh.restart()" in SERVICE
    assert 'themeCursorStatusProcess.command = [themeCursorHelperPath, "status"]' in SERVICE
    assert '"apply",\n      omarchyCursorFill,\n      omarchyCursorOutline' in SERVICE


def test_overlay_textures_are_right_sized():
    cheese = (ROOT / "assets" / "the-big-cheese.png").read_bytes()
    assert cheese[:8] == b"\x89PNG\r\n\x1a\n"
    assert struct.unpack(">II", cheese[16:24]) == (256, 256)
    assert len(cheese) < 100_000



def test_service_has_exactly_one_owner_for_each_runtime_component():
    assert len(re.findall(r"\bCursorTracker\s*\{", SERVICE)) == 1
    assert len(re.findall(r"\bShakeDetector\s*\{", SERVICE)) == 1
    assert len(re.findall(r"\bCursorPulse\s*\{", SERVICE)) == 1
    assert len(re.findall(r"\bCursorLocator\s*\{", SERVICE)) == 1
    assert "id: cursorLocator" in SERVICE


def test_service_exposes_documented_ipc_commands():
    for function_name in (
        "status",
        "enable",
        "disable",
        "reset",
        "trigger",
        "triggerScore",
        "refreshBaseline",
        "recover",
    ):
        assert re.search(rf"function\s+{function_name}\s*\(", SERVICE)


def test_detected_and_manual_triggers_share_the_same_pulse_path():
    assert "function requestPulse(score)" in SERVICE
    assert "cursorPulse.pulse(score)" in SERVICE
    assert "root.requestPulse(score)" in SERVICE
    assert "root.requestPulse(1)" in SERVICE
    assert "root.requestPulse(parsed.value)" in SERVICE
    assert SERVICE.count("cursorPulse.pulse(") == 1


def test_disable_clears_detection_without_mutating_cursor_directly():
    disable_body = re.search(
        r"function disable\(\): string \{(?P<body>.*?)\n    \}",
        SERVICE,
        re.DOTALL,
    )
    assert disable_body
    assert "root.setEnabled(false)" in disable_body.group("body")
    assert "if (!enabled) shakeDetector.reset()" in SERVICE
    assert "hyprctl" not in SERVICE
    assert "setcursor" not in SERVICE


def test_disabling_mid_pulse_keeps_tracking_and_locator_alive_until_restore():
    assert "active: root.enabled || cursorPulse.active" in SERVICE
    assert "enabled: root.enabled || cursorPulse.active" in SERVICE
    assert "if (!enabled) shakeDetector.reset()" in SERVICE


def test_detector_is_a_thin_adapter_over_the_model():
    assert 'import "ShakeModel.js" as ShakeModel' in DETECTOR
    assert "ShakeModel.addSample(" in DETECTOR
    assert "Math.sqrt" not in DETECTOR


def test_tracker_uses_one_adaptive_read_only_cursor_stream():
    assert "idlePollIntervalMs: 110" in TRACKER
    assert "armedPollIntervalMs: 55" in TRACKER
    assert "armed ? armedPollIntervalMs : idlePollIntervalMs" in TRACKER
    assert "armed: shakeDetector.armed || cursorPulse.active" in SERVICE
    assert "if (!active || launchPending || cursorProcess.running) return false" in TRACKER
    assert 'Qt.resolvedUrl("../scripts/cursor-position.py")' in TRACKER
    assert "cursorProcess.command = [helperPath, String(armedPollIntervalMs)]" in TRACKER
    assert "now - lastSampleAt < effectivePollIntervalMs - 2" in TRACKER
    assert 'command = ["hyprctl"' not in TRACKER
    assert "signal observed(real x, real y, double sampledAt)" in TRACKER
    assert "rawCursorX = payload.x" in TRACKER
    assert "signal samplingInvalidated()" in TRACKER
    assert "onSamplingInvalidated: shakeDetector.clearGesture()" in SERVICE


def test_visual_overlay_is_default_and_invokes_only_mask_helper():
    assert "property bool nativeResizeEnabled: false" in PULSE
    assert 'readonly property string mode: nativeResizeEnabled ? "native" : "overlay"' in PULSE
    visual_branch = PULSE.index("if (!nativeResizeEnabled)")
    native_branch = PULSE.index("if (!recoveryReady)")
    assert visual_branch < native_branch
    visual_code = PULSE[visual_branch:native_branch]
    assert 'maskProcess.command = [helperPath, "mask", String(activeDurationMs)]' in visual_code
    assert "activeDurationMs = activeGrowEnabled" in visual_code
    assert "? growthMaximumDurationMs : effectiveDurationMs()" in visual_code
    assert "durationMultiplier: root.easterEggEnabled ? 2 : 1" in SERVICE
    assert "maskProcess.running = true" in visual_code
    assert "active = true" in visual_code
    assert 'state === "masked"' in PULSE
    assert 'state === "restoring"' in PULSE
    assert "root.overlayReady = true" in PULSE
    assert "visualPulseTimer.restart()" in PULSE
    assert 'lastError = "cursor mask restoration is still finishing"' in PULSE
    assert 'root.setFailure("cursor mask restoration failed")' in PULSE
    assert "root.visualFinished = true" in PULSE
    assert "else if (root.visualFinished)" in PULSE
    assert 'onTriggered: root.setFailure("cursor mask exceeded its visual deadline")' in PULSE
    assert "maskProcess.running = false" not in PULSE
    assert "cursorPulse.active && cursorPulse.overlayReady" in LOCATOR
    assert "cursorTracker.ensureRunning()" in SERVICE


def test_cursor_locator_owns_input_transparent_per_output_overlay():
    assert "model: Quickshell.screens" in LOCATOR
    assert "PanelWindow" in LOCATOR
    assert "visible: root.enabled" in LOCATOR
    assert "WlrLayershell.layer: WlrLayer.Overlay" in LOCATOR
    assert "WlrLayershell.keyboardFocus: WlrKeyboardFocus.None" in LOCATOR
    assert "exclusionMode: ExclusionMode.Ignore" in LOCATOR
    assert "mask: Region {}" in LOCATOR
    assert "CursorLocatorModel.localPosition(" in LOCATOR
    assert "CursorLocatorModel.contains(" in LOCATOR
    assert "CursorTracker" not in LOCATOR
    assert "hyprctl" not in LOCATOR
    assert "locateEcho" not in LOCATOR
    assert "border.width" not in LOCATOR
    assert "Shape.CurveRenderer" in LOCATOR
    assert "renderTarget: Canvas.Image" in LOCATOR
    assert "renderStrategy: Canvas.Threaded" in LOCATOR
    assert "function drawLayer(" in LOCATOR
    assert "context.quadraticCurveTo(" in LOCATOR
    assert "var taper = life * life * (3 - 2 * life)" in LOCATOR
    assert "context.fill()" in LOCATOR
    assert 'context.lineCap = "round"' not in LOCATOR
    assert "lifetimeMs: root.easterEggEnabled ? 1200 : 950" in LOCATOR
    assert "markDirty(dirty)" in LOCATOR
    assert "trailAnchorSize * (root.active && root.easterEggEnabled ? 0.18 : 0.32)" in LOCATOR
    assert "trailAnchorSize * (root.active && root.easterEggEnabled ? 0.9 : 0.58)" in LOCATOR
    assert "Math.max(90, trailAnchorSize * 1.25)" in LOCATOR
    assert "Math.max(40, trailAnchorSize * 0.9)" in LOCATOR
    assert "locatorSurface.trailStartWidth * 0.68" in LOCATOR
    assert "locatorSurface.trailStartWidth * 0.14" in LOCATOR
    assert 'root.trailMode === "always"' in LOCATOR
    assert 'root.trailMode === "reveal" && root.active' in LOCATOR
    assert LOCATOR.count("Behavior on x") == 3
    assert LOCATOR.count("Behavior on y") == 3
    assert "enabled: pointer.visible" in LOCATOR
    assert 'source: Qt.resolvedUrl("../assets/the-big-cheese.png")' in LOCATOR
    assert "cheeseSize: root.pointerSize * 2" in LOCATOR
    assert "rotation: 80" in LOCATOR
    assert "Behavior on x" in LOCATOR
    assert "Behavior on y" in LOCATOR
    assert "NumberAnimation { duration: 50; easing.type: Easing.Linear }" in LOCATOR
    assert "cheeseSize * 0.41" in LOCATOR
    assert "cheeseSize * 0.05" in LOCATOR
    assert "&& root.easterEggEnabled" in LOCATOR
    assert "readonly property color pointerFill: useOmarchyPalette" in LOCATOR
    assert "? Color.accent : cursorThemeFill" in LOCATOR
    assert "? Color.background : cursorThemeStroke" in LOCATOR
    assert '"omarchy" : cursorPaletteTheme' in LOCATOR
    assert "cursor-palette.py" in LOCATOR
    assert "strokeColor: root.pointerStroke" in LOCATOR
    assert "fillColor: root.pointerFill" in LOCATOR
    assert "displayedPointerSize" not in LOCATOR
    assert "growAnimation" not in LOCATOR


def test_legacy_helper_uses_resolved_path_and_argument_array_detachment():
    assert 'Qt.resolvedUrl("../scripts/cursor-pulse.sh")' in PULSE
    assert "Quickshell.execDetached([" in PULSE
    assert "bash\", \"-lc" not in PULSE
    assert 'statusProbe.command = [helperPath, "status"]' in PULSE
    assert 'recoveryProcess.command = [helperPath, "recover"]' in PULSE


def test_startup_recovery_failure_is_reported_in_overlay_mode():
    assert 'reason === "startup" || root.nativeResizeEnabled' in PULSE
    assert 'root.setFailure("cursor recovery failed")' in PULSE


def test_bar_widget_uses_the_shared_service_without_duplicate_ipc():
    assert 'serviceFor(root.moduleName)' in BAR_WIDGET
    assert 'text: root.fullColorCheese ? "" : "\\uf7ef"' in BAR_WIDGET
    assert 'fontFamily: "Font Awesome 7 Free Solid"' in BAR_WIDGET
    assert "fontSize: Math.max(1, Style.bar.iconFont - 1)" in BAR_WIDGET
    assert "readonly property bool fullColorCheese: available" in BAR_WIDGET
    assert "cheeseService.easterEggEnabled === true" in BAR_WIDGET
    assert "iconComponent: root.fullColorCheese ? colorCheese : null" in BAR_WIDGET
    assert 'source: Qt.resolvedUrl("assets/cheese-emoji.png")' in BAR_WIDGET
    assert (ROOT / "assets" / "cheese-emoji.png").is_file()
    assert not (ROOT / "assets" / "cheese-emoji.svg").exists()
    assert "togglePanel()" in BAR_WIDGET
    assert "toggleEnabled()" in BAR_WIDGET
    assert "IpcHandler" not in BAR_WIDGET


def test_left_click_opens_a_minimal_native_panel():
    assert 'source: Qt.resolvedUrl("Panel.qml")' in BAR_WIDGET
    assert "else if (mouseButton === Qt.LeftButton) singleClickTimer.restart()" in BAR_WIDGET
    assert "onTriggered: root.togglePanel()" in BAR_WIDGET
    assert "interval: Qt.styleHints.mouseDoubleClickInterval" in BAR_WIDGET
    assert "onDoubleClicked:" in BAR_WIDGET
    assert "cheeseService.toggleEasterEgg()" in BAR_WIDGET
    assert "property bool easterEggEnabled: false" in SERVICE
    assert "easterEggEnabled: root.easterEggEnabled" in SERVICE
    assert "KeyboardPanel" in PANEL
    assert "PanelHero" in PANEL
    assert "ToggleSwitch" in PANEL
    assert 'source: Qt.resolvedUrl("assets/big-cheese-icon.png")' in PANEL
    assert 'meta: "Shake to locate"' in PANEL
    assert 'text: "No one but you can move your cheese!"' in PANEL
    assert PANEL.count("No one but you can move your cheese!") == 1
    assert 'title: "Shake to locate"' in PANEL
    assert 'title: "Mouse trail"' in PANEL
    assert '{ value: "off", label: "Off" }' in PANEL
    assert '{ value: "reveal", label: "Reveal" }' in PANEL
    assert '{ value: "always", label: "Always" }' in PANEL
    assert 'mouseTrail === "always" ? "Follows every move"' in PANEL
    assert "cheeseService.setMouseTrail(mode)" in PANEL
    assert "function setMouseTrail(value)" in SERVICE
    assert 'mode !== "off" && mode !== "reveal" && mode !== "always"' in SERVICE
    assert 'title: "Grow"' in PANEL
    assert 'detail: root.growEnabled' in PANEL
    assert "cheeseService.toggleGrowEnabled()" in PANEL
    assert 'title: "Theme cursor colors"' in PANEL
    assert 'detail: root.nativeThemeCursorDetail' in PANEL
    assert "cheeseService.toggleNativeThemeCursor()" in PANEL
    assert "function setGrowEnabled(value)" in SERVICE
    assert "function toggleGrowEnabled()" in SERVICE
    assert "growEnabled: root.growEnabled" in SERVICE
    assert "function growEnable(): string" in SERVICE
    assert "function growDisable(): string" in SERVICE
    assert "cursorPulse.addGrowthMotion(speed, sampledAt" in SERVICE
    assert "function setNativeThemeCursor(value)" in SERVICE
    assert 'themeCursorRestoreProcess.command = [themeCursorHelperPath, "restore"]' in SERVICE
    assert "nativeThemeCursorBusy: themeCursorStatusProcess.running" in SERVICE
    assert "useOmarchyPalette: root.nativeThemeCursorActive" in SERVICE
    assert "cursorTheme: root.nativeThemeCursorBaseline" in SERVICE
    assert "function themeCursorEnable(): string" in SERVICE
    assert "function themeCursorDisable(): string" in SERVICE
    assert 'title: "Find my cursor"' not in PANEL
    assert 'title: "Give some Cheddar"' in PANEL
    assert 'title: "Support Big Cheese"' not in PANEL
    assert "cheeseService.toggleEnabled()" in PANEL
    assert "cheeseService.requestPulse(1)" not in PANEL
    assert 'Qt.openUrlExternally("https://ko-fi.com/oldjobobo")' in PANEL


def test_bar_widget_prioritizes_service_errors_over_preparing_state():
    error_check = 'if (cheeseService.lastError !== "")'
    preparing_check = 'if (!cheeseService.pulseReady)'
    assert BAR_WIDGET.index(error_check) < BAR_WIDGET.index(preparing_check)


def test_mask_waits_for_native_cursor_to_leave_the_frame_before_overlay():
    hide = 'set_cursor_invisible true'
    frame_wait = 'sleep 0.04'
    ready = "printf 'masked\\n'"
    refresh = "refresh_cursor_image"
    mask_command = HELPER[HELPER.index("mask_command() {"):]
    assert mask_command.index(hide) < mask_command.index(refresh)
    assert mask_command.index(refresh) < mask_command.index(frame_wait)
    assert mask_command.index(frame_wait) < mask_command.index(ready)


def test_mask_hides_overlay_before_restoring_native_cursor():
    restoring = "printf 'restoring\\n'"
    restore = "restore_mask_marker"
    mask_command = HELPER[HELPER.index("mask_command() {"):]
    assert mask_command.index(restoring) < mask_command.index("sleep 0.04", mask_command.index(restoring))
    assert mask_command.index("sleep 0.04", mask_command.index(restoring)) < mask_command.rindex(restore)


def test_helper_forces_a_same_position_cursor_refresh():
    assert "read_cursor_position" in HELPER
    assert "hl.dsp.cursor.move({ x = ${cursor_x}, y = ${cursor_y} })" in HELPER
    assert 'hyprctl dispatch movecursor "$cursor_x" "$cursor_y"' in HELPER
    assert HELPER.count("refresh_cursor_image") >= 3


def test_helper_holds_final_restore_lock_until_outcome_publication():
    assert 'restore_owned_marker "$$"\n  release_lock' not in HELPER
    assert 'write_outcome "$outcome" "$pulse_started_at_ms" "$completed_at_ms"' in HELPER


def test_helpers_are_executable():
    assert (ROOT / "scripts" / "cursor-pulse.sh").stat().st_mode & 0o111
    assert (ROOT / "scripts" / "cursor-palette.py").stat().st_mode & 0o111
    assert (ROOT / "scripts" / "cheese-config.py").stat().st_mode & 0o111
    assert (ROOT / "scripts" / "cursor-position.py").stat().st_mode & 0o111
    assert (ROOT / "scripts" / "theme-cursor.py").stat().st_mode & 0o111
    assert (ROOT / "scripts" / "release.py").stat().st_mode & 0o111
