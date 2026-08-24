import os
import shutil
import socket
import subprocess
import threading
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
HARNESS = ROOT / "tests" / "quickshell"


def serve_cursor(socket_path: Path, ready: threading.Event, commands: list[bytes]):
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as server:
        server.bind(str(socket_path))
        server.listen()
        ready.set()
        connection, _ = server.accept()
        with connection:
            commands.append(connection.recv(64))
            connection.sendall(b'{"x":-1920,"y":360}')


def test_cursor_tracker_under_quickshell_with_fake_hyprland_socket(tmp_path):
    socket_path = tmp_path / "hypr.sock"
    ready = threading.Event()
    commands = []
    server = threading.Thread(
        target=serve_cursor,
        args=(socket_path, ready, commands),
        daemon=True,
    )
    server.start()
    assert ready.wait(timeout=1)

    config = tmp_path / "quickshell-test"
    services = config / "services"
    scripts = config / "scripts"
    services.mkdir(parents=True)
    scripts.mkdir()
    shutil.copy2(HARNESS / "shell.qml", config / "shell.qml")
    shutil.copy2(ROOT / "scripts" / "cursor-position.py", scripts / "cursor-position.py")
    for source_name in ("CursorTracker.qml", "ShakeDetector.qml", "ShakeModel.js"):
        shutil.copy2(ROOT / "services" / source_name, services / source_name)

    runtime = tmp_path / "runtime"
    runtime.mkdir(mode=0o700)
    env = os.environ.copy()
    # The harness is intentionally headless. Do not advertise the live Wayland
    # session to Quickshell while forcing its offscreen Qt platform.
    env.pop("WAYLAND_DISPLAY", None)
    env.update(
        BIG_CHEESE_CURSOR_SOCKET=str(socket_path),
        XDG_RUNTIME_DIR=str(runtime),
        QT_QPA_PLATFORM="offscreen",
        NO_COLOR="1",
    )
    result = subprocess.run(
        ["qs", "--no-color", "-p", str(config)],
        env=env,
        capture_output=True,
        text=True,
        timeout=10,
    )
    server.join(timeout=1)
    output = result.stdout + result.stderr
    assert "WAYLAND_DISPLAY is present" not in output, output
    assert "TRACKER_TEST_PASS" in output, output
    assert "TRACKER_TEST_FAIL" not in output, output
    assert result.returncode == 0, output
    assert commands == [b"j/cursorpos"]
