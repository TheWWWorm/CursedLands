#!/usr/bin/env python3
"""Run the focused Godot checks with isolated profiles and retained evidence.

The cases are the gameplay catalog entries that carry a `focused` ID
(tools/parity/gameplay_catalog.json): one registry for both runners, with the
same script, arguments, marker and `min_checks`. Original game data is external. Rendered checks always use GPU Lab; this script
does not change the desktop or the player's settings. Process control (stop on
the first diagnostic, timeouts, the summary-line contract and the rendered
window size) is shared with the gameplay catalog runner through
tools/parity/process.py. See docs/regression-checks.md.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
from contextlib import nullcontext
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import threading
import time

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "tools/parity"))
from gameplay import MemoryGate, TEXTS, auto_jobs, available_memory, catalog, jobs_argument, required_assets, uses_network
from process import DIAGNOSTIC, RENDERED_RESOLUTION, parse_summary, rendered_arguments, run_program

# One registry for both runners: a catalog entry with `focused` is also a case
# here, selected and reported under that short ID.
CATALOG = REPO / "tools/parity/gameplay_catalog.json"
DATA_OPTIONS = {"cursed_lands": "--base-data", "lost_in_astral": "--astral-data",
                **{"texts_" + language: "--texts-" + language for language in TEXTS}}
SETTINGS = """[options]
confine_mouse=0
show_fps=1
volume_sfx=0
volume_stream=0
volume_voice=0
auto_graphics=0
display_mode=0
fps_limit=1
net_directory=0
net_upnp=0
net_lan=0
"""
# `gpu-lab run` names its job on the first line and prints only a 64 KiB tail
# of the job's output at the end; the job directory holds the whole log.
GPU_LAB_JOB = re.compile(r"^GPU Lab job: (\w+)$", re.M)
# Seconds a rendered case may wait in the GPU Lab queue beyond its own timeout.
QUEUE_ALLOWANCE = 600
# GPU Lab virtual monitors have no EDID: the engine reports this refresh-rate
# diagnostic at start-up. `verdict` excuses it with its context line; the
# process control must not end the test when it appears.
INFRASTRUCTURE = re.compile(r'^ERROR: Parameter "monitors" is null\.$')


def focused_case(row):
    """A catalog entry in the shape this runner reports: the short `focused`
    ID, the catalog ID, the summary marker, the campaign and display, and the
    data roots the entry's campaign, companion archives and `texts` need."""
    needs = list(required_assets(row)) + ["texts_" + language for language in row.get("texts", [])]
    case = {"id": row["focused"], "catalog_id": row["id"], "script": row["script"], "summary": row["marker"],
            "contract": row["description"], "issues": list(row.get("issues", []) or []), "campaign": row["campaign"],
            "data": "base" if row["campaign"] == "cursed_lands" else "astral", "mode": row.get("display", "headless"),
            "args": list(row["args"]), "min_checks": row["min_checks"], "timeout": row["timeout"], "needs": needs}
    for key in ("rendering_method", "resolution"):
        if key in row:
            case[key] = row[key]
    return case


def focused_cases(path=None):
    return [focused_case(row) for row in catalog(path=path) if "focused" in row]


def digest(path):
    with open(path, "rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def profile_settings(profile):
    return profile / "data/godot/app_userdata/Cursed Lands/settings.cfg"


def isolation_environment(profile):
    """Linux reads XDG directories; Windows Godot resolves user:// from APPDATA."""
    return {"XDG_DATA_HOME": str(profile / "data"),
            "XDG_CONFIG_HOME": str(profile / "config"),
            "XDG_CACHE_HOME": str(profile / "cache"),
            "APPDATA": str(profile / "data"),
            "LOCALAPPDATA": str(profile / "local")}


def engine_arguments(engine, case, packaged=False):
    command = [engine]
    if not packaged:
        command += ["--path", str(REPO / "game")]
    command += ["--audio-driver", "Dummy", "--max-fps", "30"]
    if case["mode"] == "headless":
        # Match both production authority workers. The packaged Linux desktop
        # defaults to a separate render thread, which can fail dummy mesh disposal.
        return command + ["--headless", "--render-thread", "safe"]
    return command + rendered_arguments(case.get("rendering_method", "gl_compatibility"),
                                        case.get("resolution", RENDERED_RESOLUTION))


def stage_tests(destination):
    """Copy the test scripts, their fixtures and relative benchmark dependencies
    next to each other and point `res://tools/` imports at that copy.

    The Godot project root is `game/`, so `extends "res://tools/tests/..."`
    never resolves from the source tree or from a pack; staging is required in
    both modes, not only for packaged runs."""
    for name in ("tests", "benchmarks"):
        shutil.copytree(REPO / "tools" / name, destination / name,
                        ignore=shutil.ignore_patterns("__pycache__", "*.pyc"))
    # A few tests extend the wiki export tools that live directly under tools/.
    for script in (REPO / "tools").glob("*.gd"):
        shutil.copy2(script, destination / script.name)
    for script in destination.rglob("*.gd"):
        text = script.read_text(encoding="utf-8")
        script.write_text(text.replace("res://tools/", destination.as_posix() + "/"), encoding="utf-8")
    return destination / "tests"


def verdict(log, case, returncode, error=None):
    """A clean exit alone is insufficient: require the named assertion result."""
    errors = [error] if error else []
    infrastructure = []
    lines = log.splitlines()
    if case.get("expected_start"):
        starts = [line.removeprefix("GAMEPLAY_SUITE_START ") for line in lines
                  if line.startswith("GAMEPLAY_SUITE_START ")]
        try:
            if len(starts) != 1:
                raise ValueError("Missing or repeated profile/campaign confirmation")
            actual = json.loads(starts[0])
            if any(actual.get(key) != value for key, value in case["expected_start"].items()):
                raise ValueError("Wrong profile, campaign, script or display")
        except (ValueError, TypeError) as exc:
            errors.append(str(exc))
    for index, line in enumerate(lines):
        if not (DIAGNOSTIC.match(line) or re.match(r"FAIL\b", line)):
            continue
        # GPU Lab virtual monitors have no EDID. Keep this exact, observed
        # refresh-rate diagnostic visible without disguising game failures.
        context = lines[index + 1] if index + 1 < len(lines) else ""
        if (case["mode"] == "rendered" and line == 'ERROR: Parameter "monitors" is null.'
                and "at: screen_get_refresh_rate (platform/linuxbsd/x11/" in context):
            infrastructure.append(line + " " + context.strip())
        else:
            errors.append(line)
    summary = None
    try:
        summary = parse_summary(log, case["summary"], case["min_checks"])
    except (ValueError, KeyError, TypeError) as exc:
        errors.append(str(exc))
    if returncode != 0:
        errors.append("Process exit: " + str(returncode))
    if summary is not None and summary["failures"]:
        errors.append("Assertion result does not satisfy the manifest")
    return {"passed": not errors, "result": summary, "errors": errors,
            "infrastructure_diagnostics": infrastructure}


def gpu_lab_job_directory(gpu_lab, text):
    """The retained log folder of the job that `gpu-lab run` announced."""
    found = GPU_LAB_JOB.search(text)
    if not found:
        return None
    try:
        info = json.loads(subprocess.check_output([gpu_lab, "job", found.group(1)], text=True))
        directory = info.get("directory")
    except (subprocess.CalledProcessError, OSError, ValueError, AttributeError):
        return None
    return Path(directory) if directory else None


def gpu_lab_stdout(gpu_lab, text):
    directory = gpu_lab_job_directory(gpu_lab, text)
    return directory / "stdout.log" if directory else None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--engine", default="godot", help="Godot executable, preferably the release engine")
    parser.add_argument("--packaged", action="store_true",
                        help="Test the engine's adjacent exported PCK; stage external test scripts")
    parser.add_argument("--base-data", type=Path)
    parser.add_argument("--astral-data", type=Path)
    for language in ("en", "ru", "de"):
        parser.add_argument("--texts-" + language, type=Path)
    parser.add_argument("--tier", choices=("headless", "rendered", "all"), default="headless")
    parser.add_argument("--only", action="append", default=[], help="case ID; repeat to select several")
    parser.add_argument("--output", type=Path, help="new directory for profiles, logs and results.json")
    parser.add_argument("--jobs", type=jobs_argument, default=1,
                        help="cases to run at once (a number, or auto for CPU threads and free memory); "
                             "each keeps its own process and profile, and GPU Lab queues rendered cases")
    parser.add_argument("--list", action="store_true")
    args = parser.parse_args()
    cases = focused_cases(CATALOG)
    unknown = set(args.only) - {case["id"] for case in cases} - {case["catalog_id"] for case in cases}
    if unknown:
        parser.error("Unknown cases: " + ", ".join(sorted(unknown)))
    selected = [case for case in cases if ((case["id"] in args.only or case["catalog_id"] in args.only) if args.only
                else args.tier == "all" or case["mode"] == args.tier)]
    if args.list:
        for case in selected:
            print(f'{case["id"]:34} {case["mode"]:8} {case["catalog_id"]:44} {case["contract"]}')
        return 0
    if not args.output:
        parser.error("--output must name a new directory")
    engine = shutil.which(args.engine)
    if not engine:
        parser.error("Engine not found: " + args.engine)
    pack = Path(engine).with_suffix(".pck")
    if args.packaged and not pack.is_file():
        parser.error("--packaged requires an adjacent PCK: " + str(pack))
    paths = {key: str(value.resolve()) for key, value in vars(args).items()
             if isinstance(value, Path) and key != "output"}
    roots = {"cursed_lands": paths.get("base_data"), "lost_in_astral": paths.get("astral_data"),
             **{"texts_" + language: paths.get("texts_" + language) for language in TEXTS}}
    roots = {key: value for key, value in roots.items() if value}
    # Validate the whole selection before running anything. Missing archives are
    # an error, not a silently omitted language or campaign.
    for case in selected:
        for key in case["needs"]:
            if key not in roots or not Path(roots[key]).exists():
                parser.error(f'{case["id"]} requires {DATA_OPTIONS[key]}')
        if not (REPO / case["script"]).is_file():
            parser.error("Missing script: " + case["script"])
    gpu_lab = shutil.which("gpu-lab")
    if any(case["mode"] == "rendered" for case in selected) and not gpu_lab:
        parser.error("Rendered cases require GPU Lab")
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    source_hash = hashlib.sha256()
    for path in sorted((REPO / "game").rglob("*.gd")):
        if ".godot" not in path.parts:
            source_hash.update(str(path.relative_to(REPO)).encode())
            source_hash.update(path.read_bytes())
    source_hash.update((REPO / "game/project.godot").read_bytes())
    report = {
        "git_head": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=REPO, text=True).strip(),
        "game_source_sha256": source_hash.hexdigest(), "catalog_sha256": digest(CATALOG),
        "engine": engine, "engine_sha256": digest(engine), "data": paths, "cases": [],
    }
    if args.packaged:
        report["pack"] = {"path": str(pack), "sha256": digest(pack)}
    # Tests are read-only, so one staged copy per run serves every case.
    scripts = stage_tests(output / "tools")
    jobs = min(len(selected), auto_jobs(available=available_memory()) if args.jobs == "auto" else args.jobs)
    report["jobs"] = jobs
    stop = threading.Event()
    network_lock = threading.Lock()
    memory = MemoryGate(stop)
    results = {}
    lock = threading.Lock()

    def run_case(case):
        profile = output / case["id"]
        settings = profile_settings(profile)
        settings.parent.mkdir(parents=True)
        settings.write_text(SETTINGS)
        isolated = isolation_environment(profile)
        command = engine_arguments(engine, case, args.packaged)
        script = scripts / Path(case["script"]).name
        expected = {"campaign": case["campaign"], "display": case["mode"], "script": str(script),
                    "profile": {"confine_mouse": 0, "show_fps": 1, "volume_sfx": 0,
                                "volume_stream": 0, "volume_voice": 0}}
        spec = {**case, "expected_start": expected}
        command += ["--", "--no-movies", "--ei-path=" + roots[case["campaign"]],
                    "--tool=" + str(REPO / "tools/parity/gameplay_bootstrap.gd"),
                    "--suite-script=" + expected["script"], "--suite-script-root=" + str(scripts),
                    "--suite-campaign=" + expected["campaign"], "--suite-display=" + case["mode"]]
        command += [arg.format(**roots) for arg in case["args"]]
        timeout = case["timeout"]
        rendered = case["mode"] == "rendered"
        if rendered:
            command = [gpu_lab, "run", "--gpu", "auto", "--cwd", str(REPO), "--timeout", str(timeout),
                       "--", "env"] + [f"{key}={value}" for key, value in isolated.items()] + command
        log = profile / "run.log"
        # Cases that open the fixed game ports never overlap one another.
        networked = jobs > 1 and uses_network(script, REPO / "game")
        print("RUN", case["id"], flush=True)
        started = time.monotonic()
        with network_lock if networked else nullcontext(), memory:
            code, error = run_program(command, log, {**os.environ, **isolated},
                                      timeout + (QUEUE_ALLOWANCE if rendered else 0), stop,
                                      grace=10.0 if rendered else 0.0,
                                      mirror=(lambda text: gpu_lab_stdout(gpu_lab, text)) if rendered else None,
                                      tolerate=INFRASTRUCTURE if rendered else None)
        text = log.read_text(encoding="utf-8", errors="replace")
        if rendered:
            # Keep the wrapper's own output; judge the job's complete log.
            directory = gpu_lab_job_directory(gpu_lab, text)
            if directory and (directory / "stdout.log").is_file():
                (profile / "gpu-lab.log").write_text(text)
                text = "".join((directory / name).read_text(encoding="utf-8", errors="replace")
                               for name in ("stdout.log", "stderr.log") if (directory / name).is_file())
                log.write_text(text)
        return {"id": case["id"], "catalog_id": case["catalog_id"], "script": case["script"],
                "script_sha256": digest(REPO / case["script"]),
                "contract": case["contract"], "issues": case["issues"], "mode": case["mode"],
                "seconds": round(time.monotonic() - started, 2), "command": command,
                "log": str(profile.relative_to(output) / "run.log"),
                **verdict(text, spec, code, error)}

    def record(index, row):
        with lock:
            results[index] = row
            report["cases"] = [results[i] for i in sorted(results)]
            report["passed"] = all(item["passed"] for item in report["cases"])
            (output / "results.json").write_text(json.dumps(report, indent=2) + "\n")
            print("PASS" if row["passed"] else "FAIL", row["id"], row["result"], flush=True)
            for error in row["errors"][:8]:
                print(" ", error, flush=True)

    pool = ThreadPoolExecutor(max_workers=jobs)
    try:
        futures = {pool.submit(run_case, case): index for index, case in enumerate(selected)}
        for future in as_completed(futures):
            record(futures[future], future.result())
    except BaseException:
        # Ctrl-C or a runner error stops the whole selection: queued cases
        # never start and running ones are ended by run_program.
        stop.set()
        raise
    finally:
        pool.shutdown(wait=True, cancel_futures=True)
    report["complete"] = len(report["cases"]) == len(selected)
    (output / "results.json").write_text(json.dumps(report, indent=2) + "\n")
    return 0 if report["passed"] and report["complete"] else 1


if __name__ == "__main__":
    sys.exit(main())
