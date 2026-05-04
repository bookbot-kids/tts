"""Subprocess-isolated peak-RSS + wall-clock harness."""
import json
import os
import subprocess
import sys
import time

# Phonemizer (used by the Bookbot adapter) needs to find libespeak-ng at
# runtime. On macOS Homebrew it lives at /opt/homebrew/lib. Pre-populate the
# env var here so the orchestrator works without callers exporting it.
_DEFAULT_ESPEAK_LIB = "/opt/homebrew/lib/libespeak-ng.dylib"
if "PHONEMIZER_ESPEAK_LIBRARY" not in os.environ and os.path.exists(_DEFAULT_ESPEAK_LIB):
    os.environ["PHONEMIZER_ESPEAK_LIBRARY"] = _DEFAULT_ESPEAK_LIB


def run_in_subprocess(adapter_module: str, text: str, out_wav: str) -> dict:
    """Spawn a fresh ``python -c`` that imports the adapter, synthesizes, and
    prints a JSON result line. Sample RSS at 50 ms intervals via psutil from
    the parent so peak memory reflects only that engine's footprint
    (model load + one synthesis), not cumulative imports."""
    import psutil

    code = (
        "import json, sys; "
        f"from bench.adapters import {adapter_module} as a; "
        f"r = a.synthesize({text!r}, {out_wav!r}); "
        "print('___RESULT___' + json.dumps(r))"
    )
    t0 = time.perf_counter()
    p = subprocess.Popen(
        [sys.executable, "-c", code],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    proc = psutil.Process(p.pid)
    peak_rss = 0
    while p.poll() is None:
        try:
            peak_rss = max(peak_rss, proc.memory_info().rss)
        except psutil.NoSuchProcess:
            break
        time.sleep(0.05)
    out, err = p.communicate()
    wall = time.perf_counter() - t0
    if p.returncode != 0:
        raise RuntimeError(
            f"adapter {adapter_module} failed (exit {p.returncode}):\n{err.decode()}"
        )
    result_lines = [
        l for l in out.decode().splitlines() if l.startswith("___RESULT___")
    ]
    if not result_lines:
        raise RuntimeError(
            f"adapter {adapter_module} produced no result line. stdout:\n{out.decode()}\nstderr:\n{err.decode()}"
        )
    payload = json.loads(result_lines[-1].replace("___RESULT___", "", 1))
    payload["wall_seconds"] = wall
    payload["peak_rss_mb"] = peak_rss / (1024 * 1024)
    return payload
