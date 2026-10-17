#!/usr/bin/env python3
"""Run independent host/client processes against original data over both transports."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True, type=Path)
    parser.add_argument("--data", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[2]
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    results = []
    for index, transport in enumerate(("enet", "websocket")):
        processes = []
        streams = []
        profiles = []
        try:
            for role in ("host", "client"):
                profile = output / transport / role
                (profile / "data/godot/app_userdata/Cursed Lands").mkdir(parents=True)
                profiles.append(profile)
                env = dict(os.environ, XDG_DATA_HOME=str(profile / "data"),
                           XDG_CONFIG_HOME=str(profile / "config"), XDG_CACHE_HOME=str(profile / "cache"))
                cmd = [str(args.godot), "--headless", "--path", str(repo / "game"),
                       "--render-thread", "safe",
                       "--audio-driver", "Dummy", "--", "--ei-path=" + str(args.data), "--no-movies",
                       "--tool=" + str(Path(__file__).with_name("arena_online_peer.gd")),
                       "--peer-role=" + role, "--peer-transport=" + transport,
                       "--peer-port=" + str(30210 + index)]
                stream = (profile / "run.log").open("w")
                streams.append(stream)
                processes.append(subprocess.Popen(cmd, env=env, stdout=stream, stderr=subprocess.STDOUT))
                if role == "host":
                    deadline = time.monotonic() + 25
                    while time.monotonic() < deadline and processes[0].poll() is None:
                        if "ARENA_ONLINE_LISTENING" in (profile / "run.log").read_text():
                            break
                        time.sleep(0.1)
            for process in processes:
                process.wait(timeout=200)
        finally:
            for process in processes:
                if process.poll() is None:
                    process.kill()
                process.wait()
            for stream in streams:
                stream.close()
        peers = []
        for profile, process in zip(profiles, processes):
            path = profile / "data/godot/app_userdata/Cursed Lands/online-peer.json"
            report = json.loads(path.read_text()) if path.exists() else {"failures": ["missing report"]}
            report["exit_code"] = process.returncode
            report["errors"] = [line for line in (profile / "run.log").read_text().splitlines()
                                if line.startswith(("ERROR:", "SCRIPT ERROR:", "FAIL "))]
            peers.append(report)
        converged = all(peers[0].get(key) == peers[1].get(key) for key in ("health", "placements"))
        passed = converged and all(not peer["exit_code"] and not peer["failures"] and not peer["errors"] for peer in peers)
        result = {"transport": transport, "passed": passed, "results_match": converged, "peers": peers}
        results.append(result)
        print(json.dumps(result), flush=True)
    (output / "result.json").write_text(json.dumps(results, indent=2) + "\n")
    return 0 if all(result["passed"] for result in results) else 1


if __name__ == "__main__":
    raise SystemExit(main())
