#!/usr/bin/env python3
"""Stream Hyprland cursor coordinates without repeatedly spawning hyprctl."""

from __future__ import annotations

import json
import math
import os
from pathlib import Path
import socket
import sys
import time

MIN_INTERVAL_MS = 16
MAX_INTERVAL_MS = 1000
MAX_RESPONSE_BYTES = 64 * 1024


def positive_interval(raw: str) -> int:
    try:
        value = int(raw)
    except (TypeError, ValueError):
        value = 55
    return max(MIN_INTERVAL_MS, min(MAX_INTERVAL_MS, value))


def cursor_socket_path() -> Path:
    override = os.environ.get("BIG_CHEESE_CURSOR_SOCKET", "").strip()
    if override:
        return Path(override)

    runtime_dir = os.environ.get("XDG_RUNTIME_DIR", "").strip()
    signature = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE", "").strip()
    if not runtime_dir or not signature or "/" in signature or signature in {".", ".."}:
        raise RuntimeError("Hyprland cursor socket environment is unavailable")
    return Path(runtime_dir) / "hypr" / signature / ".socket.sock"


def query_cursor(path: Path) -> tuple[float, float, int]:
    started = time.monotonic_ns()
    chunks: list[bytes] = []
    total = 0

    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
        client.settimeout(1.0)
        client.connect(str(path))
        client.sendall(b"j/cursorpos")
        client.shutdown(socket.SHUT_WR)
        while True:
            chunk = client.recv(4096)
            if not chunk:
                break
            total += len(chunk)
            if total > MAX_RESPONSE_BYTES:
                raise RuntimeError("Hyprland cursor response is too large")
            chunks.append(chunk)

    payload = json.loads(b"".join(chunks).decode("utf-8"))
    x = payload.get("x")
    y = payload.get("y")
    if (
        isinstance(x, bool)
        or isinstance(y, bool)
        or not isinstance(x, (int, float))
        or not isinstance(y, (int, float))
        or not math.isfinite(x)
        or not math.isfinite(y)
    ):
        raise RuntimeError("Hyprland cursor response has invalid coordinates")

    latency_ms = max(0, round((time.monotonic_ns() - started) / 1_000_000))
    return float(x), float(y), latency_ms


def emit(payload: dict[str, object]) -> None:
    print(json.dumps(payload, separators=(",", ":")), flush=True)


def stream(interval_ms: int) -> None:
    path = cursor_socket_path()
    interval = interval_ms / 1000
    deadline = time.monotonic()

    while True:
        sampled_at_ms = round(time.time() * 1000)
        try:
            x, y, latency_ms = query_cursor(path)
            emit(
                {
                    "x": x,
                    "y": y,
                    "sampledAtMs": sampled_at_ms,
                    "latencyMs": latency_ms,
                }
            )
        except (OSError, UnicodeError, ValueError, RuntimeError) as error:
            emit({"error": str(error), "sampledAtMs": sampled_at_ms})

        deadline += interval
        now = time.monotonic()
        if deadline <= now:
            deadline = now
        else:
            time.sleep(deadline - now)


def main(argv: list[str]) -> int:
    interval_ms = positive_interval(argv[1] if len(argv) > 1 else "55")
    try:
        stream(interval_ms)
    except BrokenPipeError:
        devnull = os.open(os.devnull, os.O_WRONLY)
        os.dup2(devnull, sys.stdout.fileno())
        os.close(devnull)
        return 0
    except KeyboardInterrupt:
        return 0
    except RuntimeError as error:
        print(str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
