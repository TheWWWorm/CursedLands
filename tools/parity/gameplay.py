#!/usr/bin/env python3
"""Run the curated gameplay regressions, optionally with original-x86 parity.

The two evidence classes are reported separately. A completed assertion program
is not original-executable parity. Exit 0 passes, 1 finds differences/assertion
failures, 2 means at least one setup, capture, or runtime error.
"""
import argparse
from collections import Counter
from concurrent.futures import ThreadPoolExecutor, as_completed
from contextlib import nullcontext
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import sys
import threading
import time
import xml.etree.ElementTree as ET

from compare import digest
from process import DIAGNOSTIC, rendered_arguments, run_program, parse_summary
from run import HERE, REPO, PROFILE, command, file_hash, isolated_environment, stage_game, write_json


TEXTS = ("en", "ru", "de")


def catalog(selection=None, path=None):
    """The registered tests: the catalog (or `path`, a file of the same
    schema), or a retained `selection.json`. An entry with `focused` is also
    a case of tools/check_regressions.py under that short ID."""
    data = json.loads((selection or path or HERE / "gameplay_catalog.json").read_text())
    rows = data if selection else data["tests"]
    if (not selection and data["schema"] != 1) or not rows or len({r["id"] for r in rows}) != len(rows):
        raise ValueError("Invalid/duplicate gameplay catalog")
    aliases = [r["focused"] for r in rows if "focused" in r]
    if len(set(aliases)) != len(aliases):
        raise ValueError("Duplicate focused case IDs")
    names = {r["id"].split("/")[1]: r["id"] for r in rows}
    for row in rows:
        alias = row.get("focused")
        if alias is not None and (not re.fullmatch(r"[a-z0-9_]+", str(alias)) or names.get(alias, row["id"]) != row["id"]):
            raise ValueError("A focused ID is a short lowercase name that no other entry's name uses")
        if any(language not in TEXTS for language in row.get("texts", [])):
            raise ValueError("texts lists languages among " + ", ".join(TEXTS))
        path = Path(row["script"])
        if path.is_absolute() or ".." in path.parts or path.parts[:2] != ("tools", "tests"):
            raise ValueError("Test paths must stay inside tools/tests")
        if not re.fullmatch(r"[a-z_]+/[a-z0-9_]+", row["id"]) or row["category"] != row["id"].split("/")[0]:
            raise ValueError("Test IDs must be category/name")
        if (row["kind"] != "remake_regression" or type(row["min_checks"]) is not int
                or row["min_checks"] < 1 or row["timeout"] < 1
                or row["campaign"] not in ("cursed_lands", "lost_in_astral")
                or row.get("display", "headless") not in ("headless", "rendered")
                or row.get("rendering_method", "gl_compatibility") not in ("gl_compatibility", "mobile", "forward_plus")):
            raise ValueError("Every entry must declare evidence type and nonzero minimum coverage")
        for campaign, files in required_assets(row).items():
            if campaign not in ("cursed_lands", "lost_in_astral"):
                raise ValueError("Unknown additional campaign")
            for name in files:
                if Path(name).is_absolute() or ".." in Path(name).parts:
                    raise ValueError("Required assets must stay within the campaign folder")
        argument_paths(row, {**{key: Path("/data") / key for key in required_assets(row)},
                             **{"texts_" + language: Path("/data/texts") / language for language in row.get("texts", [])}})
    return rows


def required_assets(spec):
    assets = {spec["campaign"]: list(spec["required_files"])}
    for campaign, files in spec.get("extra_data", {}).items():
        assets.setdefault(campaign, []).extend(files)
    return assets


def argument_paths(spec, data_roots):
    """Resolve explicitly declared companion installations, and the original
    localized text archives an entry lists in `texts` (`{texts_en}` ...), as
    individual argv values."""
    def replace(match):
        name = match.group(1)
        if name.startswith("texts_"):
            if name[6:] not in spec.get("texts", []) or name not in data_roots:
                raise ValueError("Argument requires a declared localized archive: " + name)
            return str(data_roots[name])
        if name not in required_assets(spec) or name not in data_roots:
            raise ValueError("Argument requires declared campaign data: " + name)
        return str(data_roots[name])
    return [re.sub(r"\{([a-z_]+)\}", replace, value) for value in spec["args"]]


NETWORK = re.compile(r"\.host\(|\.join\(|create_server|create_client|LanDiscovery|MultiplayerPeer|WebSocket|"
                     r"PacketPeerUDP|TCPServer|StreamPeerTCP|UPNP")


def uses_network(script, runtime, seen=None):
    """Whether a test or a script it extends/preloads opens fixed local ports."""
    seen = set() if seen is None else seen
    if script in seen or not script.is_file():
        return False
    seen.add(script)
    text = script.read_text(errors="replace")
    if NETWORK.search(text):
        return True
    for base in re.findall(r'(?:^extends\s+|preload\()"([^"]+\.gd)"', text, re.M):
        path = runtime / base[6:] if base.startswith("res://") else script.parent / base
        if uses_network(path, runtime, seen):
            return True
    return False


# One loaded-map program peaks near 4.2 GiB and uses about 1.5 cores
# (LiA quest run, 2026-10-28); keep room for the desktop and other work.
PROGRAM_MEMORY = 9 * 2**29
MEMORY_RESERVE = 8 * 2**30


def available_memory():
    """MemAvailable in bytes, or None where the system does not report it."""
    try:
        for line in Path("/proc/meminfo").read_text().splitlines():
            if line.startswith("MemAvailable:"):
                return int(line.split()[1]) * 1024
    except (OSError, ValueError, IndexError):
        pass
    return None


def auto_jobs(cpus=None, available=None):
    """Parallel programs this machine can hold: CPU threads and free memory."""
    jobs = max(1, (cpus or os.cpu_count() or 1) // 3)
    if available is not None:
        jobs = min(jobs, max(1, (available - MEMORY_RESERVE) // PROGRAM_MEMORY))
    return int(jobs)


def jobs_argument(value):
    if value == "auto":
        return value
    try:
        jobs = int(value)
    except ValueError:
        raise argparse.ArgumentTypeError("--jobs must be a positive number or auto") from None
    if jobs < 1:
        raise argparse.ArgumentTypeError("--jobs must be a positive number or auto")
    return jobs


class MemoryGate:
    """Hold a program back while free memory is below one program's peak plus
    the reserve. The first program always starts, so a run never stalls."""
    def __init__(self, stop, available=available_memory, poll=2.0):
        self.stop, self.available, self.poll = stop, available, poll
        self.active = 0
        self.condition = threading.Condition()

    def __enter__(self):
        with self.condition:
            while self.active and not self.stop.is_set():
                free = self.available()
                if free is None or free >= PROGRAM_MEMORY + MEMORY_RESERVE:
                    break
                self.condition.wait(self.poll)
            self.active += 1
        return self

    def __exit__(self, *exc):
        with self.condition:
            self.active -= 1
            self.condition.notify_all()


def missing_assets(spec, data_roots):
    missing = [f"{campaign}/{name}" for campaign, files in required_assets(spec).items()
               for name in files if campaign not in data_roots or not (data_roots[campaign] / name).is_file()]
    missing += [f"texts_{language} (--texts-{language})" for language in spec.get("texts", [])
                if f"texts_{language}" not in data_roots or not data_roots[f"texts_{language}"].is_file()]
    return missing


def engine_argv(godot, runtime, display="headless", rendering_method="gl_compatibility"):
    base = [str(godot), "--path", str(runtime), "--render-thread", "safe", "--audio-driver", "Dummy"]
    if display == "headless":
        return base + ["--headless"]
    return base + rendered_arguments(rendering_method)


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
        if start.get("display", "headless") != spec.get("display", "headless"):
            raise ValueError("Wrong display mode; rendered checks require a real renderer")
        if "rendering_method" in spec and start.get("rendering_method") != spec["rendering_method"]:
            raise ValueError("Wrong rendering method; this test requires its declared renderer")
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
    rendered = sum(row.get("display", "headless") == "rendered" for row in report["tests"])
    lines += ["", "## Scope", "",
              f"{rendered} configurations requested a real OpenGL renderer on a private display; "
              "the remaining configurations run headlessly. Rendered checks qualify only their "
              "specific UI/pixel assertions, not overall visual quality or other rendering backends. "
              "Sound output, a full ordinary campaign playthrough and external Internet play are not "
              "validated. C++-versus-GDScript checks compare two remake implementations.",
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
    if "feature_inventory" in report:
        rows = {row["id"]: row for row in report["tests"]}
        lines = ["# Player feature coverage", "", report["feature_inventory"]["meaning"], "",
                 "Direct dispatch gaps: " + (", ".join(report["feature_inventory"]["direct_command_gaps"]) or
                                             "none in the inventoried campaign authority commands") + ".", "",
                 "| Player function | Linked results in this run | Checked scope | Remaining gaps |",
                 "|---|---|---|---|"]
        for feature in report["feature_inventory"]["features"]:
            feature_counts = Counter(rows[key]["status"] if key in rows else "not run" for key in feature["tests"])
            status = ", ".join(f"{value} {key}" for key, value in sorted(feature_counts.items())) or "No registered test"
            lines.append(f"| {feature['title']} | {status} | {feature['scope']} | {feature['remaining']} |")
        (output / "features.md").write_text("\n".join(lines) + "\n")
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
    for language in TEXTS:
        parser.add_argument("--texts-" + language, type=Path,
                            help=f"Original {language.upper()} texts.res for the entries that list `texts`")
    parser.add_argument("--game-source", type=Path, default=REPO / "game")
    parser.add_argument("--godot", default=shutil.which("godot-4") or shutil.which("godot"))
    parser.add_argument("--out", type=Path)
    parser.add_argument("--category", action="append", help="Repeat to combine categories")
    parser.add_argument("--case", action="append", help="Program ID substring; repeat to combine selections")
    parser.add_argument("--display", choices=("headless", "rendered"), help="Select only this execution mode")
    parser.add_argument("--quick", action="store_true", help="Select fixtures without full map sessions")
    parser.add_argument("--with-original", action="store_true", help="Also run independent original-x86 suite")
    parser.add_argument("--no-original", action="store_false", dest="with_original", help="Run remake regressions only")
    parser.add_argument("--replay-selection", type=Path, help="Replay a retained selection.json against current source")
    parser.add_argument("--seed", type=int, default=20261020)
    parser.add_argument("--timeout", type=int, help="Override per-program timeout in seconds")
    parser.add_argument("--render-display", help="Private X display for rendered cases, e.g. :91; never uses the desktop implicitly")
    parser.add_argument("--jobs", type=jobs_argument, default="auto",
                        help="Programs to run at once (default auto: CPU threads and free memory); "
                             "each keeps its own process and profile")
    parser.add_argument("--list", action="store_true")
    args = parser.parse_args()
    tests = [row for row in catalog(args.replay_selection) if (not args.quick or row["quick"])
             and (not args.category or row["category"] in args.category)
             and (not args.case or any(part in row["id"] for part in args.case))
             and (not args.display or row.get("display", "headless") == args.display)]
    if not tests:
        raise ValueError("No gameplay programs selected")
    if args.list:
        for row in tests:
            alias = f" (focused: {row['focused']})" if "focused" in row else ""
            print(f"{row['id']} [{row['campaign']}]{alias}: {row['description']}")
        return 0
    if not sys.platform.startswith("linux"):
        raise ValueError("Capture profile isolation is qualified only on Linux")
    if not args.game_dir or not args.out or not args.godot:
        parser.error("--game-dir, --godot and --out are required")
    if args.timeout is not None and args.timeout < 1:
        parser.error("--timeout must be positive")
    source, data, output = args.game_source.resolve(), args.game_dir.resolve(), args.out.resolve()
    for input_tree in (source, (REPO / "tools/tests").resolve(), (REPO / "tools/benchmarks").resolve()):
        if output == input_tree or input_tree in output.parents:
            raise ValueError("Results must be outside the game and test source folders")
    output.mkdir(parents=True, exist_ok=False)
    report = {"schema": 1, "tests": [], "selected": [r["id"] for r in tests], "complete": False,
              "seed": args.seed, "started_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
              "game_source": str(source), "evidence": "remake_regression",
              "feature_inventory": json.loads((HERE / "player_features.json").read_text())}
    try:
        runtime, _ = stage_game(source, output)
        shutil.copytree(REPO / "tools/tests", runtime / "tools/tests")
        shutil.copytree(REPO / "tools/benchmarks", runtime / "tools/benchmarks")
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
        for language in TEXTS:
            archive = getattr(args, "texts_" + language)
            if archive:
                data_roots["texts_" + language] = archive.resolve()
        report["campaign_data"] = {campaign: {
            "root":str(folder), "files": {name:file_hash(folder / name) for name in
            sorted({name for row in tests for name in required_assets(row).get(campaign, [])})
            if (folder / name).is_file()}} for campaign, folder in data_roots.items() if not campaign.startswith("texts_")}
        report["texts"] = {key: {"path": str(folder), "sha256": file_hash(folder)}
                           for key, folder in data_roots.items() if key.startswith("texts_") and folder.is_file()}
        name = re.search(r'^config/name="([^"/\\]+)"', (runtime / "project.godot").read_text(), re.M)[1]
        engine = engine_argv(shutil.which(args.godot) or Path(args.godot).resolve(), runtime)
        report["engine"] = {"path": engine[0], "sha256": file_hash(engine[0])}
        reproduce = [sys.executable, str(HERE / "gameplay.py"), "--game-dir", str(data),
                     "--game-source", str(source), "--godot", engine[0], "--seed", str(args.seed),
                     "--replay-selection", str(output / "selection.json")]
        if args.astral_dir: reproduce += ["--astral-dir", str(args.astral_dir.resolve())]
        for language in TEXTS:
            if getattr(args, "texts_" + language):
                reproduce += ["--texts-" + language, str(getattr(args, "texts_" + language).resolve())]
        if args.with_original: reproduce.append("--with-original")
        if args.timeout: reproduce += ["--timeout", str(args.timeout)]
        if args.render_display: reproduce += ["--render-display", args.render_display]
        reproduce += ["--jobs", str(args.jobs)]
        (output / "reproduce.sh").write_text('#!/bin/sh\nset -eu\noutput=${1:?"NEW_OUTPUT_DIRECTORY required"}\nshift\nexec '
                                            + shlex.join(reproduce) + ' --out "$output" "$@"\n')
        (output / "reproduce.sh").chmod(0o755)
        save_report(report, output)
        env = isolated_environment(output / "import-profile", name, data)
        env.pop("EI_FIXED_FPS", None)
        jobs = min(len(tests), auto_jobs(available=available_memory()) if args.jobs == "auto" else args.jobs)
        print(f"Importing snapshot for {len(tests)} gameplay programs ({jobs} at a time)...", flush=True)
        command(engine + ["--editor", "--import"], output / "import-bootstrap.log", env, 240, import_bootstrap=True)
        command(engine + ["--editor", "--import"], output / "import.log", env, 240)
        network_lock, display_lock = threading.Lock(), threading.Lock()
        stop = threading.Event()
        memory = MemoryGate(stop)
        def run_one(index, spec):
            directory = output / "tests" / spec["id"]
            directory.mkdir(parents=True)
            log = directory / "run.log"
            test_data = data_roots.get(spec["campaign"])
            missing = missing_assets(spec, data_roots)
            if missing:
                message = f"Missing campaign data: {', '.join(missing)}"
                log.write_text(message + "\n")
                return dict(spec, status="error", checks=0, failures=0, error=message,
                    diagnostics=[], failure_messages=[], log=log.relative_to(output).as_posix())
            if spec.get("display") == "rendered" and not args.render_display:
                message = "Rendered test requires --render-display pointing to a private X server"
                log.write_text(message + "\n")
                return dict(spec, status="error", checks=0, failures=0, error=message,
                    diagnostics=[], failure_messages=[], log=log.relative_to(output).as_posix())
            env = isolated_environment(directory / "profile", name, test_data)
            env.pop("EI_FIXED_FPS", None)
            display = spec.get("display", "headless")
            if display == "rendered":
                env["DISPLAY"] = args.render_display
                env.pop("WAYLAND_DISPLAY", None)
            argv = engine_argv(engine[0], runtime, display, spec.get("rendering_method", "gl_compatibility")) + ["--", "--no-movies", "--ei-path=" + str(test_data),
                             "--tool=res://tools/gameplay_bootstrap.gd", "--suite-script=res://" + spec["script"],
                             "--suite-seed=" + str(args.seed), "--suite-campaign=" + spec["campaign"],
                             "--suite-display=" + display, *argument_paths(spec, data_roots)]
            # Programs that open the fixed game ports never overlap one another,
            # nor do rendered programs sharing the private display.
            with network_lock if uses_network(runtime / spec["script"], runtime) else nullcontext(), \
                    display_lock if display == "rendered" else nullcontext(), memory:
                start = time.monotonic()
                exit_code, error = run_program(argv, log, env, args.timeout or spec["timeout"], stop)
            result = dict(spec, **assess(log.read_text(errors="replace"), spec, exit_code, error))
            result.update(seconds=round(time.monotonic() - start, 3),
                          log=log.relative_to(output).as_posix(), log_sha256=file_hash(log),
                          exit_code=exit_code, argv=argv)
            return result
        done = {}
        lock = threading.Lock()
        def record(index, result):
            # Keep the report in selection order whatever finishes first.
            with lock:
                done[index] = result
                report["tests"] = [done[i] for i in sorted(done)]
                save_report(report, output)
                print(f"[{len(done)}/{len(tests)}] {result['id']}: {result['status']} "
                      f"({result['checks']} checks, {result['failures']} failed)", flush=True)
        pool = ThreadPoolExecutor(max_workers=jobs)
        try:
            futures = {pool.submit(run_one, index, spec): index for index, spec in enumerate(tests)}
            for future in as_completed(futures):
                record(futures[future], future.result())
        except BaseException:
            # Ctrl-C or a runner error stops the whole selection, as a
            # sequential run did: queued programs never start and running
            # ones are killed promptly by run_program.
            stop.set()
            raise
        finally:
            pool.shutdown(wait=True, cancel_futures=True)
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
