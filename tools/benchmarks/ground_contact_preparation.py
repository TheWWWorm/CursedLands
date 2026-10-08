#!/usr/bin/env python3
"""Compare exported Linux builds with fresh Godot/NVIDIA GL caches, then warm.

Run this while other game/Godot processes are stopped. Each output directory
must be new unless --resume completes an interrupted comparison with identical
inputs; installed caches, saved games and user settings are never touched.
The 24-frame on warmup includes driver preparation, not just shader parsing.
No GPU timing is converted into gameplay FPS. PNG identity is stronger than
pixel identity; if hashes differ, inspect the images before accepting a change.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def other_games():
    return subprocess.run(
        ["ps", "-C", "godot-4", "-C", "CursedLands.x86_64", "-o", "pid,etimes,args"],
        text=True, capture_output=True, check=False,
    ).stdout.strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline", type=Path, required=True)
    parser.add_argument("--candidate", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--ei-path", type=Path, required=True)
    parser.add_argument("--map", default="bz2g")
    parser.add_argument("--resume", action="store_true")
    args = parser.parse_args()
    for path in [args.baseline, args.candidate]:
        if not path.is_file():
            parser.error(f"Missing exported executable: {path}")
    if len(other_games().splitlines()) > 1:
        parser.error("Another game/Godot process is active; run after it exits.")
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=args.resume)
    tool = Path(__file__).with_name("ground_contact.gd").resolve()
    report = {"map": args.map, "renderer": "gl_compatibility",
              "tool_sha256": sha(tool), "runs": {}, "comparisons": {}}
    if args.resume:
        saved = json.loads((output / "report.json").read_text())
        for key in ["map", "renderer", "tool_sha256"]:
            if saved[key] != report[key]:
                parser.error(f"Cannot resume with changed {key}")
        expected = ["baseline_cold", "baseline_warm", "candidate_cold", "candidate_warm"]
        if list(saved["runs"]) != expected[:len(saved["runs"])]:
            parser.error("Completed runs must be a contiguous prefix of this comparison")
        report = saved
    for label, executable in [("baseline", args.baseline), ("candidate", args.candidate)]:
        root = output / label
        for child in ["data", "config", "cache", "driver"]:
            (root / child).mkdir(parents=True, exist_ok=args.resume)
        env = os.environ.copy()
        for key, child in [("XDG_DATA_HOME", "data"), ("XDG_CONFIG_HOME", "config"),
                           ("XDG_CACHE_HOME", "cache"), ("__GL_SHADER_DISK_CACHE_PATH", "driver")]:
            env[key] = str(root / child)
        env["__GL_SHADER_DISK_CACHE"] = "1"
        executable = executable.resolve()
        command = [str(executable), "--render-thread", "safe", "--rendering-method", "gl_compatibility",
                   "--windowed", "--resolution", "256x144", "--position", "-10000,-10000",
                   "--audio-driver", "Dummy", "--", "--ei-path=" + str(args.ei_path.resolve()),
                   "--contact-map=" + args.map, "--tool=" + str(tool)]
        for temperature in ["cold", "warm"]:
            run_key = label + "_" + temperature
            if run_key in report["runs"]:
                previous = report["runs"][run_key]
                if previous["command"] != command or previous["executable_sha256"] != sha(executable) \
                        or previous["pack_sha256"] != sha(executable.with_suffix(".pck")):
                    parser.error(f"Cannot resume with changed inputs for {run_key}")
                print("KEEP", label, temperature, flush=True)
                continue
            others = other_games()
            if len(others.splitlines()) > 1:
                raise RuntimeError("Another game started; do not contaminate the performance comparison:\n" + others)
            before_engine = len(list((root / "data").rglob("*.cache")))
            before_driver = len(list((root / "driver").rglob("*")))
            if temperature == "cold" and (before_engine or before_driver):
                parser.error(f"Cold caches are not empty for {label}; choose a new output directory")
            if temperature == "warm":
                cold = report["runs"][label + "_cold"]
                if before_engine != cold["engine_cache_after"] or before_driver != cold["driver_cache_after"]:
                    parser.error(f"Caches changed since {label} cold run; choose a new output directory")
            print("START", label, temperature, flush=True)
            start = time.monotonic()
            log = root / (temperature + ".log")
            with log.open("w") as stream:
                run = subprocess.run(command, env=env, stdout=stream, stderr=subprocess.STDOUT, timeout=150)
            text = log.read_text()
            errors = [line for line in text.splitlines() if line.startswith("FAIL ")
                      or ("ERROR:" in line and "NO GRAB" not in line)]
            if run.returncode or errors:
                raise RuntimeError(f"{label}/{temperature} failed; inspect {log}: {errors}")
            data = root / "data/godot/app_userdata/Cursed Lands"
            result = json.loads((data / "ground-contact-map-gl_compatibility.json").read_text())
            if result["failures"] or len(result["rows"]) != 2:
                raise RuntimeError(f"Incomplete map result: {log}")
            images = {p.name: sha(p) for p in data.glob("ground-contact-map-*.png")}
            expected_images = {f"ground-contact-map-gl_compatibility-{args.map}-{distance}-{state}.png"
                               for distance in ["near", "far"] for state in ["off", "on", "restored"]}
            if set(images) != expected_images:
                raise RuntimeError(f"Missing or unexpected captures in {data}")
            row = {"command": command, "elapsed_seconds": time.monotonic() - start,
                   "return_code": run.returncode, "other_game_processes_at_start": others,
                   "other_game_processes_at_end": other_games(),
                   "engine_cache_before": before_engine, "driver_cache_before": before_driver,
                   "engine_cache_after": len(list((root / "data").rglob("*.cache"))),
                   "driver_cache_after": len(list((root / "driver").rglob("*"))),
                   "executable_sha256": sha(executable), "pack_sha256": sha(executable.with_suffix(".pck")),
                   "result": result, "png_sha256": images, "log": str(log)}
            report["runs"][run_key] = row
            (output / "report.json").write_text(json.dumps(report, indent=2) + "\n")
            print("RESULT", label, temperature, [(r["distance"], r["on"]["warmup_ms"]) for r in result["rows"]], flush=True)
    for pair in [("baseline_cold", "candidate_cold"), ("baseline_cold", "baseline_warm"),
                 ("candidate_cold", "candidate_warm")]:
        a = report["runs"][pair[0]]["png_sha256"]
        b = report["runs"][pair[1]]["png_sha256"]
        report["comparisons"][" vs ".join(pair)] = {"all_pngs_identical": a == b, "files": len(a)}
    (output / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report["comparisons"], indent=2), flush=True)


if __name__ == "__main__":
    main()
