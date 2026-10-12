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
import heapq
import random
import selectors
import socket
import threading


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


class DatagramLink:
    """Bidirectional impairment below ENet, including ACKs and retransmits.

    Only this test's loopback UDP sockets are touched. Reliable retransmission,
    congestion/window behavior and application ping still belong to real ENet.
    Delay/loss start after zone loading; a one-client link is intentional.
    """
    def __init__(self, directory, profile, listen_port, server_port):
        self.directory = directory
        self.profile = profile
        self.front = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.front.bind(('127.0.0.1', listen_port))
        self.back = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.back.connect(('127.0.0.1', server_port))
        self.front.setblocking(False); self.back.setblocking(False)
        self.select = selectors.DefaultSelector()
        self.select.register(self.front, selectors.EVENT_READ, 'up')
        self.select.register(self.back, selectors.EVENT_READ, 'down')
        self.client = None
        self.queue = []
        self.sequence = 0
        self.wire_at = {'up': 0., 'down': 0.}
        self.enabled_at = None
        self.random = random.Random(621012)
        self.stopping = threading.Event()
        self.stats = {'profile': profile, 'directions': {d: {'received': 0, 'bytes': 0, 'forwarded': 0,
                      'random_drops': 0, 'queue_drops': 0, 'max_datagram': 0, 'max_delay_ms': 0} for d in ('up', 'down')},
                      'queue_peak': 0, 'windows': [], 'errors': []}
        self.thread = threading.Thread(target=self.run, daemon=True)

    def start(self):
        self.thread.start()

    def run(self):
        next_window = time.monotonic() + 1
        try:
            while not self.stopping.is_set():
                now = time.monotonic()
                if self.enabled_at is None and (self.directory / 'go').exists():
                    self.enabled_at = now
                timeout = min(.005, max(0, self.queue[0][0] - now)) if self.queue else .005
                for key, _ in self.select.select(timeout):
                    direction = key.data
                    while True:
                        try:
                            if direction == 'up':
                                data, address = self.front.recvfrom(65535)
                                if self.client is not None and self.client != address:
                                    raise RuntimeError('Unexpected second client on one-client link')
                                self.client = address
                            else:
                                data = self.back.recv(65535)
                        except BlockingIOError:
                            break
                        except ConnectionRefusedError:
                            break
                        now = time.monotonic()
                        row = self.stats['directions'][direction]
                        row['received'] += 1; row['bytes'] += len(data)
                        row['max_datagram'] = max(row['max_datagram'], len(data))
                        active = self.enabled_at is not None
                        p = self.profile if active else {'rtt_ms': 0, 'jitter_ms': 0, 'loss': 0, 'kbps': 0}
                        if self.random.random() < p['loss']:
                            row['random_drops'] += 1
                            continue
                        elapsed = now - self.enabled_at if active else 0
                        extra = p.get('burst_rtt_ms', 0) if active and elapsed % 25 >= 12 and elapsed % 25 < 14 else 0
                        latency = max(0, (p['rtt_ms'] + extra + self.random.uniform(-p['jitter_ms'], p['jitter_ms'])) / 2000)
                        # Account for UDP/IPv4 plus an explicit 60-byte tunnel allowance.
                        wire = (len(data) + 88) * 8 / (p['kbps'] * 1000) if p['kbps'] else 0
                        at = max(now, self.wire_at[direction]) + wire
                        wire_end = at
                        at += latency
                        if at - now > 2.5:
                            row['queue_drops'] += 1
                            continue
                        self.wire_at[direction] = wire_end
                        row['max_delay_ms'] = max(row['max_delay_ms'], (at - now) * 1000)
                        self.sequence += 1
                        heapq.heappush(self.queue, (at, self.sequence, direction, data))
                        self.stats['queue_peak'] = max(self.stats['queue_peak'], len(self.queue))
                now = time.monotonic()
                while self.queue and self.queue[0][0] <= now:
                    _, _, direction, data = heapq.heappop(self.queue)
                    if direction == 'up': self.back.send(data)
                    elif self.client: self.front.sendto(data, self.client)
                    self.stats['directions'][direction]['forwarded'] += 1
                if now >= next_window:
                    next_window = now + 1
                    self.stats['windows'].append({'elapsed': now - self.enabled_at if self.enabled_at else -1,
                        'queue': len(self.queue), 'directions': {k: dict(v) for k, v in self.stats['directions'].items()}})
        except Exception as error:
            self.stats['errors'].append(repr(error))
        finally:
            self.select.close(); self.front.close(); self.back.close()

    def close(self):
        self.stopping.set(); self.thread.join(3)
        self.stats['enabled'] = self.enabled_at is not None
        (self.directory / 'link.json').write_text(json.dumps(self.stats, indent=2) + '\n')

PROFILES = {
    'loopback': {'rtt_ms': 0, 'jitter_ms': 0, 'loss': 0, 'kbps': 0},
    'moderate': {'rtt_ms': 80, 'jitter_ms': 20, 'loss': .01, 'kbps': 2000},
    'poor': {'rtt_ms': 240, 'jitter_ms': 80, 'loss': .03, 'kbps': 512},
    'spikes': {'rtt_ms': 120, 'jitter_ms': 40, 'loss': .02, 'kbps': 1000, 'burst_rtt_ms': 1200},
}

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build", required=True, type=Path, help="Frozen bundle directory")
    parser.add_argument("--source", required=True, type=Path, help="Disposable authored Portal checkpoint")
    parser.add_argument("--data-root", required=True, type=Path, help="Original LiA game data directory")
    parser.add_argument("--output", required=True, type=Path, help="New per-run evidence directory")
    parser.add_argument("--speed", required=True, type=int, choices=(1, 2))
    parser.add_argument("--seconds", type=int, default=120)
    parser.add_argument("--display", default=":0")
    parser.add_argument("--profile", choices=PROFILES, required=True)
    parser.add_argument("--actors", type=int, default=48)
    parser.add_argument("--zone", default="gz1h")
    parser.add_argument("--minimum-population", type=int, default=350)
    parser.add_argument("--long-routes", action="store_true")
    parser.add_argument("--capture", action="store_true")
    parser.add_argument("--profile-simulation", action="store_true")
    parser.add_argument("--independent-client", action="store_true")
    parser.add_argument("--command-ms", type=int, default=1000, help="Long player route command interval in milliseconds")
    args = parser.parse_args()
    if not 4 <= args.seconds <= 600:
        parser.error("--seconds must be between 4 and 600; sustained acceptance uses 120")
    if not 100 <= args.command_ms <= 5000:
        parser.error("--command-ms must be between 100 and 5000")
    build = args.build.resolve(strict=True)
    source = args.source.resolve(strict=True)
    data = args.data_root.resolve(strict=True)
    fixture = Path(__file__).with_name("wan_coop_stress.gd").resolve(strict=True)
    before = {name: sha(build / name) for name in BUNDLE}
    source_sha = sha(source)
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    profile = output / "profile"
    profile.mkdir()
    frozen = output / fixture.name
    private_source = output / "route-source.sav"
    shutil.copy2(fixture, frozen)
    shutil.copy2(fixture.with_name("wan_standalone_guest.gd"), output / "wan_standalone_guest.gd")
    shutil.copy2(source, private_source)
    env = dict(os.environ, DISPLAY=args.display, XDG_DATA_HOME=str(profile),
               XDG_CONFIG_HOME=str(profile / "config"), XDG_CACHE_HOME=str(profile / "cache"), EI_FRESH="1")
    env.pop("WAYLAND_DISPLAY", None)
    cmd = [str(build / BUNDLE[0]), "--rendering-method", "forward_plus", "--windowed",
           "--resolution", "1280x720", "--audio-driver", "Dummy", "--render-thread", "safe", "--",
           "--ei-path=" + str(data), "--tool=" + str(frozen), "--route-save=" + str(private_source),
           "--seconds=" + str(args.seconds), "--speeds=" + str(args.speed), "--require-adapter=NVIDIA"]
    plan = {"command": cmd, "build_sha256": before, "source": str(source), "source_sha256": source_sha,
            "fixture_sha256": sha(frozen), "independent_fixture_sha256": sha(output / "wan_standalone_guest.gd"), "display": args.display, "seconds": args.seconds, "speed": args.speed,
            "other_process_inventory_scope": "All Godot/CursedLands processes, including this run's frontend and service."}
    (output / "plan.json").write_text(json.dumps(plan, indent=2) + "\n")
    stress = {'players': 3 if args.independent_client else 2, 'source': str(private_source), 'directory': str(output), 'seconds': args.seconds, 'speed': args.speed, 'actors': args.actors,
              'profile': args.profile, 'server_port': 29945, 'proxy_port': 29946, 'zone': args.zone,
              'profile_simulation': args.profile_simulation, 'command_ms': args.command_ms, 'minimum_population': args.minimum_population, 'long_routes': args.long_routes, 'capture': args.capture, 'max_gap_ms': 2000 if args.profile == 'spikes' else 1000}
    (output / 'stress.json').write_text(json.dumps(stress, indent=2) + '\n')
    cmd.append('--stress-plan=' + str(output / 'stress.json'))
    plan['stress'] = stress
    (output / "plan.json").write_text(json.dumps(plan, indent=2) + "\n")
    link = DatagramLink(output, PROFILES[args.profile], stress['proxy_port'], stress['server_port'])
    link.start()
    second_link = DatagramLink(output / 'standalone-link', PROFILES[args.profile], stress['proxy_port'] + 1, stress['server_port']) if args.independent_client else None
    if second_link:
        second_link.directory.mkdir()
        second_link.start()
    standalone = None
    standalone_log = None
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
                if second_link and (output / 'go').exists() and not (second_link.directory / 'go').exists():
                    (second_link.directory / 'go').write_text('go')
                if second_link and standalone is None and (output / 'launch-third').exists():
                    profile2 = output / 'standalone-profile'
                    env2 = dict(env, XDG_DATA_HOME=str(profile2), XDG_CONFIG_HOME=str(profile2 / 'config'), XDG_CACHE_HOME=str(profile2 / 'cache'))
                    standalone_log = (output / 'standalone.log').open('w')
                    cmd2 = [x for x in cmd if not x.startswith('--tool=')]
                    cmd2.append('--tool=' + str(output / 'wan_standalone_guest.gd'))
                    standalone = subprocess.Popen(cmd2, env=env2, stdout=standalone_log, stderr=subprocess.STDOUT, start_new_session=True)
                if now >= next_inventory:
                    inventory.append({"wall_seconds": now - started, "processes": godot_processes()})
                    next_inventory = now + 1
                if now - started > 200 + args.seconds:
                    stopped = "timeout"
                elif standalone and standalone.poll() is not None and standalone.returncode != 0:
                    stopped = "independent client exited with " + str(standalone.returncode)
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
    link.close()
    if second_link: second_link.close()
    if standalone:
        try: standalone.wait(timeout=15)
        except subprocess.TimeoutExpired:
            os.killpg(standalone.pid, signal.SIGTERM); standalone.wait(timeout=10)
        standalone_log.close()
    inventory.append({"wall_seconds": time.monotonic() - started, "processes": godot_processes()})
    (output / "processes.json").write_text(json.dumps(inventory, indent=2) + "\n")
    text = log.read_text(errors="replace")
    errors = [line for line in text.splitlines() if ERROR.search(line)]
    if standalone:
        errors += [line for line in (output / 'standalone.log').read_text(errors='replace').splitlines() if ERROR.search(line)]
        if standalone.returncode != 0: errors.append('Independent client failed: ' + str(standalone.returncode))
        if second_link.stats['errors']: errors += second_link.stats['errors']
    workers = []
    for path in output.glob("*.cfg.log"):
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
              and hardware and immutable and complete and raw.get("failures", -1) == 0 and link.stats["enabled"] and not link.stats["errors"])
    own_pids = (child.pid, raw.get("worker_pid", -1), standalone.pid if standalone else -1)
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
              "link": link.stats, "independent_link": second_link.stats if second_link else None, "independent_pid": standalone.pid if standalone else None,
              "limit": "Linux NVIDIA with real ENet datagram impairment; existing NPC orders driven by the fixture. Separate authority, owner and guest views in one process; optional extra guest uses its own process and link. Emulated WAN, not actual ZeroTier or Windows; no full-playthrough claim."}
    (output / "run.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({key: report[key] for key in ("passed", "checks", "failures", "hardware_confirmed", "renderer_info", "stopped")}), flush=True)
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
