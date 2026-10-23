#!/usr/bin/env python3
"""Quest checkpoints recorded in the original game, replayed in the remake.

A checkpoint is two saves of the original (made in the zone, before and after
one player action, e.g. F5 quicksaves under Wine) and the action. `make`
reads both saves' live GS vars (original_save.py) into
checkpoints/<name>.json. `run` loads the "before" vars in an isolated remake
profile, enters the zone, performs the steps (tools/tests/original_checkpoint.gd)
and compares:

  entry  the remake's vars after entering the zone equal the original's
         "before" save (the save was made inside the zone, after its entry);
  delta  the step changes exactly the vars the original's step changed, to
         the same values.

Clock and zone-bookkeeping vars (gtime, zt.*, zs.*) are left out of both
comparisons. The remake process
never sees the expected values. Exit 0: all match; 1: differences; 2: errors.
"""
import argparse
import hashlib
import json
import math
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
STORE = HERE / "checkpoints"
# The campaign clock and the engine's zone-persistence bookkeeping: on leaving
# a zone the original sets zs.<zone> = 1 and zt.<zone> = gtime (base 57a21d,
# 57a49a) and reads them on re-entry. The remake keeps zone state in
# CampaignState.zones instead, so these are compared by neither check.
CLOCK = re.compile(r"^(gtime|zt\..*|zs\..*)$")
STEP = {"talk": ("talk", "topic"), "enter": ("enter",), "use": ("use",), "wait": ("wait",),
        "leave": ("leave", "destination")}
RECORDING_ONLY_VARS = frozenset({"cp_capture_nonce"})


def parse_step(text):
    if text == "reload": return {"reload": True}
    if text.startswith("script ") and text[7:].strip():
        return {"script": text[7:].strip()}
    words = text.split()
    if not words or words[0] not in STEP or len(words) != len(STEP[words[0]]) + 1:
        raise SystemExit(f"bad step {text!r}; known: " + ", ".join(f"{k} {' '.join(v[1:])}" for k, v in STEP.items()))
    return dict(zip(STEP[words[0]], words[1:]))


def kept(gs):
    return {k: v for k, v in gs.items() if not CLOCK.match(k)}


def file_hash(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def slot_identity(path):
    return {p.name: file_hash(p) for p in sorted(path.glob("*.sav"))}


def recording_only_vars(names):
    if not isinstance(names, list) or any(not isinstance(name, str) or name not in RECORDING_ONLY_VARS for name in names):
        raise ValueError("only cp_capture_nonce may be excluded as a recording-only variable")
    return set(names)


def validate_checkpoint(cp):
    if cp.get("campaign", "original") not in ("original", "lost_in_astral"):
        raise ValueError("unsupported campaign")
    if not isinstance(cp.get("zone"), str) or not re.fullmatch(r"[A-Za-z0-9_]+", cp["zone"]):
        raise ValueError("invalid zone")
    for field in ("vars_before", "vars_after"):
        if not isinstance(cp.get(field), dict) or any(not isinstance(k, str) or
                not isinstance(v, (int, float)) or not math.isfinite(v) for k, v in cp[field].items()):
            raise ValueError(f"invalid {field}")
    if not cp.get("steps") or not isinstance(cp["steps"], list):
        raise ValueError("checkpoint needs at least one action")
    for i, step in enumerate(cp["steps"]):
        if not isinstance(step, dict):
            raise ValueError("unknown step")
        actions = set(step) & (set(STEP) | {"script", "reload"})
        if len(actions) != 1:
            raise ValueError("each step needs exactly one action")
        action = next(iter(actions))
        if set(step) != set(STEP.get(action, (action,))):
            raise ValueError("missing or unexpected step fields")
        if "enter" in step and (i != 0 or step["enter"] != cp["zone"]):
            raise ValueError("enter must be first and match zone")
        if "wait" in step and not 0 <= float(step["wait"]) <= 300:
            raise ValueError("wait must be between 0 and 300 seconds")
        if action in ("use", "leave") and not re.fullmatch(r"[0-9]+", str(step[action])):
            raise ValueError("object/exit id must be a nonnegative integer")
        if action == "leave" and not re.fullmatch(r"[A-Za-z0-9_]+", str(step["destination"])):
            raise ValueError("invalid exit destination")
        if action in ("script", "talk") and (not isinstance(step[action], str) or not step[action].strip()):
            raise ValueError("empty operation")
        if action == "reload" and step[action] is not True:
            raise ValueError("reload must be true")
    for field in ("settle", "after_settle"):
        if field in cp and not 0 <= float(cp[field]) <= 300:
            raise ValueError(f"invalid {field}")
    if cp.get("schema", 1) == 2 and not cp.get("provenance", {}).get("original_executable_sha256"):
        raise ValueError("new checkpoint lacks original executable identity")
    for field in ("observations_before", "observations_after"):
        if field in cp and (not isinstance(cp[field], dict) or any(not isinstance(k, str) or
                not isinstance(v, (int, float)) or not math.isfinite(v) for k, v in cp[field].items())):
            raise ValueError(f"invalid {field}")
    if not isinstance(cp.get("probes", {}), dict) or any(not isinstance(k, str) or
            not isinstance(v, str) or not v.strip() for k, v in cp.get("probes", {}).items()):
        raise ValueError("invalid probes")
    if any(k.lower() == "money" for k in cp.get("probes", {})):
        raise ValueError("money is a reserved observation")
    recording = recording_only_vars(cp.get("provenance", {}).get("recording_only_vars", []))
    if recording & (set(cp["vars_before"]) | set(cp["vars_after"]) | set(cp.get("probes", {}))):
        raise ValueError("recording-only variables must not be compared as game state or probes")


def validate_work_dir(source, work):
    """Do not recursively copy the capture destination into its own runtime."""
    work = work.resolve()
    for tree in (source.resolve(), (REPO / "tools/tests").resolve()):
        if work == tree or tree in work.parents:
            raise ValueError("Results must be outside the game and test source folders")


def reproduction_argv(a, work, names):
    argv = [sys.executable, str(HERE / "checkpoints.py"), "run", "--godot", a.godot,
            "--game-source", str(a.game_source.resolve()), "--repeat", str(a.repeat),
            "--timeout", str(a.timeout), "--replay-selection", str(work.resolve() / "selection.json")]
    for flag, path in [("--game-dir", a.game_dir), ("--astral-dir", a.astral_dir)]:
        if path: argv += [flag, str(path.resolve())]
    for name in names: argv += ["--name", name]
    return argv


def make(a):
    from original_save import Decoder, read_slot
    decoder = Decoder(a.game_exe)
    before, after = read_slot(a.before, decoder), read_slot(a.after, decoder)
    steps = [parse_step(s) for s in a.step]
    entering = steps[0].get("enter")
    if entering and (entering != after["zone"] or any("enter" in s for s in steps[1:])):
        raise SystemExit(f"'enter' must come first and name the after save's zone ({after['zone']})")
    if not entering and before["zone"] != after["zone"] and not any("leave" in s for s in steps) \
            and not a.script_transition:
        raise SystemExit("different zones require an explicit enter or leave action")
    probes = json.loads(a.probes.read_text()) if a.probes else {}
    recording = recording_only_vars(getattr(a, "recording_only_var", []))
    if recording & set(probes):
        raise ValueError("a recording-only variable cannot also be a probe")
    excluded = set(probes) | recording
    cp = {"schema": 2, "zone": after["zone"] if entering else before["zone"],
          "expected_zone": after["zone"], "from_zone": before["zone"], "campaign": a.campaign, "note": a.note or "",
          "steps": steps,
          "vars_before": kept({k: v for k, v in before["live"]["vars"].items() if k not in excluded}),
          "vars_after": kept({k: v for k, v in after["live"]["vars"].items() if k not in excluded}),
          "fixture": {"money": before["live"]["money"]}, "probes": probes,
          "observations_before": {"money": before["live"]["money"],
              **{k: before["live"]["vars"].get(k, 0) for k in probes}},
          "observations_after": {"money": after["live"]["money"],
              **{k: after["live"]["vars"].get(k, 0) for k in probes}},
          "provenance": {"original_executable_sha256": file_hash(a.source_exe),
              "decoder_executable_sha256": file_hash(a.game_exe),
              "recording_only_vars": sorted(recording),
              "before": slot_identity(a.before), "after": slot_identity(a.after)}}
    if a.fixture:
        cp["fixture"].update(json.loads(a.fixture.read_text()))
    if a.settle is not None: cp["settle"] = a.settle
    if a.after_settle is not None: cp["after_settle"] = a.after_settle
    validate_checkpoint(cp)
    if not re.fullmatch(r"[A-Za-z0-9_-]+", a.name):
        raise SystemExit("checkpoint name must contain only letters, numbers, _ and -")
    STORE.mkdir(exist_ok=True)
    path = STORE / f"{a.name}.json"
    with path.open("x") as f:
        f.write(json.dumps(cp, indent=1, allow_nan=False, ensure_ascii=False, sort_keys=True) + "\n")
    changed = {k for k in set(cp["vars_before"]) | set(cp["vars_after"])
               if cp["vars_before"].get(k, 0.0) != cp["vars_after"].get(k, 0.0)}
    print(f"wrote {path.relative_to(REPO)}: {len(cp['vars_before'])} vars, step changes {sorted(changed)}")


def sweep(a):
    """Entry checkpoints from a zone sweep (folders NN_zone/{before,after})."""
    from original_save import Decoder, read_slot
    decoder = Decoder(a.game_exe)
    STORE.mkdir(exist_ok=True)
    for folder in sorted(p for p in a.dir.iterdir() if p.is_dir()):
        zone = folder.name.split("_", 1)[1]
        try:
            before, after = read_slot(folder / "before", decoder), read_slot(folder / "after", decoder)
        except (OSError, ValueError, KeyError) as e:
            print(f"skip {folder.name}: {e}")
            continue
        if after["zone"] != zone:
            print(f"skip {folder.name}: the after save is in {after['zone']}")
            continue
        cp = {"zone": zone, "from_zone": before["zone"], "campaign": a.campaign,
              "note": f"enter {zone} from {before['zone']}", "steps": [{"enter": zone}],
              "vars_before": kept(before["live"]["vars"]), "vars_after": kept(after["live"]["vars"])}
        name = f"{a.prefix}_enter_{zone}"
        (STORE / f"{name}.json").write_text(json.dumps(cp, indent=1, ensure_ascii=False, sort_keys=True) + "\n")
        changed = sorted(k for k in set(cp["vars_before"]) | set(cp["vars_after"])
                         if cp["vars_before"].get(k, 0.0) != cp["vars_after"].get(k, 0.0))
        print(f"{name}: {len(changed)} change(s) {changed[:6]}{' ...' if len(changed) > 6 else ''}")


def diff(expected, actual):
    out = []
    for k in sorted(set(expected) | set(actual)):
        e, v = expected.get(k, 0.0), actual.get(k, 0.0)
        if not isinstance(e, (float, int)) or not isinstance(v, (float, int)):
            if e != v: out.append(f"{k}: original {e!r}, remake {v!r}")
        elif not math.isfinite(e) or not math.isfinite(v) or abs(e - v) > 1e-6:
            out.append(f"{k}: original {e:g}, remake {v:g}")
    return out


def observation_diff(expected, actual):
    missing = sorted(set(expected) - set(actual))
    extra = sorted(set(actual) - set(expected))
    return ([f"missing observation {k}" for k in missing] +
            [f"unexpected observation {k}" for k in extra] +
            diff({k: v for k, v in expected.items() if k in actual},
                 {k: v for k, v in actual.items() if k in expected}))


def repeat_signature(capture):
    return dict(capture, entry=kept(capture["entry"]), after=kept(capture["after"]))


def capture_process(argv, log, env, timeout):
    from gameplay import run_program
    return run_program(argv, log, env, timeout)


def run_one(name, cp, a, work):
    from run import isolated_environment
    data = a.astral_dir if cp.get("campaign") == "lost_in_astral" else a.game_dir
    if data is None:
        return {"name": name, "error": "no game directory for " + cp.get("campaign", "original")}
    case = work / name
    case.mkdir(parents=True)
    env = isolated_environment(case, "Cursed Lands", data)
    entering = bool(cp["steps"]) and "enter" in cp["steps"][0]
    # An entry checkpoint was recorded with ~20 s in the zone after arrival.
    run_cp = {"zone": cp["zone"], "vars_before": cp["vars_before"],
              "campaign": cp.get("campaign", "original"),
              "settle": cp.get("settle", 20.0 if entering else 2.2),
              "after_settle": cp.get("after_settle", 2.0),
              "fixture": cp.get("fixture", {}), "probes": cp.get("probes", {}),
              "steps": [s for s in cp["steps"] if "enter" not in s]}
    (case / "checkpoint.json").write_text(json.dumps(run_cp))
    argv = [a.godot, "--path", str(a.runtime), "--headless", "--audio-driver", "Dummy", "--",
            "--no-movies", "--ei-path=" + str(data), "--tool=" + str(a.runtime / "tools/tests/original_checkpoint.gd"),
            "--checkpoint=" + str(case / "checkpoint.json")]
    log = case / "run.log"
    code, capture_error = capture_process(argv, log, env, a.timeout)
    text = log.read_text(errors="replace")
    found = [line for line in text.splitlines() if line.startswith("CHECKPOINT_RESULT ")]
    errors = [line for line in text.splitlines() if line.startswith(("ERROR:", "SCRIPT ERROR:", "Parse Error:"))]
    if len(found) != 1 or code not in (0, 1) or errors or capture_error:
        return {"name": name, "error": f"capture incomplete/invalid (exit {code}, {len(found)} result records); see {log}",
                "script_errors": errors, "log_tail": text[-1500:]}
    res = json.loads(found[-1].split(" ", 1)[1])
    entry, after = kept(res["entry"]), kept(res["after"])
    before, expect = cp["vars_before"], cp["vars_after"]
    # An entry checkpoint starts outside the zone: its delta includes the
    # zone entry, so it is measured from the loaded vars.
    base = before if entering else entry
    want = {k: expect.get(k, 0.0) for k in set(before) | set(expect) if before.get(k, 0.0) != expect.get(k, 0.0)}
    got = {k: after.get(k, 0.0) for k in set(base) | set(after) if base.get(k, 0.0) != after.get(k, 0.0)}
    report = {"name": name, "zone": cp["zone"], "note": cp.get("note", ""),
              "harness_failures": res["failures"], "checks": res["checks"], "script_errors": errors,
              "entry": [] if entering else diff(before, entry), "delta": observation_diff(want, got),
              "observations": observation_diff(cp.get("observations_after", {}), res.get("observations_after", {})) if "observations_after" in cp else [],
              "observations_entry": observation_diff(cp.get("observations_before", {}), res.get("observations_entry", {})) if "observations_before" in cp and not entering else [],
              "destination": [] if res.get("zone") == cp.get("expected_zone", cp["zone"]) else
                  [f"original {cp.get('expected_zone', cp['zone'])}, remake {res.get('zone')}"] ,
              "original_changes": want, "remake_changes": got,
              "capture": res, "checkpoint_sha256": hashlib.sha256(json.dumps(cp, sort_keys=True).encode()).hexdigest(),
              "log": str(log), "log_sha256": file_hash(log), "exit_code": code}
    report["ok"] = code == 0 and res["checks"] > 0 and not (report["entry"] or report["delta"] or
            report["observations"] or report["observations_entry"] or report["destination"] or res["failures"] or errors)
    return report


def run(a):
    from run import command, isolated_environment, stage_game, write_json
    source_selection = (json.loads(a.replay_selection.read_text()) if a.replay_selection else
                        {p.stem: json.loads(p.read_text()) for p in STORE.glob("*.json")})
    names = sorted(source_selection)
    if a.name:
        names = [n for n in names if any(s in n for s in a.name)]
    if not names:
        raise SystemExit("no checkpoints selected")
    if not a.godot:
        raise SystemExit("--godot is required (godot-4 not on PATH)")
    if a.repeat < 1:
        raise SystemExit("--repeat must be positive")
    a.game_source = a.game_source.resolve()
    a.godot = shutil.which(a.godot) or str(Path(a.godot).resolve())
    if a.work_dir:
        work = a.work_dir.resolve()
        validate_work_dir(a.game_source, work)
        work.mkdir(parents=True, exist_ok=False)
    else:
        work = Path(tempfile.mkdtemp(prefix="ei-checkpoints-"))
        validate_work_dir(a.game_source, work)
    print("Checkpoint evidence:", work, flush=True)
    selected = {n: source_selection[n] for n in names}
    if any(not re.fullmatch(r"[A-Za-z0-9_-]+", n) for n in names):
        raise ValueError("invalid checkpoint name in selection")
    for cp in selected.values(): validate_checkpoint(cp)
    write_json(work / "selection.json", selected)
    write_json(work / "tool-source.json", {str(p.relative_to(REPO)): file_hash(p) for p in
               [HERE / "checkpoints.py", REPO / "tools/tests/original_checkpoint.gd"]})
    identities = {}
    for label, path in [("original", a.game_dir), ("lost_in_astral", a.astral_dir)]:
        if path:
            assets = [path / "game.exe", path / "res/database.res", path / "res/texts.res"]
            assets += sorted((path / "maps").glob("*.mob"))
            identities[label] = {str(p.relative_to(path)): file_hash(p) for p in assets if p.is_file()}
    write_json(work / "asset-source.json", identities)
    a.runtime, _ = stage_game(a.game_source, work)
    tool = a.runtime / "tools/tests/original_checkpoint.gd"
    tool.parent.mkdir(exist_ok=True)
    shutil.copy2(REPO / "tools/tests/original_checkpoint.gd", tool)
    write_json(work / "runtime-source.json", {p.relative_to(a.runtime).as_posix(): file_hash(p)
               for p in sorted(a.runtime.rglob("*")) if p.is_file()})
    data = a.game_dir or a.astral_dir
    env = isolated_environment(work / "import-profile", "Cursed Lands", data)
    engine = [a.godot, "--headless", "--audio-driver", "Dummy", "--path", str(a.runtime), "--editor", "--import", "--quit"]
    command(engine, work / "import-bootstrap.log", env, a.timeout, import_bootstrap=True)
    command(engine, work / "import.log", env, a.timeout)
    reproduce = reproduction_argv(a, work, names)
    (work / "reproduce.sh").write_text("#!/bin/sh\nset -eu\n" + shlex.join(reproduce) + ' --work-dir "${1:?new output directory required}"\n')
    (work / "reproduce.sh").chmod(0o755)
    reports = []
    for n in names:
        cp = selected[n]
        captures = []
        for repetition in range(a.repeat):
            try:
                captures.append(run_one(n + "/repeat-" + str(repetition + 1), cp, a, work))
            except (OSError, ValueError, KeyError, subprocess.TimeoutExpired) as e:
                captures.append({"name": n, "error": str(e)})
        r = dict(captures[0], name=n, repetitions=captures)
        if any("error" in c for c in captures):
            r["error"] = next(c["error"] for c in captures if "error" in c)
            r["ok"] = False
        else:
            # Only semantic state is compared; paths and process counters differ.
            r["repeatability_verified"] = a.repeat > 1 and all(repeat_signature(c["capture"]) ==
                    repeat_signature(captures[0]["capture"]) for c in captures[1:])
            if a.repeat > 1 and not r["repeatability_verified"]:
                r["error"] = "repeat captures disagree"
            r["ok"] = all(c["ok"] for c in captures) and "error" not in r
        reports.append(r)
        if "error" in r:
            print(f"ERROR {n}: {r['error']}")
            continue
        print(("PASS " if r["ok"] else "FAIL ") + f"{n} ({r['zone']}{': ' + r['note'] if r['note'] else ''})")
        for kind in ("entry", "delta", "observations", "observations_entry", "destination"):
            for line in r[kind]:
                print(f"    {kind}: {line}")
        if r["harness_failures"]:
            print(f"    {r['harness_failures']} harness check(s) failed; see {r['log']}")
        for line in r["script_errors"][:5]:
            print("    " + line)
    write_json(work / "report.json", reports)
    if a.out:
        write_json(a.out, reports)
    if not a.keep and not a.work_dir:
        shutil.rmtree(work, ignore_errors=True)
    if any("error" in r for r in reports):
        return 2
    return 0 if all(r["ok"] for r in reports) else 1


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)
    m = sub.add_parser("make", help="Record a checkpoint from two original save slots")
    m.add_argument("--game-exe", required=True, type=Path, help="Verified base-game game.exe (save decoder)")
    m.add_argument("--source-exe", required=True, type=Path, help="Executable that actually produced the two saves")
    m.add_argument("--before", required=True, type=Path)
    m.add_argument("--after", required=True, type=Path)
    m.add_argument("--name", required=True)
    m.add_argument("--campaign", default="original", choices=("original", "lost_in_astral"))
    m.add_argument("--step", action="append", required=True, help="e.g. 'talk daughter b.daughter.z0_3'")
    m.add_argument("--note", help="What the step is, in words")
    m.add_argument("--fixture", type=Path, help="Explicit prepared inventory, party, and setup commands JSON")
    m.add_argument("--probes", type=Path, help="Map original diagnostic GS variable names to read-only expressions")
    m.add_argument("--recording-only-var", action="append", default=[], choices=sorted(RECORDING_ONLY_VARS),
                   help="Exclude this exact native capture nonce, retaining its name in provenance; repeatable")
    m.add_argument("--settle", type=float)
    m.add_argument("--after-settle", type=float)
    m.add_argument("--script-transition", action="store_true", help="The recorded script/dialogue intentionally changes zone; verify the native final destination")
    w = sub.add_parser("sweep", help="Record entry checkpoints from a zone sweep (original/sweep.py output)")
    w.add_argument("--game-exe", required=True, type=Path)
    w.add_argument("--campaign", default="original", choices=("original", "lost_in_astral"))
    w.add_argument("--prefix", default="sweep", help="Checkpoint name prefix")
    w.add_argument("dir", type=Path)
    r = sub.add_parser("run", help="Replay checkpoints in the remake and compare")
    r.add_argument("--game-dir", type=Path, help="Owned Evil Islands installation")
    r.add_argument("--astral-dir", type=Path, help="Owned Lost in Astral installation")
    r.add_argument("--godot", default=shutil.which("godot-4") or shutil.which("godot"))
    r.add_argument("--game-source", type=Path, default=REPO / "game")
    r.add_argument("--name", action="append", help="Checkpoint name substring; repeat to combine")
    r.add_argument("--timeout", type=int, default=300)
    r.add_argument("--out", type=Path, help="Write the JSON report here")
    r.add_argument("--keep", action="store_true", help="Keep the isolated profiles and logs")
    r.add_argument("--work-dir", type=Path, help="New persistent evidence directory (never overwritten)")
    r.add_argument("--repeat", type=int, default=2, help="Fresh captures per checkpoint; default verifies determinism")
    r.add_argument("--replay-selection", type=Path, help="Replay retained checkpoint inputs and original observations")
    a = p.parse_args()
    if a.cmd == "make":
        make(a)
        return 0
    if a.cmd == "sweep":
        sweep(a)
        return 0
    return run(a)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, KeyError, RuntimeError, subprocess.TimeoutExpired) as exc:
        print("Checkpoint setup/capture error:", exc, file=sys.stderr)
        sys.exit(2)
