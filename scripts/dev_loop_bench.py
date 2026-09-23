#!/usr/bin/env python3
"""Development-loop benchmark: source save -> visible browser change on the durable slice.

What it measures, for one iteration:
  t0  the file write (the "save")
      `zig build example-webtransport_tasks`            build (compile + link)
      server restart                                    the old process is stopped, the new one is up
      browser reload + the durable round trip           the page reloads when the version it polls
                                                        changes, dials a session, subscribes, submits a
                                                        durable action, waits for the completion patch, and
                                                        reports what it rendered
  t1  the server prints `[devloop] verified ...`

The stopwatch ends on the *browser's* report, never on the compiler's exit code: a build that finishes and a
page nobody reloaded is not a development loop. Chromium stays open across iterations (the page reloads
itself when the served page's version changes), so each iteration pays reload and reconnection, not browser
startup.

Three edits, each with its own observable:
  handler  a change in the WebTransport handler's reply, plus the build token the page renders
  render   a change in the page's own markup and the mark it renders
  type     a change to the shared slice's `Task` type (which forces the module, the example and the suite to
           rebuild) plus the build token

Usage:
  python3 scripts/dev_loop_bench.py --reps 5 --json out.json
  python3 scripts/dev_loop_bench.py --kinds handler --reps 3 --keep-going

Needs: a built `zig build example-webtransport_tasks`, the same PostgreSQL the example uses, and Chromium
(the harness installs one; pass --chrome to point elsewhere).
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import statistics
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
EXAMPLE = ROOT / "examples" / "tls" / "webtransport_tasks.zig"
PAGE = ROOT / "examples" / "tls" / "webtransport_tasks.html"
SLICE = ROOT / "examples" / "durable" / "tasks.zig"
SERVER = ROOT / "zig-out" / "bin" / "zix-example-webtransport_tasks-x86_64-linux-debug"
CHROME = Path(
    os.environ.get("ZIX_CHROME", "/home/autark/.omp/puppeteer/chrome/linux-150.0.7871.24/chrome-linux64/chrome")
)
SPKI = "icvjpo9jth21Jte9ZDs5vIYTVbMdL4UUewni7JD1ZsI="
PORT = 9444

# Each edit is a list of (file, old, new) where `new` may carry a {mark} the runner fills in per iteration.
EDITS = {
    "handler": [
        (
            EXAMPLE,
            'const dev_token: []const u8 = "d0";',
            'const dev_token: []const u8 = "{mark}";',
        ),
        (
            EXAMPLE,
            '"{{\\"kind\\":\\"accepted\\",\\"task_id\\":{d},\\"rev\\":{d},\\"duplicate\\":{}}}\\n"',
            '"{{\\"kind\\":\\"accepted\\",\\"task_id\\":{d},\\"rev\\":{d},\\"duplicate\\":{},\\"dev\\":\\"{mark}\\"}}\\n"',
        ),
    ],
    "render": [
        (
            PAGE,
            'const DEV_MARK = "m0";',
            'const DEV_MARK = "{mark}";',
        ),
        (
            PAGE,
            "<h1>zix · durable tasks</h1>",
            "<h1>zix · durable tasks · {mark}</h1>",
        ),
    ],
    "type": [
        (
            EXAMPLE,
            'const dev_token: []const u8 = "d0";',
            'const dev_token: []const u8 = "{mark}";',
        ),
        (
            SLICE,
            "pub const Task = struct {\n    id: i64,",
            "pub const Task = struct {\n    id: i64,\n    created_rev: i64,",
        ),
        (
            SLICE,
            "\\\\SELECT id::int8 AS id, title, state, attempts::int8 AS attempts, result",
            "\\\\SELECT id::int8 AS id, created_rev::int8 AS created_rev, title, state, attempts::int8 AS attempts, result",
        ),
        (
            SLICE,
            "                .id = try row.get(i64, 0),\n                .title = try arena.dupe(u8, try row.get([]const u8, 1)),",
            "                .id = try row.get(i64, 0),\n                .created_rev = try row.get(i64, 1),\n                .title = try arena.dupe(u8, try row.get([]const u8, 2)),",
        ),
        (
            SLICE,
            "                .state = try arena.dupe(u8, try row.get([]const u8, 2)),\n                .attempts = try row.get(i64, 3),\n                .result = if (try row.get(?[]const u8, 4)) |text| try arena.dupe(u8, text) else null,",
            "                .state = try arena.dupe(u8, try row.get([]const u8, 3)),\n                .attempts = try row.get(i64, 4),\n                .result = if (try row.get(?[]const u8, 5)) |text| try arena.dupe(u8, text) else null,",
        ),
        (
            EXAMPLE,
            ',\\"state\\":\\"{s}\\",\\"attempts\\":{d},\\"result\\":", .{ task.state, task.attempts }',
            ',\\"created_rev\\":{d},\\"state\\":\\"{s}\\",\\"attempts\\":{d},\\"result\\":", .{ task.created_rev, task.state, task.attempts }',
        ),
    ],
}


def metadata(chrome_path: Path) -> dict:
    zig = shutil.which("zig")
    version = subprocess.run([zig, "version"], capture_output=True, text=True).stdout.strip() if zig else "?"
    real = os.path.realpath(zig) if zig else "?"
    cache = ROOT / ".zig-cache"
    cache_bytes = sum(f.stat().st_size for f in cache.rglob("*") if f.is_file()) if cache.exists() else 0

    return {
        "toolchain": {"zig": version, "wrapper": "anyzig", "resolved": real},
        "build": {"step": "zig build example-webtransport_tasks", "optimize": "Debug"},
        "backend": {"page": "HTTPS/1.1 over TCP", "session": "HTTP/3 over QUIC (UDP), same port"},
        "hardware": {
            "kernel": os.uname().release,
            "machine": os.uname().machine,
            "cpus": os.cpu_count(),
            "note": "WSL2 on Windows, local loopback",
        },
        "cache": {"dir": str(cache), "warm": cache.exists(), "bytes": cache_bytes},
        "browser": {
            "path": str(chrome_path),
            "flags": [
                "--ignore-certificate-errors",
                f"--ignore-certificate-errors-spki-list={SPKI}",
                f"--origin-to-force-quic-on=127.0.0.1:{PORT}",
            ],
            "note": "one instance for the whole run: the page reloads itself, so iterations pay reload, not launch",
        },
        "commit": subprocess.run(["git", "-C", str(ROOT), "rev-parse", "--short", "HEAD"], capture_output=True, text=True).stdout.strip(),
    }


class Server:
    def __init__(self, log_path: Path):
        self.log_path = log_path
        self.process: subprocess.Popen | None = None

    def start(self) -> float:
        started = time.monotonic()
        log = self.log_path.open("ab")
        self.process = subprocess.Popen([str(SERVER)], cwd=ROOT, stdout=log, stderr=log)

        deadline = time.monotonic() + 20
        while time.monotonic() < deadline:
            if "page https://" in self.log_path.read_text(errors="ignore"):
                return (time.monotonic() - started) * 1000
            time.sleep(0.01)

        raise TimeoutError("server never became ready")

    def stop(self) -> None:
        if self.process is None:
            return
        self.process.terminate()
        try:
            self.process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            self.process.kill()
        self.process = None

    def wait_for(self, needle: str, offset: int, timeout: float, started: float) -> float:
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            text = self.log_path.read_text(errors="ignore")
            index = text.find(needle, offset)
            if index >= 0:
                return (time.monotonic() - started) * 1000
            time.sleep(0.005)

        raise TimeoutError(f"browser never verified {needle!r}")


def touched_files() -> list[Path]:
    return sorted({path for edits in EDITS.values() for path, _, _ in edits})


class Editor:
    """Apply an edit and put the file back exactly as it was, from a copy taken in memory.

    Note:
    - Restoring through git would throw away whatever the developer had not committed, so the baseline is
      read from the working tree at the start and written back at the end, byte for byte.
    """

    def __init__(self) -> None:
        self.original = {path: path.read_bytes() for path in touched_files()}

    def apply(self, kind: str, mark: str) -> None:
        for path, old, new in EDITS[kind]:
            text = path.read_text()
            if old not in text:
                raise SystemExit(f"{path}: edit anchor not found for {kind}")
            path.write_text(text.replace(old, new, 1))

    def restore(self) -> None:
        for path, content in self.original.items():
            path.write_bytes(content)


def percentile(values: list[float], fraction: float) -> float:
    if not values:
        return 0.0
    ordered = sorted(values)
    return ordered[min(len(ordered) - 1, int(round(fraction * (len(ordered) - 1))))]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--reps", type=int, default=5)
    parser.add_argument("--kinds", default="handler,render,type")
    parser.add_argument("--timeout", type=float, default=120.0, help="seconds one iteration may take")
    parser.add_argument("--json", default="")
    parser.add_argument("--chrome", default=str(CHROME))
    args = parser.parse_args()

    chrome_path = Path(args.chrome)
    if not chrome_path.exists():
        raise SystemExit(f"chromium not found at {chrome_path}: pass --chrome")

    if not SERVER.exists():
        raise SystemExit(f"{SERVER} is missing: run `zig build example-webtransport_tasks` first")

    log_path = Path("/tmp/dev-loop-server.log")
    log_path.write_text("")
    server = Server(log_path)

    print("starting the browser (it stays open for the whole run)")
    browser = subprocess.Popen(
        [
            str(chrome_path),
            "--headless=new",
            "--no-sandbox",
            "--disable-dev-shm-usage",
            f"--user-data-dir=/tmp/dev-loop-profile-{os.getpid()}",
            "--ignore-certificate-errors",
            f"--ignore-certificate-errors-spki-list={SPKI}",
            f"--origin-to-force-quic-on=127.0.0.1:{PORT}",
            f"https://127.0.0.1:{PORT}/?devloop",
        ],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )

    editor = Editor()
    results: dict[str, dict[str, list[float]]] = {}
    try:
        for kind in args.kinds.split(","):
            kind = kind.strip()
            if kind not in EDITS:
                raise SystemExit(f"unknown edit kind {kind!r}")

            measured = {"build": [], "restart": [], "verify": [], "total": []}
            results[kind] = measured
            print(f"\n== {kind}: {args.reps} iterations ==")

            for iteration in range(args.reps):
                mark = f"{kind[0]}{iteration + 1}"
                editor.restore()
                log_path.write_text("")
                server.stop()
                server.start()  # a warm server so the page's polls survive the iteration's own restart
                time.sleep(0.2)

                # The stopwatch starts here, at the file write, exactly as a developer experiences it.
                started = time.monotonic()
                editor.apply(kind, mark)

                build = subprocess.run(
                    ["zig", "build", "example-webtransport_tasks"],
                    cwd=ROOT,
                    capture_output=True,
                    text=True,
                )
                if build.returncode != 0:
                    print(build.stderr[-2000:])
                    raise SystemExit(f"build failed for {kind} #{iteration + 1}")
                build_ms = (time.monotonic() - started) * 1000

                # Restart onto the new binary. The browser keeps polling through the gap, reloads when the
                # version changes, and its report below is what the stopwatch ends on.
                fresh = log_path.stat().st_size
                server.stop()
                restart_ms = server.start()

                total = server.wait_for(f"verified token={mark}&mark={mark}", fresh, args.timeout, started)

                measured["build"].append(build_ms)
                measured["restart"].append(restart_ms)
                measured["verify"].append((total - build_ms - restart_ms))
                measured["total"].append(total)
                print(f"  #{iteration + 1}: total {total:7.0f}ms  (build {build_ms:6.0f}  restart {restart_ms:5.0f}  reload+verify {total - build_ms - restart_ms:6.0f})")
    finally:
        server.stop()
        browser.terminate()
        try:
            browser.wait(timeout=5)
        except subprocess.TimeoutExpired:
            browser.kill()
        editor.restore()

    print("\n=== development loop: save -> visible browser change ===")
    for kind, measured in results.items():
        print(f"\n{kind}:")
        for phase in ("build", "restart", "verify", "total"):
            values = measured[phase]
            print(
                f"  {phase:8s} n={len(values)}  mean={statistics.fmean(values):7.0f}ms  "
                f"p50={percentile(values, 0.50):7.0f}ms  p90={percentile(values, 0.90):7.0f}ms  "
                f"p99={percentile(values, 0.99):7.0f}ms  max={max(values):7.0f}ms"
            )

    report = {"metadata": metadata(chrome_path), "results": results}
    if args.json:
        Path(args.json).write_text(json.dumps(report, indent=2))
        print(f"\nwrote {args.json}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
