#!/usr/bin/env python3
"""Measure what a rebuild actually costs, by edit depth, plus a cold build.

The development loop is: save an edit, rebuild, restart/reload, see the change. This script prices the
rebuild half of that, and does it by *edit depth* so the growth question ("what does an edit cost as the
application grows?") has a number instead of a guess:

  - no-op: nothing changed, everything cached — the floor (process start plus build graph)
  - page: the embedded HTML changes, so no Zig is recompiled at all
  - slice module, example, core library file: progressively deeper Zig compilation

If the page row costs as much as the core library row, then compilation is not what the loop pays for and
optimising the compiler is the wrong lever. That is the case here.

Every probe appends a comment and restores the file from an in-memory copy, so the working tree is left
exactly as found and no measurement can be mistaken for a real edit.

Usage: python3 scripts/build_profile.py [--step example-webtransport_tasks]
"""

from __future__ import annotations

import argparse
import os
import pathlib
import subprocess
import time


def timed_build(args: list[str], step: str) -> tuple[float, bool]:
    t = time.perf_counter()
    result = subprocess.run(
        ["zig", "build", step, *args], capture_output=True, text=True, env=dict(os.environ)
    )
    return (time.perf_counter() - t) * 1000, result.returncode == 0


def with_probe(path: str, marker: str, body) -> None:
    """Run body() with path temporarily modified, restoring it from memory afterwards."""
    file = pathlib.Path(path)
    original = file.read_text()
    try:
        file.write_text(original + f"\n// {marker}\n")
        body()
    finally:
        file.write_text(original)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--step", default="example-webtransport_tasks", help="the build step to time")
    parser.add_argument(
        "--probes",
        default="examples/tls/webtransport_tasks.html,examples/durable/tasks.zig,"
        "examples/tls/webtransport_tasks.zig,src/udp/http3/Http3.zig",
        help="files to edit, shallowest first",
    )
    args = parser.parse_args()

    results: list[tuple[str, float, bool]] = []

    dt, ok = timed_build([], args.step)
    results.append(("no-op (everything cached)", dt, ok))

    for probe in args.probes.split(","):
        if not pathlib.Path(probe).exists():
            results.append((f"edit: {probe} (missing)", 0.0, False))
            continue
        holder: list[tuple[float, bool]] = []
        with_probe(probe, "build profile probe", lambda: holder.append(timed_build([], args.step)))
        dt, ok = holder[0]
        results.append((f"edit: {probe}", dt, ok))

    cache = "/tmp/zix-build-profile-cache"
    prefix = "/tmp/zix-build-profile-out"
    subprocess.run(["rm", "-rf", cache, prefix], check=False)
    dt, ok = timed_build(["--cache-dir", cache, "--prefix", prefix], args.step)
    results.append(("cold (fresh local cache, warm global)", dt, ok))

    print("| edit depth | ms | ok |")
    print("|---|---|---|")
    for name, dt, ok in results:
        print(f"| {name} | {dt:.0f} | {ok} |")

    version = subprocess.run(["zig", "version"], capture_output=True, text=True).stdout.strip()
    print(f"\nzig: {version}")

    verbose = subprocess.run(
        ["zig", "build", "--verbose", args.step], capture_output=True, text=True
    )
    commands = [
        line for line in (verbose.stderr + verbose.stdout).splitlines()
        if "build-exe" in line or "build-lib" in line
    ]
    if commands:
        line = commands[0]
        print("backend: LLVM" if "-fno-llvm" not in line else "backend: self-hosted (-fno-llvm)")
        print("linker: " + ("explicit -fuse-ld" if "-fuse-ld" in line else "zig default (bundled LLD)"))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
