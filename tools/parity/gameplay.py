#!/usr/bin/env python3
"""Run the curated gameplay regressions, optionally with original-x86 parity.

The two evidence classes are reported separately. A completed assertion program
is not original-executable parity. Exit 0 passes, 1 finds differences/assertion
failures, 2 means at least one setup, capture, or runtime error.
"""
import argparse
from collections import Counter
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

from compare import digest
from run import HERE, REPO, PROFILE, command, file_hash, isolated_environment, stage_game, write_json


DIAGNOSTIC = re.compile(r"^\s*(ERROR:|SCRIPT ERROR:|Parse Error:)", re.M)


def catalog(selection=None):
    data = json.loads((selection or HERE / "gameplay_catalog.json").read_text())
    rows = data if selection else data["tests"]
    if (not selection and data["schema"] != 1) or not rows or len({r["id"] for r in rows}) != len(rows):
        raise ValueError("Invalid/duplicate gameplay catalog")
    for row in rows:
        path = Path(row["script"])
        if path.is_absolute() or ".." in path.parts or path.parts[:2] != ("tools", "tests"):
            raise ValueError("Test paths must stay inside tools/tests")
        if not re.fullmatch(r"[a-z_]+/[a-z0-9_]+", row["id"]) or row["category"] != row["id"].split("/")[0]:
            raise ValueError("Test IDs must be category/name")
        if (row["kind"] != "remake_regression" or type(row["min_checks"]) is not int
                or row["min_checks"] < 1 or row["timeout"] < 1
                or row["campaign"] not in ("cursed_lands", "lost_in_astral")):
            raise ValueError("Every entry must declare evidence type and nonzero minimum coverage")
        for name in row["required_files"]:
            if Path(name).is_absolute() or ".." in Path(name).parts:
                raise ValueError("Required assets must stay within the campaign folder")
    return rows


def run_program(argv, log, env, timeout):
    """Abort a broken Godot script promptly, owning only this process group."""
    start = time.monotonic()
    error = None
    with log.open("w") as stream, log.open(errors="replace") as reader:
        process = subprocess.Popen(argv, stdout=stream, stderr=subprocess.STDOUT, env=env,
                                   start_new_session=True)
        pending = ""
        try:
            while process.poll() is None:
                pending += reader.read()
                if DIAGNOSTIC.search(pending):
                    error = "Runtime/script error; stopped this test process"
                    break
                if time.monotonic() - start > timeout:
                    error = f"Test exceeded {timeout} seconds"
                    break
                # Preserve any incomplete line across reads.
                pending = pending.rsplit("\n", 1)[-1]
                time.sleep(0.1)
        finally:
            if process.poll() is None:
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
            process.wait()
    return process.returncode, error


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


def assess(text, spec, exit_code, error=None):
    result = {"status": "error", "checks": 0, "failures": 0}
    diagnostics = [line for line in text.splitlines() if DIAGNOSTIC.match(line)]
    result["diagnostics"] = diagnostics
    result["failure_messages"] = [line for line in text.splitlines() if line.startswith("FAIL ")][:100]
    starts = [line.removeprefix("GAMEPLAY_SUITE_START ") for line in text.splitlines()
              if line.startswith("GAMEPLAY_SUITE_START ")]
    try:
        if len(starts) != 1:
            raise ValueError("Missing/duplicate isolated-profile confirmation")
        start = json.loads(starts[0])
        if (start["profile"] != PROFILE or start["script"] != "res://" + spec["script"]
                or start["campaign"] != spec["campaign"]):
            raise ValueError("Wrong profile, campaign or test script")
        result["runtime"] = start
        result.update(parse_summary(text, spec["marker"], spec["min_checks"]))
        if diagnostics:
            result["error"] = "Runtime/script diagnostics; assertion results are not a clean run"
        elif error or exit_code not in (0, 1) or (exit_code == 1 and not result["failures"]):
            result["error"] = error or f"Runtime diagnostics or exit code {exit_code}"
        elif result["failures"]:
            result["status"] = "failed"
        else:
            result["status"] = "passed"
    except (KeyError, ValueError, TypeError) as exc:
        result["error"] = str(exc)
    if error:
        result.setdefault("error", error)
    return result


def render(report):
    lines = ["# Gameplay test report", "",
             "**Remake regressions and original-executable comparisons are separate evidence.**", "",
             f"Overall status: **{report['status']}**.", "",
             f"Completed {len(report['tests'])} of {len(report['selected'])} selected programs.", "",
             "| Category | Programs | Passed | Failed | Errors | Completed checks |",
             "|---|---:|---:|---:|---:|---:|"]
    for category in sorted({r["category"] for r in report["tests"]}):
        rows = [r for r in report["tests"] if r["category"] == category]
        counts = Counter(r["status"] for r in rows)
        lines.append(f"| {category} | {len(rows)} | {counts['passed']} | {counts['failed']} | "
                     f"{counts['error']} | {sum(r['checks'] for r in rows)} |")
    if "original" in report:
        original = report["original"]
        lines += ["", "## Original executable", "", f"Status: **{original['status']}**. "
                  f"Counts: `{json.dumps(original.get('counts', {}))}`. "
                  "See [the independent comparison report](original/report.md)."]
    if report.get("error"):
        lines += ["", "Capture error: " + report["error"], ""]
    lines += ["", "## Program results", "",
              "| Program | Status | Checks | Failed checks | Log |",
              "|---|---|---:|---:|---|"]
    for row in report["tests"]:
        lines.append(f"| `{row['id']}` | {row['status']} | {row['checks']} | {row['failures']} | "
                     f"[log]({row['log']}) |")
    for row in report["tests"]:
        if row["status"] != "passed":
            lines += ["", "### " + row["id"], "", row.get("error", "Failed assertions:"), ""]
            lines += ["- " + msg.replace("\n", " ") for msg in row["failure_messages"][:12]]
            lines += ["- " + msg.replace("\n", " ") for msg in row["diagnostics"][:6]]
    lines += ["", "## Scope", "",
              "These headless checks cover gameplay state, authored scripts, animation state/rigs and "
              "effect logic. Rendered pixels, sound, a full ordinary campaign playthrough and external "
              "Internet play are not validated. C++-versus-GDScript checks compare two remake implementations.",
              "", "Each program runs in a fresh process and isolated muted profile. "
              "Runtime source hashes and required-asset hashes are retained. No failure is automatically approved.",
              "", "Run `reproduce.sh NEW_OUTPUT_DIRECTORY` to repeat this selection against the current source.", ""]
    return "\n".join(lines)


def save_report(report, output):
    counts = Counter(r["status"] for r in report["tests"])
    report["counts"] = {key: counts[key] for key in ["passed", "failed", "error"]}
    report["counts"]["programs"] = len(report["tests"])
    report["counts"]["checks"] = sum(r["checks"] for r in report["tests"])
    report["counts"]["failed_checks"] = sum(r["failures"] for r in report["tests"])
    original = report.get("original", {}).get("status")
    report["status"] = ("incomplete" if not report.get("complete", False) else
                       "error" if counts["error"] or original == "error" else
                       "failed" if counts["failed"] or original == "mismatch" else "passed")
    write_json(output / "report.json", report)
    (output / "report.md").write_text(render(report))
    extra_error = int(not report.get("complete", False)) + int(original == "error")
    extra_failure = int(original == "mismatch")
    suite = ET.Element("testsuite", name="gameplay-regressions",
                       tests=str(len(report["tests"]) + int(not report.get("complete", False)) + int(original is not None)),
                       failures=str(counts["failed"] + extra_failure), errors=str(counts["error"] + extra_error))
    for row in report["tests"]:
        item = ET.SubElement(suite, "testcase", classname=row["category"], name=row["id"],
                             assertions=str(row["checks"]), time=str(row.get("seconds", 0)))
        if row["status"] != "passed":
            error = ET.SubElement(item, "failure" if row["status"] == "failed" else "error",
                                  message=row.get("error", "Assertions failed"))
            error.text = "\n".join(row["failure_messages"] + row["diagnostics"])
    if not report.get("complete", False):
        item = ET.SubElement(suite, "testcase", classname="capture", name="selection_completed")
        ET.SubElement(item, "error", message=report.get("error", "Selected programs have not all completed"))
    if original is not None:
        item = ET.SubElement(suite, "testcase", classname="original-x86", name="independent_comparison")
        if original in ("error", "mismatch"):
            ET.SubElement(item, "error" if original == "error" else "failure",
                          message="See original/report.json for individual scenarios")
    ET.ElementTree(suite).write(output / "junit.xml", encoding="utf-8", xml_declaration=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--game-dir", type=Path)
    parser.add_argument("--astral-dir", type=Path, help="Owned Lost in Astral installation for expansion-specific tests")
    parser.add_argument("--game-source", type=Path, default=REPO / "game")
    parser.add_argument("--godot", default=shutil.which("godot-4") or shutil.which("godot"))
    parser.add_argument("--out", type=Path)
    parser.add_argument("--category", action="append", help="Repeat to combine categories")
    parser.add_argument("--case", help="Program ID substring")
    parser.add_argument("--quick", action="store_true", help="Select fixtures without full map sessions")
    parser.add_argument("--with-original", action="store_true", help="Also run independent original-x86 suite")
    parser.add_argument("--no-original", action="store_false", dest="with_original", help="Run remake regressions only")
    parser.add_argument("--replay-selection", type=Path, help="Replay a retained selection.json against current source")
    parser.add_argument("--seed", type=int, default=20261020)
    parser.add_argument("--timeout", type=int, help="Override per-program timeout in seconds")
    parser.add_argument("--list", action="store_true")
    args = parser.parse_args()
    tests = [row for row in catalog(args.replay_selection) if (not args.quick or row["quick"])
             and (not args.category or row["category"] in args.category)
             and (not args.case or args.case in row["id"])]
    if not tests:
        raise ValueError("No gameplay programs selected")
    if args.list:
        for row in tests:
            print(f"{row['id']} [{row['campaign']}]: {row['description']}")
        return 0
    if not sys.platform.startswith("linux"):
        raise ValueError("Capture profile isolation is qualified only on Linux")
    if not args.game_dir or not args.out or not args.godot:
        parser.error("--game-dir, --godot and --out are required")
    if args.timeout is not None and args.timeout < 1:
        parser.error("--timeout must be positive")
    source, data, output = args.game_source.resolve(), args.game_dir.resolve(), args.out.resolve()
    for input_tree in (source, (REPO / "tools/tests").resolve()):
        if output == input_tree or input_tree in output.parents:
            raise ValueError("Results must be outside the game and test source folders")
    output.mkdir(parents=True, exist_ok=False)
    report = {"schema": 1, "tests": [], "selected": [r["id"] for r in tests], "complete": False,
              "seed": args.seed, "started_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
              "game_source": str(source), "evidence": "remake_regression"}
    try:
        runtime, _ = stage_game(source, output)
        shutil.copytree(REPO / "tools/tests", runtime / "tools/tests")
        shutil.copy2(HERE / "gameplay_bootstrap.gd", runtime / "tools/gameplay_bootstrap.gd")
        manifest = {p.relative_to(runtime).as_posix(): file_hash(p)
                    for p in sorted(runtime.rglob("*")) if p.is_file()}
        write_json(output / "runtime-source.json", manifest)
        write_json(output / "selection.json", tests)
        write_json(output / "tool-source.json", {p.name: file_hash(p) for p in sorted(HERE.iterdir()) if p.is_file()})
        report["source_sha256"] = digest(manifest)
        report["original_data"] = {str(p.relative_to(data)): file_hash(p) for p in [
            data / "game.exe", data / "res/database.res", data / "res/texts.res"] if p.is_file()}
        data_roots = {"cursed_lands": data}
        if args.astral_dir:
            data_roots["lost_in_astral"] = args.astral_dir.resolve()
        report["campaign_data"] = {campaign: {
            "root":str(folder), "files": {name:file_hash(folder / name) for name in
            sorted({name for row in tests if row["campaign"] == campaign for name in row["required_files"]})
            if (folder / name).is_file()}} for campaign, folder in data_roots.items()}
        name = re.search(r'^config/name="([^"/\\]+)"', (runtime / "project.godot").read_text(), re.M)[1]
        engine = [str(shutil.which(args.godot) or Path(args.godot).resolve()), "--headless", "--path",
                  str(runtime), "--render-thread", "safe", "--audio-driver", "Dummy"]
        report["engine"] = {"path": engine[0], "sha256": file_hash(engine[0])}
        reproduce = [sys.executable, str(HERE / "gameplay.py"), "--game-dir", str(data),
                     "--game-source", str(source), "--godot", engine[0], "--seed", str(args.seed),
                     "--replay-selection", str(output / "selection.json")]
        if args.astral_dir: reproduce += ["--astral-dir", str(args.astral_dir.resolve())]
        if args.with_original: reproduce.append("--with-original")
        if args.timeout: reproduce += ["--timeout", str(args.timeout)]
        (output / "reproduce.sh").write_text('#!/bin/sh\nset -eu\noutput=${1:?"NEW_OUTPUT_DIRECTORY required"}\nshift\nexec '
                                            + shlex.join(reproduce) + ' --out "$output" "$@"\n')
        (output / "reproduce.sh").chmod(0o755)
        save_report(report, output)
        env = isolated_environment(output / "import-profile", name, data)
        env.pop("EI_FIXED_FPS", None)
        print(f"Importing snapshot for {len(tests)} gameplay programs...", flush=True)
        command(engine + ["--editor", "--import"], output / "import-bootstrap.log", env, 240, import_bootstrap=True)
        command(engine + ["--editor", "--import"], output / "import.log", env, 240)
        for index, spec in enumerate(tests):
            directory = output / "tests" / spec["id"]
            directory.mkdir(parents=True)
            log = directory / "run.log"
            test_data = data_roots.get(spec["campaign"])
            missing = spec["required_files"] if test_data is None else [
                file for file in spec["required_files"] if not (test_data / file).is_file()]
            if missing:
                message = f"Missing {spec['campaign']} data: {', '.join(missing)}"
                log.write_text(message + "\n")
                report["tests"].append(dict(spec, status="error", checks=0, failures=0, error=message,
                    diagnostics=[], failure_messages=[], log=log.relative_to(output).as_posix()))
                save_report(report, output)
                print(f"[{index+1}/{len(tests)}] {spec['id']}: error ({message})", flush=True)
                continue
            env = isolated_environment(directory / "profile", name, test_data)
            env.pop("EI_FIXED_FPS", None)
            argv = engine + ["--", "--no-movies", "--ei-path=" + str(test_data),
                             "--tool=res://tools/gameplay_bootstrap.gd", "--suite-script=res://" + spec["script"],
                             "--suite-seed=" + str(args.seed), "--suite-campaign=" + spec["campaign"], *spec["args"]]
            start = time.monotonic()
            exit_code, error = run_program(argv, log, env, args.timeout or spec["timeout"])
            result = dict(spec, **assess(log.read_text(errors="replace"), spec, exit_code, error))
            result.update(seconds=round(time.monotonic() - start, 3),
                          log=log.relative_to(output).as_posix(), log_sha256=file_hash(log),
                          exit_code=exit_code, argv=argv)
            report["tests"].append(result)
            save_report(report, output)
            print(f"[{index+1}/{len(tests)}] {spec['id']}: {result['status']} "
                  f"({result['checks']} checks, {result['failures']} failed)", flush=True)
        if args.with_original:
            print("Running independent original-executable comparisons...", flush=True)
            argv = [sys.executable, str(HERE / "run.py"), "--game-dir", str(data),
                    "--game-source", str(runtime), "--godot", engine[0], "--out", str(output / "original"),
                    "--seed", str(args.seed)]
            # Known differences still leave a complete report and do not erase regressions.
            try:
                command(argv, output / "original-run.log", os.environ.copy(), 600)
            except Exception:
                pass
            original_path = output / "original/report.json"
            original = json.loads(original_path.read_text()) if original_path.exists() else {"status": "error"}
            report["original"] = {k: original[k] for k in ["status", "counts", "repeatability"] if k in original}
        report["complete"] = len(report["tests"]) == len(tests)
        save_report(report, output)
        print(f"Report: {output / 'report.md'}", flush=True)
        return {"passed": 0, "failed": 1, "error": 2}[report["status"]]
    except (Exception, KeyboardInterrupt) as exc:
        report.update(status="error", complete=False, error=str(exc) or type(exc).__name__)
        save_report(report, output)
        print(report["error"], file=sys.stderr)
        return 2


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, KeyError) as exc:
        print(f"Gameplay setup error: {exc}", file=sys.stderr)
        raise SystemExit(2)
