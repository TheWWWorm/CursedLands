#!/usr/bin/env python3
"""Run one frozen export through normal-frame contact cold/warm measurements.

Use a new output directory per build and compare the same fixture/arguments.
Private Godot and NVIDIA driver caches are reused only for the warm run.
Other engine processes are sampled throughout; --allow-busy permits diagnostic
runs but marks their timings unqualified. Nothing touches installed caches.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import time


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def engines(exclude=None):
    found = []
    for entry in Path("/proc").glob("[0-9]*/exe"):
        try:
            pid = int(entry.parent.name)
            name = entry.resolve()
            if pid == exclude or not ("godot" in name.name.lower() or name.name == "CursedLands.x86_64"):
                continue
            args = (entry.parent / "cmdline").read_bytes().split(b"\0")
            found.append({"pid": pid, "executable": str(name), "headless": b"--headless" in args,
                          "command": [arg.decode(errors="replace") for arg in args if arg],
                          "proc_stat": (entry.parent / "stat").read_text()})
        except (OSError, RuntimeError):
            pass
    return found


def cache_state(root):
    return {str(path.relative_to(root)): {"bytes": path.stat().st_size, "sha256": sha(path)}
            for leaf in ["data", "cache", "driver"] for path in (root / leaf).rglob("*")
            if path.is_file() and (leaf == "driver" or "shader_cache" in str(path))}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--ei-path", type=Path, required=True)
    parser.add_argument("--map", default="bz2g")
    parser.add_argument("--renderer", choices=["gl_compatibility", "forward_plus", "mobile"], default="gl_compatibility")
    parser.add_argument("--natural", action="store_true")
    parser.add_argument("--no-deform", action="store_true")
    parser.add_argument("--allow-busy", action="store_true")
    parser.add_argument("--timeout", type=int, default=180)
    args = parser.parse_args()
    build = args.build.resolve()
    files = [build / name for name in ["CursedLands.x86_64", "CursedLands.pck", "libterrain_search.so"]]
    for path in files:
        if not path.is_file():
            parser.error(f"Missing export component: {path}")
    others = engines()
    if others and not args.allow_busy:
        parser.error("Other engines are active. Wait for them to finish, or use --allow-busy for explicitly unqualified diagnostics.")
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    source = Path(__file__).resolve().parent
    fixture = output / "fixture"
    fixture.mkdir()
    for name in ["ground_contact_cost.gd", "ground_contact.gd", "ground_contact_cost.py"]:
        shutil.copy2(source / name, fixture / name)
    root = output / "isolated"
    env = os.environ.copy()
    for key, leaf in [("XDG_DATA_HOME", "data"), ("XDG_CONFIG_HOME", "config"),
                      ("XDG_CACHE_HOME", "cache"), ("__GL_SHADER_DISK_CACHE_PATH", "driver")]:
        directory = root / leaf
        directory.mkdir(parents=True)
        env[key] = str(directory)
    env["__GL_SHADER_DISK_CACHE"] = "1"
    settings = root / "data/godot/app_userdata/Cursed Lands/settings.cfg"
    settings.parent.mkdir(parents=True)
    settings.write_text('[options]\ndisplay_mode=0\nresolution=1\nq_aa=0\nconfine_mouse=0\nauto_graphics=0\nshow_tutorial=0\n[display]\nresolution="800x600"\n[remake]\ngfx=4\n')
    command = [str(files[0]), "--render-thread", "safe", "--rendering-method", args.renderer,
               "--windowed", "--resolution", "800x600", "--position", "-10000,-10000", "--audio-driver", "Dummy",
               "--", "--ei-path=" + str(args.ei_path.resolve()), "--contact-map=" + args.map,
               "--tool=" + str(fixture / "ground_contact_cost.gd")]
    if args.natural:
        command.append("--contact-natural")
    if args.no_deform:
        command.append("--contact-no-deform")
    report = {"command": command, "fixture_sha256": {p.name: sha(p) for p in fixture.iterdir()},
              "build_sha256": {p.name: sha(p) for p in files}, "settings_before": settings.read_text(),
              "cache_environment": {key: env[key] for key in env if key.startswith("XDG_") or key.startswith("__GL_SHADER_")},
              "allow_busy": args.allow_busy, "runs": {}, "scope": "Preparation and steady viewport measurements; no gameplay FPS or device acceptance claim."}
    for temperature in ["cold", "warm"]:
        others = engines()
        if others and not args.allow_busy:
            raise RuntimeError("An engine started before the next run; use a fresh output directory later.")
        dest = output / temperature
        dest.mkdir()
        before = cache_state(root)
        if temperature == "cold" and before:
            raise RuntimeError("Cold caches are not empty")
        if temperature == "warm" and before != report["runs"]["cold"]["cache_after"]:
            raise RuntimeError("Cache state changed between cold and warm runs")
        print("START", temperature, args.renderer, args.map, flush=True)
        start = time.monotonic()
        observations = [{"seconds": 0.0, "processes": others}]
        reason = None
        log = dest / "run.log"
        with log.open("w") as stream:
            proc = subprocess.Popen(command, stdout=stream, stderr=subprocess.STDOUT, env=env)
            while proc.poll() is None:
                time.sleep(0.25)
                current = log.read_text()
                current_engines = engines(proc.pid)
                for process in current_engines:
                    stat = process["proc_stat"].rsplit(")", 1)[1].split()
                    # The launcher briefly probes the renderer in its own
                    # same-command child. Retain it in the raw evidence, but
                    # do not classify it as another concurrent workload.
                    process["own_pre_renderer_child"] = (
                        int(stat[1]) == proc.pid and process["command"] == command
                        and "Using Device:" not in current)
                observations.append({"seconds": time.monotonic() - start, "launcher_pid": proc.pid,
                                     "processes": current_engines})
                if "SCRIPT ERROR:" in current or time.monotonic() - start > args.timeout:
                    reason = "script error" if "SCRIPT ERROR:" in current else "timeout"
                    proc.terminate()
                    try:
                        proc.wait(timeout=3)
                    except subprocess.TimeoutExpired:
                        proc.kill(); proc.wait()
                    break
        elapsed = time.monotonic() - start
        text = log.read_text()
        errors = [line for line in text.splitlines() if line.startswith("FAIL ") or ("ERROR:" in line and "NO GRAB" not in line)]
        data = settings.parent
        result_path = data / "ground-contact-cost.json"
        result = json.loads(result_path.read_text()) if result_path.is_file() else {}
        for path in data.glob("ground-contact-cost*"):
            if path.is_file():
                shutil.copy2(path, dest / path.name)
                path.unlink()  # Warm must emit its own complete result and captures.
        images = {p.name: sha(p) for p in dest.glob("*.png")}
        expected = {f"ground-contact-cost-{args.map}-{distance}-{state}.png"
                    for distance in ["near", "far"] for state in ["off", "on", "restored"]}
        if set(images) != expected:
            errors.append("Missing or unexpected captures")
        if not result or result.get("failures") or len(result.get("rows", [])) != 2:
            errors.append("Incomplete or failed fixture result")
        clean = not any(any(not p.get("own_pre_renderer_child", False) for p in item["processes"])
                        for item in observations)
        row = {"seconds": elapsed, "return_code": proc.returncode, "termination_reason": reason,
               "errors": errors, "cache_before": before, "cache_after": cache_state(root),
               "timing_qualified_against_other_engines": clean, "process_observations": observations,
               "png_sha256": images, "result": result}
        report["runs"][temperature] = row
        (output / "report.json").write_text(json.dumps(report, indent=2) + "\n")
        print("RESULT", temperature, "clean_engines=" + str(clean), "errors=" + str(len(errors)),
              [(r["distance"], r["on"]["refresh_ms"], r["on"]["first_frame_ms"], r["on"]["viewport_gpu_ms"]["median"]) for r in result.get("rows", [])], flush=True)
        if proc.returncode or errors or reason:
            raise RuntimeError(f"Run failed; inspect {log}")
    report["cold_warm_png_identical"] = report["runs"]["cold"]["png_sha256"] == report["runs"]["warm"]["png_sha256"]
    (output / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    if not report["cold_warm_png_identical"]:
        raise RuntimeError("Cold/warm captures differ; inspect the retained images before accepting this run")


if __name__ == "__main__":
    main()
