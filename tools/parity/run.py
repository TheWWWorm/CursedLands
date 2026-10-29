#!/usr/bin/env python3
"""Capture the original and remake independently, then report first divergences.

Exit 0: every selected observation matches. Exit 1: behavioral differences.
Exit 2: invalid inputs, missing coverage, nondeterminism, or a capture failure.
Requires the user's original game installation; no game files are distributed.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import signal
import subprocess
import sys
import time
import xml.etree.ElementTree as ET

from cases import REFERENCES, contracts_for, make_inputs
from compare import canonical, compare, digest, first_difference, validate_trace

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
PROFILE = {"confine_mouse": 0, "show_fps": 1, "volume_sfx": 0, "volume_stream": 0, "volume_voice": 0}


def file_hash(path):
    with Path(path).open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def write_json(path, data):
    Path(path).write_text(json.dumps(data, indent=2, allow_nan=False, ensure_ascii=False) + "\n")


def command(args, log, env, timeout, import_bootstrap=False):
    """Own and reap just this subprocess group, including on interruption."""
    start = time.monotonic()
    with log.open("w") as stream:
        process = subprocess.Popen(args, stdout=stream, stderr=subprocess.STDOUT, env=env,
                                   start_new_session=os.name == "posix")
        try:
            code = process.wait(timeout=timeout)
        except BaseException:
            if process.poll() is None:
                if os.name == "posix":
                    os.killpg(process.pid, signal.SIGKILL)
                else:
                    process.kill()
                process.wait()
            raise
    text = log.read_text(errors="replace")
    if code:
        raise RuntimeError(f"Command exited {code}; see {log.name}\n" + text[-1800:])
    diagnostics = [line for line in text.splitlines() if line.startswith(("ERROR:", "SCRIPT ERROR:", "Parse Error:"))]
    if diagnostics and not import_bootstrap:
        raise RuntimeError(f"Runtime errors in {log.name}; a nominal zero exit is not a passing capture")
    return {"argv": args, "seconds": round(time.monotonic() - start, 3), "exit_code": code,
            "log": log.name, "log_sha256": file_hash(log), "diagnostics": diagnostics}


def isolated_environment(directory, project_name, data):
    profile = directory / "data" / "godot" / "app_userdata" / project_name
    profile.mkdir(parents=True)
    settings = "[game]\nroot=" + json.dumps(str(data)) + "\ndifficulty=0\n\n[options]\n"
    settings += "".join(f"{key}={value}\n" for key, value in PROFILE.items())
    # A preexisting player's preferences are never read or copied.
    (profile / "settings.cfg").write_text(settings)
    return dict(os.environ, XDG_DATA_HOME=str(directory / "data"),
                XDG_CONFIG_HOME=str(directory / "config"), XDG_CACHE_HOME=str(directory / "cache"),
                APPDATA=str(directory / "data"), LOCALAPPDATA=str(directory / "local"),
                EI_FIXED_FPS="60")


def stage_game(source, output):
    runtime = output / "runtime"
    shutil.copytree(source, runtime, ignore=shutil.ignore_patterns(".godot", "*.log", "__pycache__"))
    (runtime / "tools").mkdir(exist_ok=True)
    shutil.copy2(HERE / "remake_trace.gd", runtime / "tools" / "parity_trace.gd")
    from extensions import remake_scripts
    if remake_scripts():
        (runtime / "tools" / "parity_ext").mkdir()
    for script in remake_scripts():
        shutil.copy2(script, runtime / "tools" / "parity_ext" / script.name.removeprefix("remake_ext_"))
    manifest = {p.relative_to(runtime).as_posix(): file_hash(p) for p in sorted(runtime.rglob("*")) if p.is_file()}
    write_json(output / "runtime-source.json", manifest)
    return runtime, digest(manifest)


def check_inputs(inputs):
    reference = inputs.get("reference", {})
    campaign = reference.get("campaign")
    if inputs.get("schema") != 1 or campaign not in REFERENCES or reference != REFERENCES[campaign]:
        raise ValueError("Unsupported input schema/reference")
    contracts = contracts_for(campaign)
    rows = inputs.get("scenarios", [])
    if not rows or len({r["id"] for r in rows}) != len(rows):
        raise ValueError("Scenario IDs must be nonempty and unique")
    for row in rows:
        if row["kind"] not in contracts or inputs["contracts"].get(row["kind"]) != contracts[row["kind"]]:
            raise ValueError(f"Unrecognized or modified contract for {row['id']}")
        if row["kind"] == "cast_rank":
            heights = {}
            for unit in row["inputs"]["units"]:
                x, y, z = unit["pos"]
                if (x, y) in heights and heights[(x, y)] != z:
                    raise ValueError(f"{row['id']}: multiple ground heights at one XY are unsupported by this fixture")
                heights[(x, y)] = z
    canonical(inputs)


def report_text(report, inputs):
    counts = report["counts"]
    lines = [
        "# Original-versus-remake comparison", "",
        f"Result: **{report['status']}**. {counts['matches']} matching scenarios; "
        f"{counts['mismatches']} differing scenarios; {counts['original_steps']} original observations.",
        "", f"Reference: `{report['reference']['executable_sha256']}`.",
        "", "These are bounded subsystem replays with declared supplied boundaries. They do not establish "
        "a complete campaign, save/load, multiplayer or graphical match.",
        "", "The original capture executes the user's x86 instructions in Unicorn. The remake capture calls "
        "production game methods and receives only inputs. No mismatch is automatically approved.", "",
        "| Scenario | First difference | Original | Remake |", "|---|---|---|---|",
    ]
    for row in report["scenarios"]:
        if row["status"] == "match":
            continue
        diff = row["first_divergence"]
        lines.append(f"| `{row['id']}` | `{diff['field']}` | `{diff.get('expected', diff.get('expected_length', diff.get('missing')))}` | `{diff.get('actual', diff.get('actual_length', diff.get('extra')))}` |")
    lines += ["", "## Coverage contracts", ""]
    for kind, contract in inputs["contracts"].items():
        lines += [f"### {kind}", "", contract["scope"], "", "Supplied boundaries: " + "; ".join(contract["stubs"]) + ".",
                  "", contract["limits"], "", "Tolerances: `" + json.dumps(contract["tolerances"]) + "`.", ""]
    lines += ["## Reproduction", "", "Exact inputs are in `inputs.json`. Run `reproduce.sh NEW_OUTPUT_DIRECTORY` "
              "to repeat the captured scenarios against the current source; add `--case SCENARIO_ID` to narrow the run.",
              "The retained `runtime/` directory and `runtime-source.json` identify the source actually tested.", ""]
    return "\n".join(lines)


def junit(report, output):
    suite = ET.Element("testsuite", name="original-parity", tests=str(report["counts"]["scenarios"]),
                       failures=str(report["counts"]["mismatches"]), errors="0")
    for row in report["scenarios"]:
        case = ET.SubElement(suite, "testcase", classname=row["kind"], name=row["id"])
        if row["status"] != "match":
            diff = row["first_divergence"]
            failure = ET.SubElement(case, "failure", message=diff["field"])
            failure.text = json.dumps(diff, indent=2)
    ET.ElementTree(suite).write(output, encoding="utf-8", xml_declaration=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--game-dir", type=Path, help="Owned original game folder containing game.exe")
    parser.add_argument("--game-source", type=Path, default=REPO / "game", help="Remake project to snapshot")
    parser.add_argument("--godot", default=shutil.which("godot-4") or shutil.which("godot"))
    parser.add_argument("--out", type=Path, help="New result directory; existing results are never overwritten")
    parser.add_argument("--seed", type=int, default=20261020)
    parser.add_argument("--fuzz", type=int, default=12, help="Seeded cases per supported numeric/ordering family")
    parser.add_argument("--case", help="Scenario ID substring filter")
    parser.add_argument("--campaign", choices=list(REFERENCES), default="original",
                        help="Qualified executable/campaign (replay uses the recorded reference)")
    parser.add_argument("--authored-quests", action="store_true",
                        help="Add up to 120 supported condition lists from this installation's MOBs")
    parser.add_argument("--quest-limit", type=int, default=120,
                        help="Authored condition-list cap; 0 includes every supported list")
    parser.add_argument("--replay-inputs", type=Path, help="Replay exact previously captured inputs")
    parser.add_argument("--repeat", type=int, choices=[1, 2, 3], default=2, help="Independent fresh captures to verify repeatability")
    parser.add_argument("--timeout", type=int, default=180, help="Seconds allowed for each subprocess")
    parser.add_argument("--list", action="store_true", help="List selected cases without loading the game/emulator")
    args = parser.parse_args()
    if args.fuzz < 0 or args.fuzz > 1000 or args.timeout < 1 or args.quest_limit < 0:
        parser.error("Use 0..1000 fuzz cases, a nonnegative quest limit and a positive timeout")
    if args.replay_inputs:
        inputs = json.loads(args.replay_inputs.read_text())
        if args.case:
            inputs["scenarios"] = [r for r in inputs["scenarios"] if args.case in r["id"]]
    else:
        inputs = make_inputs(args.seed, args.fuzz, None if args.authored_quests else args.case, args.campaign)
        if args.authored_quests:
            if not args.game_dir:
                parser.error("--authored-quests requires --game-dir")
            from campaign_quests import append_campaign_cases
            append_campaign_cases(inputs, args.game_dir, args.quest_limit)
            import extensions
            extensions.authored(inputs, args.game_dir, args.quest_limit)
            if args.case:
                inputs["scenarios"] = [r for r in inputs["scenarios"] if args.case in r["id"]]
    check_inputs(inputs)
    if args.list:
        for row in inputs["scenarios"]:
            print(row["id"])
        return 0
    if not args.game_dir or not args.out or not args.godot:
        parser.error("--game-dir, --godot and --out are required")
    source = args.game_source.resolve()
    output = args.out.resolve()
    if output == source or source in output.parents:
        raise ValueError("Place results outside --game-source to avoid recursively copying the result directory")
    output.mkdir(parents=True, exist_ok=False)
    started = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    commands = []
    try:
        data = args.game_dir.resolve()
        binary = data / "game.exe"
        if file_hash(binary) != inputs["reference"]["executable_sha256"]:
            raise ValueError("Unsupported game.exe hash. This suite refuses to execute unverified addresses.")
        if not sys.platform.startswith("linux"):
            raise ValueError("Capture profile isolation is qualified only on Linux; --list remains available")
        # Check before importing/staging, and give actionable dependency errors.
        import unicorn
        if unicorn.__version__ != "2.1.4":
            raise ValueError("Use the pinned Unicorn version in tools/parity/requirements.txt")
        inputs_path = output / "inputs.json"
        inputs_path.write_bytes(canonical(inputs))
        write_json(output / "tool-source.json", {p.name: file_hash(p) for p in sorted(HERE.iterdir()) if p.is_file()})
        harness = output / "harness"
        shutil.copytree(HERE, harness, ignore=shutil.ignore_patterns("__pycache__"))
        runtime, source_digest = stage_game(source, output)
        name_match = re.search(r'^config/name="([^"]+)"', (runtime / "project.godot").read_text(), re.M)
        if not name_match or "/" in name_match[1] or "\\" in name_match[1]:
            raise ValueError("Unsupported project user-directory name")
        name = name_match[1]
        executable = shutil.which(args.godot) or str(Path(args.godot).resolve())
        engine = [executable, "--headless", "--path", str(runtime), "--render-thread", "safe", "--audio-driver", "Dummy"]
        env = isolated_environment(output / "import-profile", name, data)
        print("Importing isolated remake snapshot...", flush=True)
        # Godot's first clean scan can parse autoloads before importing their
        # textures/fonts. Retain those diagnostics, then require a clean second
        # scan with the imported resources. Neither pass runs gameplay.
        commands.append(command(engine + ["--editor", "--import"], output / "import-bootstrap.log", env, args.timeout, import_bootstrap=True))
        commands.append(command(engine + ["--editor", "--import"], output / "import.log", env, args.timeout))
        native_runs, remake_runs = [], []
        for repetition in range(args.repeat):
            print(f"Capturing original and remake ({repetition + 1}/{args.repeat})...", flush=True)
            native_path, remake_path = output / f"original-{repetition}.json", output / f"remake-{repetition}.json"
            commands.append(command([sys.executable, str(harness / "native.py"), "--binary", str(binary),
                                     "--inputs", str(inputs_path), "--output", str(native_path)],
                                    output / f"original-{repetition}.log", os.environ.copy(), args.timeout))
            env = isolated_environment(output / f"remake-profile-{repetition}", name, data)
            commands.append(command(engine + ["--fixed-fps", "60", "--", "--no-movies", "--ei-path=" + str(data),
                                             "--tool=res://tools/parity_trace.gd", "--parity-inputs=" + str(inputs_path),
                                             "--parity-output=" + str(remake_path)],
                                    output / f"remake-{repetition}.log", env, args.timeout))
            original = json.loads(native_path.read_text())
            remake = json.loads(remake_path.read_text())
            validate_trace(original, inputs, "original")
            validate_trace(remake, inputs, "remake")
            if remake.get("profile") != PROFILE:
                raise ValueError("Remake did not confirm the required isolated development preferences")
            native_runs.append(original)
            remake_runs.append(remake)
        for role, runs in [("original", native_runs), ("remake", remake_runs)]:
            for i, trace in enumerate(runs[1:], 1):
                difference = first_difference(runs[0]["scenarios"], trace["scenarios"])
                if difference:
                    raise ValueError(f"{role} capture is not repeatable (run {i}): {difference}")
        report = compare(inputs, native_runs[0], remake_runs[0])
        report["repeatability"] = {"captures_per_side": args.repeat, "verified": args.repeat >= 2}
        report["provenance"] = {
            "started_utc": started, "game_source": str(source), "game_source_sha256": source_digest,
            "godot": remake_runs[0]["engine"], "original_executable": str(binary),
            "fpu_control_word": native_runs[0]["fpu_control_word"],
            "common_native_boundary": "Empty emulated Windows SEH chain at FS:[0]; no native exceptions are handled.",
            "commands": commands, "python": sys.version,
            "original_data_files": {str(p.relative_to(data)): file_hash(p) for p in [
                data / "res/database.res", data / "res/texts.res", data / "config/ai.reg"] if p.is_file()},
        }
        for name_, git_args in [("commit", ["rev-parse", "HEAD"]), ("working_tree", ["status", "--porcelain"])]:
            result = subprocess.run(["git", "-C", str(source), *git_args], capture_output=True, text=True, check=False)
            report["provenance"][name_] = result.stdout.strip() if result.returncode == 0 else None
        write_json(output / "report.json", report)
        (output / "report.md").write_text(report_text(report, inputs))
        junit(report, output / "junit.xml")
        reproduce = [sys.executable, str(HERE / "run.py"), "--game-dir", str(data), "--game-source", str(source),
                     "--godot", executable, "--replay-inputs", str(inputs_path), "--repeat", str(args.repeat)]
        prefix = "env " + shlex.quote("PYTHONPATH=" + os.environ["PYTHONPATH"]) + " " if os.environ.get("PYTHONPATH") else ""
        (output / "reproduce.sh").write_text("#!/bin/sh\nset -eu\n"
            'output=${1:?"usage: reproduce.sh NEW_OUTPUT_DIRECTORY [--case ID]"}\nshift\nexec '
            + prefix + shlex.join(reproduce) + ' --out "$output" "$@"\n')
        (output / "reproduce.sh").chmod(0o755)
        print(f"{report['counts']['matches']} match, {report['counts']['mismatches']} differ. Report: {output / 'report.md'}")
        for row in report["scenarios"]:
            if row["status"] != "match":
                print(row["id"], json.dumps(row["first_divergence"], sort_keys=True))
        return 1 if report["counts"]["mismatches"] else 0
    except (Exception, KeyboardInterrupt) as exc:
        error = {"schema": 1, "status": "error", "started_utc": started, "error": str(exc) or type(exc).__name__,
                 "input_sha256": digest(inputs), "commands": commands}
        write_json(output / "report.json", error)
        (output / "report.md").write_text("# Capture failed\n\n" + error["error"] + "\n\nNo parity pass is claimed.\n")
        print(error["error"], file=sys.stderr)
        return 2


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, KeyError) as exc:
        print(f"Parity setup error: {exc}", file=sys.stderr)
        raise SystemExit(2)
