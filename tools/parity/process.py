"""Process control shared by the focused (`tools/check_regressions.py`) and
catalog (`tools/parity/gameplay.py`) Godot test runners.

Both runners start one engine process per test, stop it on the first runtime
diagnostic or at its timeout, and require the test's own unique summary line.
Keeping the rules here means a fix to one runner cannot drift from the other.
"""
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import time

DIAGNOSTIC = re.compile(r"^\s*(ERROR:|SCRIPT ERROR:|Parse Error:)", re.M)

# Rendered checks open the same window in both runners. 1280x800 keeps the
# original 800x600 interface at an integer-free but common 16:10 fit; a case
# may declare its own `resolution` when its assertions need another size.
RENDERED_RESOLUTION = "1280x800"


def rendered_arguments(rendering_method="gl_compatibility", resolution=RENDERED_RESOLUTION):
    """Engine flags for a real renderer on an explicitly selected private display.
    Pixel/UI checks must never silently fall back to the headless dummy renderer."""
    return ["--display-driver", "windows" if sys.platform == "win32" else "x11", "--rendering-method", rendering_method,
            "--windowed", "--resolution", resolution, "--position", "0,0"]


def run_program(argv, log, env, timeout, stop=None, grace=0.0, mirror=None, tolerate=None):
    """Run one test process, owning only its process group.

    The process ends early on the first runtime/script diagnostic in its
    output, when `timeout` seconds pass, or when the `stop` event is set
    (interrupt or another program's crash). With a positive `grace`, the group
    first receives SIGINT and gets that many seconds to finish on its own; a
    `gpu-lab run` wrapper cancels its remote job on SIGINT, which SIGKILL
    would leave running. `mirror(text)` may name a second file to scan for
    diagnostics (the remote job's live stdout, found from the wrapper's first
    lines). `tolerate` is a compiled pattern of complete diagnostic lines that
    do not end the process (a known infrastructure message the verdict judges
    with its context later). Only complete lines are judged, so a diagnostic
    split across two reads is seen whole. Returns (exit code, error message or
    None).
    """
    start = time.monotonic()
    error = None
    log = Path(log)
    with log.open("w", encoding="utf-8") as stream, log.open(encoding="utf-8", errors="replace") as reader:
        process = subprocess.Popen(argv, stdout=stream, stderr=subprocess.STDOUT, env=env,
                                   start_new_session=os.name == "posix",
                                   creationflags=subprocess.CREATE_NEW_PROCESS_GROUP if os.name == "nt" else 0)
        job = None
        if os.name == "nt":
            try:
                from windows_job import WindowsJob
                job = WindowsJob(process)
            except BaseException:
                subprocess.run(["taskkill", "/PID", str(process.pid), "/T", "/F"],
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
                process.wait()
                raise
        pending = ""
        head = ""
        mirrored, mirrored_at = None, 0
        try:
            while process.poll() is None:
                pending += reader.read()
                if mirror is not None and mirrored is None and len(head) < 65536:
                    head += pending
                    mirrored = mirror(head)
                if mirrored is not None and mirrored.is_file():
                    with mirrored.open(errors="replace") as remote:
                        remote.seek(mirrored_at)
                        chunk = remote.read()
                    mirrored_at += len(chunk.encode("utf-8", "replace"))
                    pending += chunk
                complete, _, pending = pending.rpartition("\n")
                if diagnostic_in(complete, tolerate):
                    error = "Runtime/script error; stopped this test process"
                    break
                if time.monotonic() - start > timeout:
                    error = f"Test exceeded {timeout} seconds"
                    break
                if stop is not None and stop.is_set():
                    error = "Run stopped before this test finished"
                    break
                time.sleep(0.1)
        finally:
            try:
                if process.poll() is None:
                    _end(process, grace, job)
                process.wait()
            finally:
                if job:
                    job.close()
    return process.returncode, error


def diagnostic_in(text, tolerate=None):
    """The first runtime/script diagnostic line in `text` that `tolerate` does not match."""
    for match in DIAGNOSTIC.finditer(text):
        line = text[match.start():].split("\n", 1)[0]
        if tolerate is None or not tolerate.match(line):
            return line
    return None


def _end(process, grace, job=None):
    try:
        if grace > 0:
            if job:
                process.send_signal(signal.CTRL_BREAK_EVENT)
            else:
                os.killpg(process.pid, signal.SIGINT)
            try:
                process.wait(timeout=grace)
                return
            except subprocess.TimeoutExpired:
                pass
        if job:
            job.terminate()
        else:
            os.killpg(process.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass


def parse_summary(text, marker, minimum):
    """Require the selected program's own unique terminal summary."""
    lines = [line[len(marker) + 1:] for line in text.splitlines() if line.startswith(marker + " ")]
    if len(lines) != 1:
        raise ValueError(f"Expected exactly one {marker} summary, found {len(lines)}")
    tail = lines[0].strip()
    if tail.startswith("{"):
        data = json.loads(tail)
        checks, failed = data["checks"], data["failures"]
        if isinstance(failed, list):
            failed = len(failed)
    else:
        found = (re.match(r"(\d+) checks\s+(\d+) failures(?:[;\s]|$)", tail)
                 or re.fullmatch(r"(\d+) checks;\s*failures=(\d+)", tail)
                 or re.match(r"checks=(\d+)\s+failures=(\d+)(?:\s|$)", tail))
        if not found:
            raise ValueError(f"Unrecognized {marker} summary")
        checks, failed = map(int, found.groups())
    if type(checks) is not int or type(failed) is not int or checks < minimum or not 0 <= failed <= checks:
        raise ValueError(f"Invalid/incomplete counts: checks={checks}, failures={failed}, minimum={minimum}")
    return {"checks": checks, "failures": failed}
