#!/usr/bin/env python3
"""Run one sustained LiA speed on an explicit frozen Linux/NVIDIA bundle.

Each invocation owns a fresh output directory. Run 1x and 2x independently;
a failed first speed must not erase its artifacts or suppress the second.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import time


ERROR = re.compile(r"SCRIPT ERROR|Parse Error|Compile Error|^ERROR:", re.M)
BUNDLE = ("CursedLands.x86_64", "CursedLands.pck", "libterrain_search.so")


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def godot_processes():
    """Read only engine process identity, without arbitrary command arguments."""
    rows = []
    for proc in Path("/proc").iterdir():
        if not proc.name.isdigit():
            continue
        try:
            executable = (proc / "exe").resolve(strict=True)
            if not any(name in executable.name.lower() for name in ("godot", "cursedlands")):
                continue
            stat = (proc / "stat").read_text().rsplit(")", 1)[1].split()
            args = (proc / "cmdline").read_bytes().decode(errors="replace").split("\0")
            method = args[args.index("--rendering-method") + 1] if "--rendering-method" in args else "default"
            rows.append({"pid": int(proc.name), "parent": int(stat[1]), "state": stat[0],
                         "start_ticks": int(stat[19]), "executable": str(executable),
                         "headless": "--headless" in args, "requested_renderer": method})
        except (OSError, ValueError, IndexError):
            continue
    return sorted(rows, key=lambda row: row["pid"])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build", required=True, type=Path, help="Frozen bundle directory")
    parser.add_argument("--source", required=True, type=Path, help="Disposable authored Portal checkpoint")
    parser.add_argument("--data-root", required=True, type=Path, help="Original LiA game data directory")
    parser.add_argument("--output", required=True, type=Path, help="New per-run evidence directory")
    parser.add_argument("--speed", required=True, type=int, choices=(1, 2))
    parser.add_argument("--seconds", type=int, default=120)
    parser.add_argument("--display", default=":0")
    args = parser.parse_args()
    if not 4 <= args.seconds <= 600:
        parser.error("--seconds must be between 4 and 600; sustained acceptance uses 120")
    build = args.build.resolve(strict=True)
    source = args.source.resolve(strict=True)
    data = args.data_root.resolve(strict=True)
    fixture = Path(__file__).with_name("sustained_coop_delivery.gd").resolve(strict=True)
    before = {name: sha(build / name) for name in BUNDLE}
    source_sha = sha(source)
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    profile = output / "profile"
    profile.mkdir()
    frozen = output / fixture.name
    private_source = output / "route-source.sav"
    shutil.copy2(fixture, frozen)
    shutil.copy2(source, private_source)
    env = dict(os.environ, DISPLAY=args.display, XDG_DATA_HOME=str(profile),
               XDG_CONFIG_HOME=str(profile / "config"), XDG_CACHE_HOME=str(profile / "cache"), EI_FRESH="1")
    env.pop("WAYLAND_DISPLAY", None)
    cmd = [str(build / BUNDLE[0]), "--rendering-method", "forward_plus", "--windowed",
           "--resolution", "1280x720", "--audio-driver", "Dummy", "--render-thread", "safe", "--",
           "--ei-path=" + str(data), "--tool=" + str(frozen), "--route-save=" + str(private_source),
           "--seconds=" + str(args.seconds), "--speeds=" + str(args.speed), "--require-adapter=NVIDIA"]
    plan = {"command": cmd, "build_sha256": before, "source": str(source), "source_sha256": source_sha,
            "fixture_sha256": sha(frozen), "display": args.display, "seconds": args.seconds, "speed": args.speed,
            "other_process_inventory_scope": "All Godot/CursedLands processes, including this run's frontend and service."}
    (output / "plan.json").write_text(json.dumps(plan, indent=2) + "\n")
    log = output / "run.log"
    inventory = [{"wall_seconds": 0, "processes": godot_processes()}]
    started = time.monotonic()
    stopped = ""
    with log.open("w") as stream:
        child = subprocess.Popen(cmd, env=env, stdout=stream, stderr=subprocess.STDOUT, start_new_session=True)
        print(json.dumps({"event": "started", "pid": child.pid, "output": str(output), "speed": args.speed}), flush=True)
        next_inventory = started + 1
        try:
            while child.poll() is None:
                now = time.monotonic()
                if now >= next_inventory:
                    inventory.append({"wall_seconds": now - started, "processes": godot_processes()})
                    next_inventory = now + 1
                if now - started > 200 + args.seconds:
                    stopped = "timeout"
                elif ERROR.search(log.read_text(errors="replace")):
                    stopped = "engine error"
                if stopped:
                    try:
                        os.killpg(child.pid, signal.SIGTERM)
                    except ProcessLookupError:
                        pass
                    break
                time.sleep(0.2)
            child.wait(timeout=12)
        except (subprocess.TimeoutExpired, KeyboardInterrupt):
            stopped = stopped or "interrupted"
            try:
                os.killpg(child.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            child.wait()
    inventory.append({"wall_seconds": time.monotonic() - started, "processes": godot_processes()})
    (output / "processes.json").write_text(json.dumps(inventory, indent=2) + "\n")
    text = log.read_text(errors="replace")
    errors = [line for line in text.splitlines() if ERROR.search(line)]
    workers = []
    for path in profile.rglob("*.cfg.log"):
        lines = path.read_text(errors="replace").splitlines()
        workers.append({"path": str(path), "sha256": sha(path), "errors": [line for line in lines if ERROR.search(line)]})
    raw_path = profile / "godot/app_userdata/Cursed Lands/sustained-coop-delivery.json"
    try:
        raw = json.loads(raw_path.read_text()) if raw_path.exists() else {}
    except (OSError, json.JSONDecodeError) as error:
        errors.append("Cannot read fixture report: " + str(error))
        raw = {}
    renderer = raw.get("renderer_info", {})
    hardware = (renderer.get("method") == "forward_plus" and renderer.get("display") != "headless"
                and "nvidia" in renderer.get("adapter", "").lower())
    after = {name: sha(build / name) for name in BUNDLE}
    immutable = before == after and source_sha == sha(source) == sha(private_source)
    runs = raw.get("runs", [])
    complete = len(runs) == 1 and runs[0].get("speed") == args.speed and runs[0].get("wall_seconds", 0) >= args.seconds
    passed = (child.returncode == 0 and not stopped and not errors and not any(row["errors"] for row in workers)
              and hardware and immutable and complete and raw.get("failures", -1) == 0)
    own_pids = (child.pid, raw.get("worker_pid", -1))
    other_engines = {}
    for sample in inventory:
        for process in sample["processes"]:
            if process["pid"] not in own_pids:
                other_engines[(process["pid"], process["start_ticks"])] = process
    report = {**plan, "exit_code": child.returncode, "wall_seconds": time.monotonic() - started,
              "frontend_pid": child.pid, "worker_pid": raw.get("worker_pid"),
              "stopped": stopped, "errors": errors, "workers": workers, "renderer_info": renderer,
              "hardware_confirmed": hardware, "inputs_unchanged": immutable, "requested_phase_completed": complete,
              "checks": raw.get("checks"), "failures": raw.get("failures"), "passed": passed,
              "log_sha256": sha(log), "raw_report": str(raw_path),
              "process_inventory": str(output / "processes.json"),
              "other_engine_processes_seen": list(other_engines.values()),
              "artifacts": {str(path.relative_to(output)): sha(path) for path in profile.rglob("*")
                            if path.is_file() and path.suffix in (".json", ".png")},
              "limit": "Linux NVIDIA loopback; both frontends share one process. No Windows, WAN, busy-combat or full-playthrough claim."}
    (output / "run.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({key: report[key] for key in ("passed", "checks", "failures", "hardware_confirmed", "renderer_info", "stopped")}), flush=True)
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
