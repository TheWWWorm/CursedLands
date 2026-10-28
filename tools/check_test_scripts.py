#!/usr/bin/env python3
"""Parse every Godot test and benchmark script without game data.

Stages tools/tests and tools/benchmarks the way the regression runner does, so
`extends "res://tools/..."` resolves, then loads each script in one headless
engine process. A script that fails to parse or analyse (for example a `:=`
that infers Variant, which Godot 4.7 treats as an error) is reported with the
engine's own diagnostic. Needs only the engine and the repository.
"""
import argparse
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "tools"))
from check_regressions import stage_tests  # noqa: E402

PARSER = REPO / "tools/parity/parse_scripts.gd"
# Scripts that reference engine API added by the project's engine patches.
# They cannot load on the stock editor binary; pass --patched-engine when the
# engine under test carries those patches so they are required to load.
PATCHED_ENGINE_ONLY = {
    "d3d12_cold_menu_start.gd": "Viewport.SCALING_3D_MODE_DLSS from the restore-dlss engine patch",
}


def import_project(engine, timeout=900):
    """Build the project's import cache, which holds the global class-name
    table the analyser needs. A fresh clone has none; the step is idempotent."""
    subprocess.run([engine, "--headless", "--path", str(REPO / "game"), "--import"], cwd=REPO,
                   check=True, timeout=timeout, stdout=subprocess.DEVNULL, stderr=subprocess.STDOUT)


def run(engine, output=None, timeout=900):
    """Return (failed script names, engine diagnostics, raw log)."""
    with tempfile.TemporaryDirectory(prefix="parse-scripts-") as temporary:
        staged = stage_tests(Path(temporary) / "tools")
        command = [engine, "--headless", "--path", str(REPO / "game"), "--script", str(PARSER),
                   "--", "--scripts=" + staged.as_posix()]
        result = subprocess.run(command, cwd=REPO, text=True, timeout=timeout,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    log = result.stdout.replace(staged.as_posix() + "/", "")
    summary = None
    for line in log.splitlines():
        if line.startswith("PARSE_SCRIPTS "):
            summary = json.loads(line.removeprefix("PARSE_SCRIPTS "))
    if summary is None:
        raise RuntimeError("The parse pass did not finish:\n" + log[-4000:])
    diagnostics = [line for line in log.splitlines() if re.match(r"^(SCRIPT ERROR|ERROR):", line)
                   or line.startswith("          at: ")]
    if output:
        output.write_text(log, encoding="utf-8")
    return summary, diagnostics, log


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--engine", default="godot", help="Godot 4.7 executable (headless is enough)")
    parser.add_argument("--log", type=Path, help="write the complete engine output here")
    parser.add_argument("--timeout", type=int, default=900)
    parser.add_argument("--patched-engine", action="store_true",
                        help="the engine carries the project's engine patches; no script may be skipped")
    parser.add_argument("--import-first", action="store_true",
                        help="run the editor import step first (required on a fresh checkout)")
    args = parser.parse_args()
    engine = shutil.which(args.engine)
    if not engine:
        parser.error("Engine not found: " + args.engine)
    if args.import_first:
        import_project(engine, args.timeout)
    summary, diagnostics, _ = run(engine, args.log, args.timeout)
    skipped = [] if args.patched_engine else [name for name in summary["failed"] if name in PATCHED_ENGINE_ONLY]
    failed = [name for name in summary["failed"] if name not in skipped]
    print(f'Parsed {summary["scripts"]} scripts; {len(failed)} failed to load; '
          f'{len(skipped)} need the patched engine')
    for line in diagnostics:
        print(line)
    for name in skipped:
        print("SKIPPED", name, "-", PATCHED_ENGINE_ONLY[name])
    for name in failed:
        print("FAILED", name)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
