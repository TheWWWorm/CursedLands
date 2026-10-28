#!/usr/bin/env python3
"""Run issue-linked Godot checks with isolated profiles and retained evidence.

Original game data is external. Rendered checks always use GPU Lab; this script
does not change the desktop or the player's settings. See docs/regression-checks.md.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "tools/parity"))
from gameplay import parse_summary

MANIFEST = REPO / "tools/regressions.json"
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
    return command + ["--display-driver", "x11", "--rendering-method",
                      case.get("rendering_method", "gl_compatibility"),
                      "--windowed", "--resolution", "1280x720"]


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


def verdict(log, case, returncode):
    """A clean exit alone is insufficient: require the named assertion result."""
    errors = []
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
        except (ValueError, TypeError) as error:
            errors.append(str(error))
    for index, line in enumerate(lines):
        if not re.match(r"^(?:SCRIPT ERROR:|ERROR:|FAIL\b)", line):
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
    except (ValueError, KeyError, TypeError) as error:
        errors.append(str(error))
    if returncode != 0:
        errors.append("Process exit: " + str(returncode))
    if summary is not None and summary["failures"]:
        errors.append("Assertion result does not satisfy the manifest")
    return {"passed": not errors, "result": summary, "errors": errors,
            "infrastructure_diagnostics": infrastructure}


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
    parser.add_argument("--list", action="store_true")
    args = parser.parse_args()
    cases = json.loads(MANIFEST.read_text(encoding="utf-8"))["cases"]
    unknown = set(args.only) - {case["id"] for case in cases}
    if unknown:
        parser.error("Unknown cases: " + ", ".join(sorted(unknown)))
    selected = [case for case in cases if (case["id"] in args.only if args.only else
                args.tier == "all" or case["mode"] == args.tier)]
    if args.list:
        for case in selected:
            print(f'{case["id"]:34} {case["mode"]:8} {case["contract"]}')
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
    # Validate the whole selection before running anything. Missing archives are
    # an error, not a silently omitted language or campaign.
    for case in selected:
        required = {case["data"] + "_data"}
        required.update(re.findall(r"\{(\w+)\}", " ".join(case.get("args", []))))
        for key in required:
            if key not in paths or not Path(paths[key]).exists():
                parser.error(f'{case["id"]} requires --{key.replace("_", "-")}')
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
        "game_source_sha256": source_hash.hexdigest(), "manifest_sha256": digest(MANIFEST),
        "engine": engine, "engine_sha256": digest(engine), "data": paths, "cases": [],
    }
    if args.packaged:
        report["pack"] = {"path": str(pack), "sha256": digest(pack)}
    # Tests are read-only, so one staged copy per run serves every case.
    scripts = stage_tests(output / "tools")
    for case in selected:
        profile = output / case["id"]
        settings = profile_settings(profile)
        settings.parent.mkdir(parents=True)
        settings.write_text(SETTINGS)
        isolated = isolation_environment(profile)
        command = engine_arguments(engine, case, args.packaged)
        script = scripts / Path(case["script"]).name
        expected = {"campaign": "cursed_lands" if case["data"] == "base" else "lost_in_astral",
                    "display": case["mode"], "script": str(script),
                    "profile": {"confine_mouse": 0, "show_fps": 1, "volume_sfx": 0,
                                "volume_stream": 0, "volume_voice": 0}}
        case = {**case, "expected_start": expected}
        command += ["--", "--no-movies", "--ei-path=" + paths[case["data"] + "_data"],
                    "--tool=" + str(REPO / "tools/parity/gameplay_bootstrap.gd"),
                    "--suite-script=" + expected["script"], "--suite-script-root=" + str(scripts),
                    "--suite-campaign=" + expected["campaign"], "--suite-display=" + case["mode"]]
        command += [arg.format(**paths) for arg in case.get("args", [])]
        timeout = case.get("timeout", 420)
        if case["mode"] == "rendered":
            command = [gpu_lab, "run", "--gpu", "auto", "--cwd", str(REPO), "--timeout", str(timeout),
                       "--", "env"] + [f"{key}={value}" for key, value in isolated.items()] + command
        started = time.monotonic()
        print("RUN", case["id"], flush=True)
        with (profile / "run.log").open("w") as stream:
            try:
                result = subprocess.run(command, cwd=REPO, env={**os.environ, **isolated},
                                        stdout=stream, stderr=subprocess.STDOUT,
                                        timeout=timeout + (600 if case["mode"] == "rendered" else 0))
                code = result.returncode
            except subprocess.TimeoutExpired:
                code = 124
        row = {"id": case["id"], "script": case["script"], "script_sha256": digest(REPO / case["script"]),
               "contract": case["contract"], "issues": case.get("issues", []), "mode": case["mode"],
               "seconds": round(time.monotonic() - started, 2), "command": command,
               "log": str(profile.relative_to(output) / "run.log"),
               **verdict((profile / "run.log").read_text(encoding="utf-8", errors="replace"), case, code)}
        report["cases"].append(row)
        report["passed"] = all(item["passed"] for item in report["cases"])
        (output / "results.json").write_text(json.dumps(report, indent=2) + "\n")
        print("PASS" if row["passed"] else "FAIL", case["id"], row["result"], flush=True)
        for error in row["errors"][:8]:
            print(" ", error, flush=True)
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    sys.exit(main())
