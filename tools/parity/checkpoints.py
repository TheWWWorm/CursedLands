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
import json
import re
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
STEP = {"talk": ("talk", "topic"), "enter": ("enter",), "use": ("use",)}


def parse_step(text):
    words = text.split()
    if not words or words[0] not in STEP or len(words) != len(STEP[words[0]]) + 1:
        raise SystemExit(f"bad step {text!r}; known: " + ", ".join(f"{k} {' '.join(v[1:])}" for k, v in STEP.items()))
    return dict(zip(STEP[words[0]], words[1:]))


def kept(gs):
    return {k: v for k, v in gs.items() if not CLOCK.match(k)}


def make(a):
    from original_save import Decoder, read_slot
    decoder = Decoder(a.game_exe)
    before, after = read_slot(a.before, decoder), read_slot(a.after, decoder)
    steps = [parse_step(s) for s in a.step]
    entering = steps[0].get("enter")
    if entering and (entering != after["zone"] or any("enter" in s for s in steps[1:])):
        raise SystemExit(f"'enter' must come first and name the after save's zone ({after['zone']})")
    if not entering and before["zone"] != after["zone"]:
        raise SystemExit("the two saves are in different zones; start the steps with 'enter <zone>'")
    cp = {"zone": after["zone"], "from_zone": before["zone"], "campaign": a.campaign, "note": a.note or "",
          "steps": steps,
          "vars_before": kept(before["live"]["vars"]), "vars_after": kept(after["live"]["vars"])}
    STORE.mkdir(exist_ok=True)
    path = STORE / f"{a.name}.json"
    path.write_text(json.dumps(cp, indent=1, ensure_ascii=False, sort_keys=True) + "\n")
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
        if abs(e - v) > 1e-6:
            out.append(f"{k}: original {e:g}, remake {v:g}")
    return out


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
    run_cp = {"zone": cp["zone"], "vars_before": cp["vars_before"], "settle": 20.0 if entering else 2.2,
              "steps": [s for s in cp["steps"] if "enter" not in s]}
    (case / "checkpoint.json").write_text(json.dumps(run_cp))
    argv = [a.godot, "--path", str(REPO / "game"), "--headless", "--audio-driver", "Dummy", "--",
            "--no-movies", "--ei-path=" + str(data), "--tool=" + str(REPO / "tools/tests/original_checkpoint.gd"),
            "--checkpoint=" + str(case / "checkpoint.json")]
    log = case / "run.log"
    with log.open("w") as stream:
        subprocess.run(argv, stdout=stream, stderr=subprocess.STDOUT, env=env, timeout=a.timeout)
    text = log.read_text(errors="replace")
    found = [line for line in text.splitlines() if line.startswith("CHECKPOINT_RESULT ")]
    errors = [line for line in text.splitlines() if line.startswith(("SCRIPT ERROR:", "Parse Error:"))]
    if not found:
        return {"name": name, "error": "no result; see " + str(log), "log_tail": text[-1500:]}
    res = json.loads(found[-1].split(" ", 1)[1])
    entry, after = kept(res["entry"]), kept(res["after"])
    before, expect = cp["vars_before"], cp["vars_after"]
    # An entry checkpoint starts outside the zone: its delta includes the
    # zone entry, so it is measured from the loaded vars.
    base = before if entering else entry
    want = {k: expect.get(k, 0.0) for k in set(before) | set(expect) if before.get(k, 0.0) != expect.get(k, 0.0)}
    got = {k: after.get(k, 0.0) for k in set(base) | set(after) if base.get(k, 0.0) != after.get(k, 0.0)}
    report = {"name": name, "zone": cp["zone"], "note": cp.get("note", ""),
              "harness_failures": res["failures"], "script_errors": errors,
              "entry": [] if entering else diff(before, entry), "delta": diff(want, got),
              "original_changes": want, "remake_changes": got}
    report["ok"] = not (report["entry"] or report["delta"] or res["failures"] or errors)
    return report


def run(a):
    names = sorted(p.stem for p in STORE.glob("*.json"))
    if a.name:
        names = [n for n in names if any(s in n for s in a.name)]
    if not names:
        raise SystemExit("no checkpoints selected")
    if not a.godot:
        raise SystemExit("--godot is required (godot-4 not on PATH)")
    work = Path(tempfile.mkdtemp(prefix="ei-checkpoints-"))
    reports = []
    for n in names:
        cp = json.loads((STORE / f"{n}.json").read_text())
        r = run_one(n, cp, a, work)
        reports.append(r)
        if "error" in r:
            print(f"ERROR {n}: {r['error']}")
            continue
        print(("PASS " if r["ok"] else "FAIL ") + f"{n} ({r['zone']}{': ' + r['note'] if r['note'] else ''})")
        for kind in ("entry", "delta"):
            for line in r[kind]:
                print(f"    {kind}: {line}")
        if r["harness_failures"]:
            print(f"    {r['harness_failures']} harness check(s) failed; see {work / n / 'run.log'}")
        for line in r["script_errors"][:5]:
            print("    " + line)
    if a.out:
        a.out.write_text(json.dumps(reports, indent=1, ensure_ascii=False) + "\n")
    if not a.keep:
        shutil.rmtree(work, ignore_errors=True)
    if any("error" in r for r in reports):
        return 2
    return 0 if all(r["ok"] for r in reports) else 1


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)
    m = sub.add_parser("make", help="Record a checkpoint from two original save slots")
    m.add_argument("--game-exe", required=True, type=Path, help="Verified base-game game.exe (save decoder)")
    m.add_argument("--before", required=True, type=Path)
    m.add_argument("--after", required=True, type=Path)
    m.add_argument("--name", required=True)
    m.add_argument("--campaign", default="original", choices=("original", "lost_in_astral"))
    m.add_argument("--step", action="append", required=True, help="e.g. 'talk daughter b.daughter.z0_3'")
    m.add_argument("--note", help="What the step is, in words")
    w = sub.add_parser("sweep", help="Record entry checkpoints from a zone sweep (original/sweep.py output)")
    w.add_argument("--game-exe", required=True, type=Path)
    w.add_argument("--campaign", default="original", choices=("original", "lost_in_astral"))
    w.add_argument("--prefix", default="sweep", help="Checkpoint name prefix")
    w.add_argument("dir", type=Path)
    r = sub.add_parser("run", help="Replay checkpoints in the remake and compare")
    r.add_argument("--game-dir", type=Path, help="Owned Evil Islands installation")
    r.add_argument("--astral-dir", type=Path, help="Owned Lost in Astral installation")
    r.add_argument("--godot", default=shutil.which("godot-4") or shutil.which("godot"))
    r.add_argument("--name", action="append", help="Checkpoint name substring; repeat to combine")
    r.add_argument("--timeout", type=int, default=300)
    r.add_argument("--out", type=Path, help="Write the JSON report here")
    r.add_argument("--keep", action="store_true", help="Keep the isolated profiles and logs")
    a = p.parse_args()
    if a.cmd == "make":
        make(a)
        return 0
    if a.cmd == "sweep":
        sweep(a)
        return 0
    return run(a)


if __name__ == "__main__":
    sys.exit(main())
