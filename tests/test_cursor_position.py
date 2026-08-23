import importlib.util
import json
import os
from pathlib import Path
import socket
import subprocess
import threading

import pytest


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "cursor-position.py"


def load_module():
    spec = importlib.util.spec_from_file_location("cursor_position", SCRIPT)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def serve_cursor(
    socket_path: Path,
    responses: list[bytes],
    commands: list[bytes],
    ready: threading.Event,
):
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as server:
        server.bind(str(socket_path))
        server.listen()
        ready.set()
        for response in responses:
            connection, _ = server.accept()
            with connection:
                commands.append(connection.recv(64))
                connection.sendall(response)


def test_query_cursor_uses_read_only_json_command(tmp_path):
    module = load_module()
    socket_path = tmp_path / "hypr.sock"
    commands = []
    ready = threading.Event()
    thread = threading.Thread(
        target=serve_cursor,
        args=(socket_path, [b'{"x":-1920,"y":360}'], commands, ready),
        daemon=True,
    )
    thread.start()
    assert ready.wait(timeout=1)

    x, y, latency_ms = module.query_cursor(socket_path)
    thread.join(timeout=1)

    assert (x, y) == (-1920.0, 360.0)
    assert latency_ms >= 0
    assert commands == [b"j/cursorpos"]


@pytest.mark.parametrize(
    "payload",
    [b"{}", b'{"x":null,"y":1}', b'{"x":true,"y":1}', b"not-json"],
)
def test_query_cursor_rejects_invalid_responses(tmp_path, payload):
    module = load_module()
    socket_path = tmp_path / "hypr.sock"
    ready = threading.Event()
    thread = threading.Thread(
        target=serve_cursor,
        args=(socket_path, [payload], [], ready),
        daemon=True,
    )
    thread.start()
    assert ready.wait(timeout=1)

    with pytest.raises((ValueError, RuntimeError)):
        module.query_cursor(socket_path)
    thread.join(timeout=1)


def test_stream_emits_multiple_samples_from_one_process(tmp_path):
    socket_path = tmp_path / "hypr.sock"
    commands = []
    responses = [
        b'{"x":10,"y":20}',
        b'{"x":11,"y":21}',
        b'{"x":12,"y":22}',
    ]
    ready = threading.Event()
    thread = threading.Thread(
        target=serve_cursor,
        args=(socket_path, responses, commands, ready),
        daemon=True,
    )
    thread.start()
    assert ready.wait(timeout=1)

    env = os.environ.copy()
    env["BIG_CHEESE_CURSOR_SOCKET"] = str(socket_path)
    process = subprocess.Popen(
        [str(SCRIPT), "16"],
        env=env,
        stdout=subprocess.PIPE,
        text=True,
    )
    try:
        assert process.stdout is not None
        samples = [json.loads(process.stdout.readline()) for _ in responses]
    finally:
        process.terminate()
        process.wait(timeout=2)
    thread.join(timeout=1)

    assert [(sample["x"], sample["y"]) for sample in samples] == [
        (10.0, 20.0),
        (11.0, 21.0),
        (12.0, 22.0),
    ]
    assert commands == [b"j/cursorpos"] * 3
