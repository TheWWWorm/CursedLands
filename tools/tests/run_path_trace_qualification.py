#!/usr/bin/env python3
"""Qualify an exported PT build on an explicit NVIDIA GPU and X11 display.

Linux Vulkan and Windows DX12 through Wine use the same frozen fixtures and
failure gates. See docs/path-tracing-qualification.md for commands and limits.
Only Python's standard library and nvidia-smi are required on the Linux host.
"""
from __future__ import annotations

import argparse
import csv
import fcntl
import hashlib
import json
import math
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
import time
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
TESTS = ROOT / "tools/tests"
RUNNER_PATH = Path(__file__).resolve()
RUNNER_SHA256 = hashlib.sha256(RUNNER_PATH.read_bytes()).hexdigest()
PROFILE = {"confine_mouse": 0, "show_fps": 1, "volume_sfx": 0, "volume_stream": 0, "volume_voice": 0}
# Deliberately include only self-contained tests. Historical reference-pack
# benchmarks require their own pinned inputs and are not silently substituted.
REPORTS = {
    "device": "path-device.json", "motion": "path-motion.json", "resolution": "path-resolution.json",
    "lifecycle": "path-lifecycle.json", "controller": "path-controller.json", "detached_live": "path-detached-live.json",
    "resolution_performance": "path-resolution-performance.json", "sustained": "path-sustained-results.json",
    "topology": "path-topology-results.json", "variance": "path-variance.json", "quality": "path-quality.json",
    "glossy": "path-glossy.json", "sampling": "path-sampling.json", "contacts": "path-contacts.json",
    "foliage": "path-foliage.json", "terrain": "path-terrain.json", "surface_maps": "path-surface-maps.json",
    "surface_detail": "path-surface-detail.json", "emitters": "path-emitters.json", "lighting": "path-lighting.json",
    "light_history": "path-light-history.json", "daylight": "path-daylight.json", "live": "path-live.json",
    "outdoor": "path-outdoor.json", "cave": "path-cave.json", "receivers": "path-receivers.json",
    "underwater": "path-underwater.json", "water_live": "live.json", "fsr": "rt-fsr.json",
    "shader_ui": "shader-compilation-screen.json", "shader_live": "shader-compilation-live.json",
    "shader_arena": "shader-compilation-arena.json", "shader_scene": "shader-compilation-scene.json",
    "shader_water": "shader-compilation-water.json",
    "shader_settings": "shader-compilation-settings.json",
}
FIXTURES = {"water_live": "water_raytrace_live.gd", "shader_ui": "shader_compilation_screen.gd",
            "shader_live": "shader_compilation_live.gd", "shader_arena": "shader_compilation_arena.gd",
            "shader_scene": "shader_compilation_scene.gd", "shader_water": "shader_compilation_water.gd",
            "shader_settings": "shader_compilation_settings.gd"}
GROUPS = {
    "core": ["device", "motion", "lifecycle", "topology", "controller", "detached_live", "resolution", "sustained"],
    "preparation": ["shader_ui", "shader_live", "shader_arena", "shader_scene", "shader_water", "shader_settings"],
    "full": [name for name in REPORTS if name not in ("fsr", "resolution_performance")],
    "sdk": ["resolution", "fsr", "sustained"],
    "benchmark": ["resolution_performance"],
}
ERROR = re.compile(r"SCRIPT ERROR:|^ERROR:|Parse Error|Unhandled exception|^FAIL |device (?:removed|lost)|VK_ERROR_DEVICE_LOST", re.I)
REFRESH_DIAGNOSTIC = "ERROR: An error occurred while trying to get the screen refresh rate."
PROTECTED_ENV = {"DISPLAY", "XAUTHORITY", "WAYLAND_DISPLAY", "WINEPREFIX", "WINEARCH", "XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME"}
DESCENDANT_EXIT_GRACE = 5.0


def sha(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def write_json(path: Path, value) -> None:
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, indent=2) + "\n")
    temporary.replace(path)


def expand_suites(names: list[str]) -> list[str]:
    result = []
    for name in names:
        for suite in GROUPS.get(name, [name]):
            if suite not in REPORTS:
                raise ValueError("Unknown suite: " + suite)
            if suite not in result:
                result.append(suite)
    return result


def reserve_directory(path: Path, kind: str) -> Path:
    path = path.expanduser().resolve()
    # Existing profiles, including previously generated test profiles, are
    # never reset. Each qualification has a new profile and evidence root.
    normal = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share")).resolve()
    if kind == "profile" and (path == normal or normal in path.parents):
        raise ValueError("Use a profile outside the normal application-data directory")
    path.mkdir(parents=True, exist_ok=False)
    (path / ".pt-qualification").write_text(kind + "\n")
    return path


def settings(resolution: str) -> str:
    values = {**PROFILE, "auto_graphics": 0, "display_mode": 0, "net_directory": 0,
              "net_upnp": 0, "net_lan": 0, "autosave": 0, "vsync": 0, "fps_limit": 0,
              "fsr_upscaling": 0, "fsr_frame_generation": 0}
    return "[options]\n" + "".join(f"{key}={value}\n" for key, value in values.items()) + f'[display]\nresolution="{resolution}"\n'


def host_path(path: Path, wine: bool) -> str:
    return "Z:" + str(path) if wine else str(path)


def freeze_fixtures(destination: Path, wine: bool) -> dict:
    destination.mkdir()
    hashes = {}
    prefix = host_path(destination, wine) + "/"
    for source in sorted(TESTS.glob("*.gd")):
        target = destination / source.name
        target.write_text(source.read_text().replace("res://tools/tests/", prefix))
        hashes[source.name] = {"source_sha256": sha(source), "executed_sha256": sha(target)}
    return hashes


def gpu_inventory() -> list[dict]:
    command = ["nvidia-smi", "--query-gpu=index,uuid,name,pci.bus_id,driver_version", "--format=csv,noheader,nounits"]
    result = subprocess.run(command, capture_output=True, text=True, timeout=10, check=True)
    return [dict(zip(("index", "uuid", "name", "pci_bus_id", "driver"), [item.strip() for item in row]))
            for row in csv.reader(result.stdout.splitlines())]


def parse_gpu_xml(text: str) -> list[dict]:
    root = ET.fromstring(text)
    rows = []
    for gpu in root.findall("gpu"):
        rows.append({"uuid": gpu.findtext("uuid"), "name": gpu.findtext("product_name"),
                     "memory_used": gpu.findtext("fb_memory_usage/used"),
                     "utilization": gpu.findtext("utilization/gpu_util"),
                     "processes": [{"pid": int(p.findtext("pid", "0")), "type": p.findtext("type"),
                                    "name": p.findtext("process_name"), "memory": p.findtext("used_memory")}
                                   for p in gpu.findall("processes/process_info")]})
    return rows


def process_group_members(group: int) -> set[int]:
    """Return live members; exited children awaiting reaping own no workload."""
    members = set()
    for entry in Path("/proc").iterdir():
        if not entry.name.isdigit():
            continue
        try:
            # comm can contain spaces and parentheses; fields after its final
            # ')' begin at state (field 3), so pgrp (field 5) is index 2.
            fields = (entry / "stat").read_text().rsplit(")", 1)[1].split()
            if int(fields[2]) == group and fields[0] not in ("Z", "X"):
                members.add(int(entry.name))
        except (OSError, ValueError, IndexError):
            pass  # Processes can finish between /proc enumeration and read.
    return members


def sample_gpu(group: int) -> dict:
    owners = process_group_members(group)
    owners.add(group)
    result = subprocess.run(["nvidia-smi", "-q", "-x"], capture_output=True, text=True, timeout=10, check=True)
    gpus = parse_gpu_xml(result.stdout)
    for gpu in gpus:
        gpu["owned_processes"] = [p for p in gpu["processes"] if p["pid"] in owners]
    rss = {}
    for pid in owners:
        try:
            text = Path(f"/proc/{pid}/status").read_text()
            match = re.search(r"^VmRSS:\s+(\d+)\s+kB$", text, re.M)
            rss[str(pid)] = int(match[1]) if match else None
        except OSError:
            rss[str(pid)] = None
    return {"unix": time.time(), "process_group": group, "members": sorted(owners), "host_rss_kib_by_pid": rss, "gpus": gpus}


def classify_errors(text: str, allow_refresh: bool) -> tuple[list[str], list[str]]:
    errors, diagnostics = [], []
    for line in text.splitlines():
        if not ERROR.search(line):
            continue
        if allow_refresh and line == REFRESH_DIAGNOSTIC:
            diagnostics.append(line)
        else:
            errors.append(line)
    return errors, diagnostics


def stop_process_group(process: subprocess.Popen) -> None:
    try:
        os.killpg(process.pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
    deadline = time.monotonic() + 5
    while process.poll() is None or process_group_members(process.pid):
        if time.monotonic() >= deadline:
            break
        time.sleep(0.05)
    # A child can ignore TERM even after its parent exits. Never leave a
    # timed-out fixture's descendant workload running behind a failed report.
    if process.poll() is None or process_group_members(process.pid):
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    process.wait(timeout=5)
    deadline = time.monotonic() + 5
    while process_group_members(process.pid) and time.monotonic() < deadline:
        time.sleep(0.05)


def supervise(command: list[str], env: dict, cwd: Path, output: Path, timeout: float,
              gpu_uuid: str, allow_refresh: bool, monitor=sample_gpu) -> dict:
    began = time.monotonic()
    stopped = ""
    gpu_seen, wrong_gpu, telemetry_errors = set(), set(), []
    next_sample = began
    parent_exit_at = None
    descendants_seen = set()
    cleanup_forced = False
    with (output / "run.log").open("w") as stream, (output / "gpu.jsonl").open("w") as telemetry:
        process = subprocess.Popen(command, cwd=cwd, env=env, stdout=stream, stderr=subprocess.STDOUT, start_new_session=True)
        print(json.dumps({"event": "started", "pid": process.pid, "output": str(output)}), flush=True)
        try:
            while True:
                now = time.monotonic()
                if now - began > timeout:
                    stopped = "wall-time limit exceeded (including teardown)"
                    break
                if process.poll() is not None:
                    if parent_exit_at is None:
                        parent_exit_at = now
                    descendants = process_group_members(process.pid)
                    descendants_seen.update(descendants)
                    if not descendants:
                        break
                    if now - parent_exit_at >= DESCENDANT_EXIT_GRACE:
                        stopped = "live process-group descendants outlasted the clean-exit grace period"
                        break
                errors, _ = classify_errors((output / "run.log").read_text(errors="replace"), allow_refresh)
                if errors:
                    stopped = "runtime error"
                    break
                if now >= next_sample:
                    next_sample = now + 2
                    try:
                        sample = monitor(process.pid)
                        telemetry.write(json.dumps(sample) + "\n"); telemetry.flush()
                        for gpu in sample["gpus"]:
                            if gpu["owned_processes"]:
                                gpu_seen.add(gpu["uuid"])
                                if gpu["uuid"] != gpu_uuid:
                                    wrong_gpu.add(gpu["uuid"])
                        if wrong_gpu:
                            stopped = "qualification process used an unrequested physical GPU"
                            break
                    except (OSError, subprocess.SubprocessError, ET.ParseError) as error:
                        telemetry_errors.append(str(error))
                        stopped = "GPU telemetry failed"
                        break
                time.sleep(0.1)
        except KeyboardInterrupt:
            stopped = "interrupted"
        finally:
            if process.poll() is None or process_group_members(process.pid):
                cleanup_forced = True
                stop_process_group(process)
    remaining = sorted(process_group_members(process.pid))
    errors, diagnostics = classify_errors((output / "run.log").read_text(errors="replace"), allow_refresh)
    return {"exit_code": process.returncode, "pid": process.pid, "wall_seconds": time.monotonic() - began,
            "stopped": stopped, "errors": errors, "allowed_diagnostics": diagnostics,
            "gpu_uuids_observed": sorted(gpu_seen), "wrong_gpu_uuids": sorted(wrong_gpu),
            "physical_gpu_confirmed": gpu_uuid in gpu_seen and not wrong_gpu,
            "telemetry_errors": telemetry_errors,
            "process_group_clean": not remaining,
            "teardown": {"descendant_grace_seconds": DESCENDANT_EXIT_GRACE,
                         "after_parent_exit_seconds": time.monotonic() - parent_exit_at if parent_exit_at is not None else 0,
                         "descendants_observed_after_parent_exit": sorted(descendants_seen),
                         "forced_cleanup": cleanup_forced, "live_members_after_cleanup": remaining}}


def load_report(path: Path, problems: list[str]) -> dict:
    try:
        value = json.loads(path.read_text())
        if not isinstance(value, dict):
            raise ValueError("report root is not an object")
        return value
    except (OSError, ValueError) as error:
        problems.append(f"Cannot read {path.name}: {error}")
        return {}


def sustained_rss_trend(report: dict, telemetry: Path, gpu_uuid: str) -> dict:
    """Match real GPU-owner RSS to each fixture's same-state cycle timestamp."""
    try:
        samples = [json.loads(line) for line in telemetry.read_text().splitlines() if line.strip()]
        cycles = report.get("cycles", [])
        if len(cycles) < 4 or not samples:
            raise ValueError("at least four complete cycles and host telemetry are required")
        rows = []
        for cycle in cycles:
            timestamp = float(cycle["memory"]["unix"])
            nearest = min(samples, key=lambda sample: abs(sample["unix"] - timestamp))
            distance = abs(nearest["unix"] - timestamp)
            if distance > 3:
                raise ValueError("same-state sample is more than three seconds from host telemetry")
            owners = {str(p["pid"]) for gpu in nearest["gpus"] if gpu["uuid"] == gpu_uuid for p in gpu["owned_processes"]}
            rss = nearest.get("host_rss_kib_by_pid", {})
            if not owners or any(rss.get(pid) is None for pid in owners):
                raise ValueError("actual GPU-owner RSS is unavailable at a same-state sample")
            values = {pid: rss[pid] * 1024 for pid in sorted(owners)}
            rows.append({"cycle": cycle["cycle"], "fixture_unix": timestamp, "sample_unix": nearest["unix"],
                         "distance_seconds": distance, "bytes_by_pid": values, "bytes": sum(values.values())})
        warm = rows[1:]
        if any(row["bytes_by_pid"].keys() != warm[0]["bytes_by_pid"].keys() for row in warm):
            raise ValueError("GPU-owner process set changed between same-state samples")
        baseline, final = warm[0]["bytes"], warm[-1]["bytes"]
        budget = max(128 * 1024 * 1024, baseline * 0.25)
        growth = final - baseline
        return {"available": True, "passed": growth <= budget, "baseline_bytes": baseline, "final_bytes": final,
                "growth_bytes": growth, "budget_bytes": budget, "slope_bytes_per_cycle": growth / (len(warm) - 1),
                "samples": rows, "scope": "RSS of the same actual GPU-owning process set; shared/resident pages, not private allocation accounting"}
    except (OSError, ValueError, KeyError, TypeError) as error:
        return {"available": False, "passed": False, "reason": str(error)}


def measured_summary(value: dict, minimum: int) -> bool:
    return (isinstance(value, dict) and isinstance(value.get("n"), int) and value["n"] >= minimum
            and all(isinstance(value.get(key), (int, float)) and math.isfinite(value[key]) and value[key] > 0 for key in ("median", "p95"))
            and value["p95"] >= value["median"])


def validate_reports(suite: str, report: dict, runtime: dict, driver: str, require_sdk: bool, render_thread: str = "project") -> list[str]:
    problems = []
    if report.get("failures") != [] or not isinstance(report.get("checks"), int) or report.get("checks", 0) <= 0:
        problems.append("Fixture did not report positive checks and an empty failures list")
    if not runtime.get("passed") or runtime.get("profile") != PROFILE or not runtime.get("pt_supported"):
        problems.append("Runtime did not confirm PT hardware and all mandated test settings")
    if runtime.get("driver") != driver or runtime.get("method") != "forward_plus" or runtime.get("display") == "headless":
        problems.append("Runtime renderer does not match the requested hardware backend")
    threads = runtime.get("render_thread", {})
    expected_separate = threads.get("project_model") == 2 if render_thread == "project" else render_thread == "separate"
    thread_ids = (threads.get("main_id"), threads.get("render_id"))
    if (threads.get("requested") != render_thread or threads.get("project_model") not in (0, 1, 2)
            or not all(isinstance(value, int) and value > 0 for value in thread_ids)
            or (thread_ids[0] != thread_ids[1]) != expected_separate or not threads.get("passed")):
        problems.append("Runtime did not confirm the requested render-thread model with actual callback thread IDs")
    if require_sdk and not (runtime.get("fsr", {}).get("api") and runtime.get("fsr", {}).get("sr3")):
        problems.append("Explicit SDK qualification is unsupported on this runtime")
    if suite == "sustained":
        cycles = report.get("requested_cycles", 0)
        if report.get("status") != "passed" or cycles < 4 or report.get("completed_cycles") != cycles:
            problems.append("Sustained campaign did not complete every requested cycle")
        if len(report.get("saves", [])) != cycles or any(not row.get("pt_active_after_load") for row in report.get("saves", [])):
            problems.append("Sustained campaign did not complete each generated save/load")
        if require_sdk and (not report.get("require_sdk") or not report.get("sdk_readiness")):
            problems.append("Sustained campaign is missing its required SDK phases")
    if suite in ("resolution", "resolution_performance") and require_sdk:
        readiness = report.get("sdk_readiness", [])
        if not readiness or any(not row.get("ready") for row in readiness):
            problems.append("SDK-labeled resolution data lacks completed readiness gates")
    if suite == "resolution_performance":
        rows = report.get("runs", [])
        expected = {(quality, reference, round_index) for quality in (0, 1) for reference in (False, True) for round_index in (0, 1)}
        actual = {(row.get("quality"), row.get("window_reference"), row.get("round")) for row in rows}
        if len(rows) != 8 or actual != expected:
            problems.append("Resolution benchmark did not collect all eight distinct alternating blocks")
        for index, row in enumerate(rows):
            summaries = [(row.get(key, {}), 120) for key in ("frame_ms", "main_gpu_ms")]
            summaries += [(row.get(key, {}), 110) for key in ("rt_gpu_ms", "controller_cpu_ms")]
            summaries += [(row.get("gpu_stages_ms", {}).get(key, {}), 110) for key in ("rays", "reconstruction", "copies")]
            if not all(measured_summary(value, minimum) for value, minimum in summaries):
                problems.append(f"Benchmark block {index} has missing, incomplete or invalid GPU/CPU/frame samples")
            if require_sdk and row.get("upscale_evaluations", 0) < 110:
                problems.append(f"Benchmark block {index} has insufficient actual SDK evaluations")
    if suite == "fsr" and len(report.get("rows", [])) != 7:
        problems.append("FSR/FG fixture did not complete all seven production presentation phases")
    if suite == "lifecycle":
        required = {"pipeline_failure", "image", "filter_set", "ray_set", "sampler", "frame_upload_render",
                    "history_copy_render", "pose_upload_render", "resize_render"}
        if not required.issubset(report.get("metrics", {})):
            problems.append("Lifecycle fixture omitted a required allocation/dispatch failure scenario")
        lifetime = report.get("metrics", {}).get("dispatch_lifetime", {})
        if (lifetime.get("events") != ["build", "render", "dispose"]
                or not all(lifetime.get(key) is True for key in ("built", "rendered", "disposed", "images_freed"))
                or lifetime.get("separate_thread") is not expected_separate
                or lifetime.get("render_thread") != thread_ids[1]
                or (expected_separate and lifetime.get("retained_before_execution") is not True)):
            problems.append("Lifecycle fixture did not prove ordered retained dispatch, image release and the actual expected render thread")
    if suite == "controller":
        required = {"camera recenter", "replacement retry", "rapid camera recenter"}
        if not required.issubset({row.get("case") for row in report.get("runs", [])}) or len(report.get("retry_delays", [])) != 8:
            problems.append("Controller fixture did not complete all three handoffs and bounded retry probes")
    if suite == "detached_live" and (len(report.get("observations", [])) != 4 or any(row.get("traced_pixels", 0) <= 20 for row in report.get("observations", []))):
        problems.append("Detached live fixture did not observe all four real moving mesh phases")
    return problems


def immutable_inputs(executable: Path, data: Path) -> dict:
    files = [executable]
    pack = executable.with_suffix(".pck")
    if not pack.is_file():
        raise ValueError("An exported executable with its sibling .pck is required")
    files.append(pack)
    files.extend(sorted(path for path in executable.parent.rglob("*")
                        if path.is_file() and (path.name.lower().endswith((".dll", ".so")) or ".so." in path.name.lower())))
    return {"files": {str(path): {"sha256": sha(path), "bytes": path.stat().st_size} for path in files if path.is_file()},
            "data": {"path": str(data), "inventory_kind": "recursive path/size/mtime; original data contents are not rehashed",
                     "files": [{"name": str(p.relative_to(data)), "bytes": p.stat().st_size, "mtime_ns": p.stat().st_mtime_ns}
                               for p in sorted(data.rglob("*")) if p.is_file()]}}


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--executable", type=Path, required=True)
    p.add_argument("--render-thread", choices=("project", "safe", "separate"), default="project",
                   help="Use the exported project's thread model by default; overrides are diagnostic coverage")
    p.add_argument("--data-root", type=Path, required=True)
    p.add_argument("--profile-root", type=Path, required=True, help="New directory; existing directories are rejected")
    p.add_argument("--output", type=Path, required=True, help="New evidence directory")
    p.add_argument("--driver", choices=("vulkan", "d3d12"), required=True)
    p.add_argument("--display", required=True, help="Dedicated X11 display, for example :97")
    p.add_argument("--xauthority", type=Path, required=True)
    p.add_argument("--physical-gpu", type=int, default=1, help="nvidia-smi physical GPU index; verified by process UUID evidence")
    p.add_argument("--engine-gpu-index", type=int, default=1, help="Godot adapter enumeration index; independent of physical index")
    p.add_argument("--suite", action="append", choices=sorted(set(REPORTS) | set(GROUPS)), help="Repeatable; default core")
    p.add_argument("--require-sdk", action="store_true", help="Fail without DX12 FSR 3.1; also enables sustained SDK phases")
    p.add_argument("--timeout", type=float, default=480, help="Per ordinary suite, including process teardown")
    p.add_argument("--stress-timeout", type=float, default=1200)
    p.add_argument("--total-timeout", type=float, default=7200)
    p.add_argument("--stress-cycles", type=int, default=6)
    p.add_argument("--stress-seconds", type=float, default=3)
    p.add_argument("--benchmark-resolution", default="1280x720")
    p.add_argument("--allow-virtual-refresh-diagnostic", action="store_true", help="Retain the one exact X11 refresh-rate diagnostic as an explicit allowed diagnostic")
    p.add_argument("--wine", type=Path, help="Explicit wine64 binary for a Windows bundle")
    p.add_argument("--wine-prefix-template", type=Path, help="Dedicated prepared prefix; copied into the new isolated profile")
    p.add_argument("--wine-user", help="User directory inside the prepared Wine prefix")
    p.add_argument("--env", action="append", default=[], metavar="KEY=VALUE", help="Explicit runtime environment, e.g. WINESERVER or LD_LIBRARY_PATH; cannot override isolation")
    return p


def main(argv=None) -> int:
    args = parser().parse_args(argv)
    output = None
    plan = None
    lock = None
    try:
        if sys.platform != "linux":
            raise ValueError("This runner requires a Linux host; Wine covers the Windows DX12 build")
        executable = args.executable.expanduser().resolve(strict=True)
        data = args.data_root.expanduser().resolve(strict=True)
        authority = args.xauthority.expanduser().resolve(strict=True)
        if not executable.is_file() or not data.is_dir() or not authority.is_file():
            raise ValueError("Executable, data directory and Xauthority must exist")
        wine = args.wine is not None
        require_sdk = args.require_sdk or "sdk" in (args.suite or []) or "fsr" in (args.suite or [])
        if (args.driver == "d3d12") != wine:
            raise ValueError("DX12 requires explicit --wine, --wine-prefix-template and --wine-user; Vulkan uses the native build")
        if require_sdk and args.driver != "d3d12":
            raise ValueError("SDK qualification requires DX12; native FSR2 is covered by the ordinary resolution suite")
        if wine and (not args.wine_prefix_template or not args.wine_user or "/" in args.wine_user or args.wine_user in (".", "..")):
            raise ValueError("Wine requires an explicit prepared prefix template and user name")
        if min(args.timeout, args.stress_timeout, args.total_timeout) < 1 or not 4 <= args.stress_cycles <= 30 or not 1 <= args.stress_seconds <= 12:
            raise ValueError("Positive deadlines, 4–30 stress cycles and 1–12 phase seconds are required")
        if not re.fullmatch(r"[1-9]\d{2,4}x[1-9]\d{2,4}", args.benchmark_resolution):
            raise ValueError("Benchmark resolution must be positive WIDTHxHEIGHT, at least 100 each")
        if args.profile_root.resolve() == args.output.resolve():
            raise ValueError("Profile and evidence directories must be distinct")
        suites = expand_suites(args.suite or ["core"])
        explicit_env = {}
        for item in args.env:
            key, separator, value = item.partition("=")
            if not separator or not re.fullmatch(r"[A-Z_][A-Z_0-9]*", key) or key in PROTECTED_ENV:
                raise ValueError("Invalid or protected --env key: " + key)
            explicit_env[key] = value
        inventory = gpu_inventory()
        gpu = next((row for row in inventory if int(row["index"]) == args.physical_gpu), None)
        if gpu is None:
            raise ValueError("Requested physical GPU is absent from nvidia-smi")
        # An advisory lock prevents overlapping runs of this qualification
        # workflow. External workload inventory remains in the GPU evidence.
        lock = open(Path("/tmp") / ("ei-pt-qualification-" + gpu["uuid"] + ".lock"), "a")
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        before = immutable_inputs(executable, data)
        output = reserve_directory(args.output, "evidence")
        profile = reserve_directory(args.profile_root, "profile")
        fixture_dir = output / "fixtures"
        fixture_hashes = freeze_fixtures(fixture_dir, wine)
        env = dict(os.environ, **explicit_env, DISPLAY=args.display, XAUTHORITY=str(authority))
        env.pop("WAYLAND_DISPLAY", None)
        prefix = None
        if wine:
            args.wine = args.wine.resolve(strict=True)
            template = args.wine_prefix_template.resolve(strict=True)
            prefix = profile / "wine-prefix"
            # Reflinks retain immutable DLL/cache inputs cheaply when supported.
            subprocess.run(["cp", "-a", "--reflink=auto", str(template), str(prefix)], check=True, timeout=300)
            user = prefix / "drive_c/users" / args.wine_user / "AppData/Roaming/Godot/app_userdata/Cursed Lands"
            if prefix not in user.resolve().parents:
                raise ValueError("Prepared Wine user data resolves outside the isolated prefix")
            if user.exists():
                shutil.rmtree(user)  # Only the newly copied test prefix.
            env.update(WINEPREFIX=str(prefix), WINEARCH="win64", WINEDEBUG=explicit_env.get("WINEDEBUG", "-all"))
        wine_hashes = {}
        if wine:
            wine_hashes[str(args.wine)] = sha(args.wine)
            for name in ("d3d12.dll", "d3d12core.dll", "dxgi.dll", "d3d11.dll", "nvapi64.dll", "zlib1.dll"):
                library = prefix / "drive_c/windows/system32" / name
                if library.is_file():
                    wine_hashes[name] = sha(library)
        source_state = subprocess.run(["git", "status", "--porcelain"], cwd=ROOT, capture_output=True, text=True, check=True).stdout
        commit = subprocess.run(["git", "rev-parse", "HEAD"], cwd=ROOT, capture_output=True, text=True, check=True).stdout.strip()
        plan = {"schema": 1, "status": "running", "passed": False, "started_unix": time.time(),
                "repository_commit": commit, "repository_status": source_state, "suites_requested": suites,
                "runner": {"path": str(RUNNER_PATH), "sha256": RUNNER_SHA256},
                "require_sdk": require_sdk, "render_thread": args.render_thread, "inputs": before, "fixture_hashes": fixture_hashes,
                "profile": str(profile), "mandated_settings": PROFILE, "display": args.display,
                "xauthority": str(authority), "physical_gpu": gpu, "engine_gpu_index": args.engine_gpu_index,
                "gpu_inventory": inventory, "runtime_environment": explicit_env,
                "wine": {"binary": str(args.wine), "prefix_template": str(args.wine_prefix_template), "user": args.wine_user,
                         "runtime_sha256": wine_hashes} if wine else None,
                "limits": {"suite_seconds": args.timeout, "stress_seconds": args.stress_timeout, "total_seconds": args.total_timeout},
                "runs": [], "not_run": [], "failures": [],
                "scope": "NVIDIA GPU on Linux X11; native Vulkan or Windows DX12 through explicit Wine. GPU allocations are engine counters; nvidia-smi adds driver residency evidence. This does not certify other hardware, native Windows, or a complete campaign playthrough."}
        write_json(output / "qualification.json", plan)
        began = time.monotonic()
        for index, suite in enumerate(suites):
            remaining = args.total_timeout - (time.monotonic() - began)
            if remaining <= 0:
                plan["failures"].append("Total campaign wall-time limit exceeded")
                plan["not_run"] = suites[index:]
                break
            directory = output / suite; directory.mkdir()
            suite_profile = profile / suite; suite_profile.mkdir()
            suite_env = dict(env)
            if wine:
                suite_env.setdefault("DXVK_LOG_PATH", str(directory))
                suite_env.setdefault("VKD3D_SHADER_CACHE_PATH", str(suite_profile / "cache"))
            for name in ("DATA", "CONFIG", "CACHE"):
                suite_env[f"XDG_{name}_HOME"] = str(suite_profile / name.lower())
            if not wine:
                user = suite_profile / "data/godot/app_userdata/Cursed Lands"
            user.mkdir(parents=True, exist_ok=False)
            (user / "settings.cfg").write_text(settings("1280x720"))
            thread_args = [] if args.render_thread == "project" else ["--render-thread", args.render_thread]
            command = ([str(args.wine)] if wine else []) + [str(executable)] + thread_args + ["--audio-driver", "Dummy",
                       "--gpu-index", str(args.engine_gpu_index), "--rendering-method", "forward_plus", "--rendering-driver", args.driver,
                       "--windowed", "--borderless", "--resolution", "1280x720", "--",
                       "--ei-path=" + host_path(data, wine), "--no-movies", "--mod-tests",
                       "--tool=" + host_path(fixture_dir / "path_trace_qualification.gd", wine),
                       "--qualification-fixture=" + host_path(fixture_dir / FIXTURES.get(suite, "path_trace_" + suite + ".gd"), wine),
                       "--qualification-render-thread=" + args.render_thread,
                       "--audit-out=" + host_path(directory, wine)]
            if require_sdk:
                command.append("--qualification-require-sdk")
            if suite == "sustained":
                command += ["--pt-stress-cycles=" + str(args.stress_cycles), "--pt-stress-seconds=" + str(args.stress_seconds),
                            "--pt-stress-timeout=" + str(max(1, min(args.stress_timeout, remaining) - 20))]
            if suite == "resolution_performance":
                command += ["--pt-bench-resolution=" + args.benchmark_resolution, "--ei-profile-rt"]
            deadline = min(args.stress_timeout if suite == "sustained" else args.timeout, remaining)
            write_json(directory / "command.json", {"argv": command, "cwd": str(executable.parent), "profile": str(user), "timeout": deadline})
            result = supervise(command, suite_env, executable.parent, directory, deadline, gpu["uuid"],
                               args.allow_virtual_refresh_diagnostic and not wine)
            problems = []
            raw = load_report(directory / REPORTS[suite], problems)
            runtime = load_report(directory / "qualification-runtime.json", problems)
            problems += validate_reports(suite, raw, runtime, args.driver, require_sdk, args.render_thread)
            if suite == "sustained":
                result["host_rss_trend"] = sustained_rss_trend(raw, directory / "gpu.jsonl", gpu["uuid"])
                if not result["host_rss_trend"]["passed"]:
                    problems.append("Same-state host RSS trend is unavailable or exceeds the explicit warmed-cache budget")
            if runtime.get("adapter") != gpu["name"]:
                problems.append("Runtime adapter name differs from the requested physical GPU")
            expected_user = host_path(user, wine).replace("/", "\\").lower() if wine else str(user)
            actual_user = str(runtime.get("user_data", ""))
            # Wine reports C:\\users rather than the host's Z: mapping.
            if wine:
                expected_user = "c:\\" + str(user.relative_to(prefix / "drive_c")).replace("/", "\\").lower()
                actual_user = actual_user.replace("/", "\\").lower()
            if actual_user != expected_user:
                problems.append("Runtime user-data directory differs from the isolated test profile")
            result.update(suite=suite, checks=raw.get("checks"), fixture_failures=raw.get("failures"), validation_errors=problems,
                          runtime=runtime, report=REPORTS[suite])
            result["passed"] = (result["exit_code"] == 0 and not result["stopped"] and not result["errors"]
                                and result["physical_gpu_confirmed"] and result["process_group_clean"]
                                and not result["teardown"]["forced_cleanup"] and not result["telemetry_errors"] and not problems)
            if wine:
                shutil.move(str(user), str(suite_profile / "user-data"))
            result["artifacts"] = {str(path.relative_to(directory)): sha(path) for path in sorted(directory.rglob("*")) if path.is_file()}
            write_json(directory / "run.json", result)
            plan["runs"].append(result)
            write_json(output / "qualification.json", plan)
            print(json.dumps({"suite": suite, "passed": result["passed"], "checks": result["checks"], "seconds": result["wall_seconds"],
                              "errors": result["errors"] + problems, "stopped": result["stopped"]}), flush=True)
            if not result["passed"]:
                plan["failures"].append("Suite failed: " + suite)
                plan["not_run"] = suites[index + 1:]
                break
        after = immutable_inputs(executable, data)
        plan["inputs_unchanged"] = before == after
        if before != after:
            plan["failures"].append("Executable, pack, runtime libraries or data inventory changed during qualification")
        plan["wall_seconds"] = time.monotonic() - began
        plan["passed"] = not plan["failures"] and not plan["not_run"] and len(plan["runs"]) == len(suites)
        plan["status"] = "passed" if plan["passed"] else "failed"
        write_json(output / "qualification.json", plan)
        return 0 if plan["passed"] else 1
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        if output:
            write_json(output / "runner-failure.json", {"passed": False, "error": str(error)})
            if plan:
                plan["status"] = "failed"
                plan["passed"] = False
                plan["failures"].append("Runner failed: " + str(error))
                completed = {row["suite"] for row in plan["runs"]}
                plan["not_run"] = [name for name in plan["suites_requested"] if name not in completed]
                write_json(output / "qualification.json", plan)
        print("PT qualification failed: " + str(error), file=sys.stderr)
        return 1
    finally:
        if lock:
            lock.close()


if __name__ == "__main__":
    raise SystemExit(main())
