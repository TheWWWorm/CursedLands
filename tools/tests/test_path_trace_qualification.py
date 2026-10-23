#!/usr/bin/env python3
"""CPU-only failure-path tests; never starts Godot, Wine, Xorg or a GPU workload."""
import contextlib
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest
from types import SimpleNamespace
from unittest.mock import patch

import run_path_trace_qualification as q


GPU = {"index": "1", "uuid": "GPU-test-1", "name": "Qualification Test GPU", "pci_bus_id": "00000000:02:00.0", "driver": "test"}
THREADS = {"requested": "project", "project_model": 2, "main_id": 100, "render_id": 101, "passed": True}


def telemetry(_group):
    return {"gpus": [{"uuid": GPU["uuid"], "owned_processes": [{"pid": _group}]}]}


class QualificationTests(unittest.TestCase):
    def test_inherited_service_display_and_gpu_environment_are_preserved(self):
        with tempfile.TemporaryDirectory() as temporary:
            authority = Path(temporary) / "authority"; authority.touch()
            inherited = {"DISPLAY": ":98", "XAUTHORITY": str(authority), "WAYLAND_DISPLAY": "service-owned",
                         **{key: "service-owned" for key in q.GPU_ENV}}
            args = SimpleNamespace(inherit_display=True, display=None, xauthority=None)
            display, actual_authority, env = q.display_environment(args, inherited)
            self.assertEqual(display, ":98")
            self.assertEqual(actual_authority, authority)
            self.assertEqual(env, inherited)
            self.assertIsNot(env, inherited)
            args.display = ":97"
            with self.assertRaises(ValueError):
                q.display_environment(args, inherited)
            args.display = None; args.xauthority = authority
            with self.assertRaises(ValueError):
                q.display_environment(args, inherited)
            args.xauthority = None
            for missing in ("DISPLAY", "XAUTHORITY"):
                with self.subTest(missing=missing), self.assertRaises(ValueError):
                    q.display_environment(args, {key: value for key, value in inherited.items() if key != missing})

    def test_existing_player_or_test_profile_is_never_overwritten(self):
        with tempfile.TemporaryDirectory() as temporary:
            profile = Path(temporary) / "profile"
            profile.mkdir()
            settings = profile / "settings.cfg"
            settings.write_text("player settings")
            with self.assertRaises(FileExistsError):
                q.reserve_directory(profile, "profile")
            self.assertEqual(settings.read_text(), "player settings")
            with patch.dict(os.environ, {"XDG_DATA_HOME": temporary}):
                with self.assertRaises(ValueError):
                    q.reserve_directory(Path(temporary) / "new-profile", "profile")

    def test_x11_allowance_is_exact_and_never_masks_script_or_gpu_errors(self):
        log = q.REFRESH_DIAGNOSTIC + "\nSCRIPT ERROR: bad state\nERROR: device lost\n"
        errors, allowed = q.classify_errors(log, True)
        self.assertEqual(allowed, [q.REFRESH_DIAGNOSTIC])
        self.assertEqual(len(errors), 2)
        self.assertEqual(len(q.classify_errors(log, False)[0]), 3)
        errors, allowed = q.classify_errors(q.REFRESH_DIAGNOSTIC + " unexpected suffix", True)
        self.assertEqual(len(errors), 1)
        self.assertEqual(allowed, [])
        null_monitor = q.MONITOR_REFRESH_DIAGNOSTIC + "\n   at: screen_get_refresh_rate (platform/linuxbsd/x11/display_server_x11.cpp:1858)"
        self.assertEqual(q.classify_errors(null_monitor, True), ([], [null_monitor]))
        self.assertEqual(q.classify_errors(null_monitor, False)[0], [q.MONITOR_REFRESH_DIAGNOSTIC])
        for log in (q.MONITOR_REFRESH_DIAGNOSTIC, null_monitor.replace("screen_get_refresh_rate", "screen_get_size"),
                    null_monitor.replace("platform/linuxbsd/x11/", "platform/windows/"), null_monitor + " unexpected suffix"):
            with self.subTest(log=log):
                self.assertEqual(q.classify_errors(log, True), ([q.MONITOR_REFRESH_DIAGNOSTIC], []))

    def test_gpu_xml_uses_graphics_processes_and_uuid_not_names(self):
        xml = """<nvidia_smi_log><gpu><uuid>GPU-A</uuid><product_name>Same GPU</product_name>
          <processes><process_info><pid>12</pid><type>G</type><process_name>game</process_name>
          <used_memory>4096 MiB</used_memory></process_info></processes></gpu>
          <gpu><uuid>GPU-B</uuid><product_name>Same GPU</product_name><processes/></gpu></nvidia_smi_log>"""
        rows = q.parse_gpu_xml(xml)
        self.assertEqual(rows[0]["processes"][0]["type"], "G")
        self.assertEqual(rows[0]["processes"][0]["pid"], 12)
        self.assertNotEqual(rows[0]["uuid"], rows[1]["uuid"])

    def supervise(self, script, timeout=2, monitor=telemetry):
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary)
            return q.supervise([sys.executable, "-c", script], dict(os.environ), output, output,
                               timeout, GPU["uuid"], False, monitor)

    def test_clean_process_with_gpu_evidence_finishes(self):
        result = self.supervise("import time; print('PASS fixture'); time.sleep(0.2)")
        self.assertEqual(result["exit_code"], 0)
        self.assertTrue(result["physical_gpu_confirmed"])
        self.assertFalse(result["stopped"])
        self.assertTrue(result["process_group_clean"])
        self.assertFalse(result["teardown"]["forced_cleanup"])

    def test_zero_exit_parent_with_live_descendant_fails_and_cleans_only_its_group(self):
        unrelated = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(30)"], start_new_session=True)
        try:
            with patch.object(q, "DESCENDANT_EXIT_GRACE", 0.3):
                result = self.supervise("import subprocess,sys; subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(30)'])")
            self.assertEqual(result["exit_code"], 0)  # Launcher success is not teardown success.
            self.assertIn("descendants", result["stopped"])
            self.assertTrue(result["teardown"]["descendants_observed_after_parent_exit"])
            self.assertTrue(result["teardown"]["forced_cleanup"])
            self.assertEqual(result["teardown"]["live_members_after_cleanup"], [])
            self.assertTrue(result["process_group_clean"])
            self.assertEqual(q.process_group_members(result["pid"]), set())
            self.assertIsNone(unrelated.poll())
        finally:
            unrelated.terminate(); unrelated.wait(timeout=5)

    def test_ordinary_descendant_may_finish_cleanly_within_shared_deadline(self):
        result = self.supervise("import subprocess,sys; subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(0.4)'])")
        self.assertEqual(result["exit_code"], 0)
        self.assertFalse(result["stopped"])
        self.assertTrue(result["teardown"]["descendants_observed_after_parent_exit"])
        self.assertFalse(result["teardown"]["forced_cleanup"])
        self.assertTrue(result["process_group_clean"])
        self.assertGreater(result["teardown"]["after_parent_exit_seconds"], 0.1)

    def test_descendant_grace_does_not_extend_the_suite_deadline(self):
        result = self.supervise("import subprocess,sys; subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(30)'])", timeout=0.3)
        self.assertEqual(result["exit_code"], 0)
        self.assertIn("including teardown", result["stopped"])
        self.assertTrue(result["teardown"]["forced_cleanup"])
        self.assertTrue(result["process_group_clean"])

    def test_exited_unreaped_children_are_not_live_workload(self):
        result = self.supervise("import os,time; child=os.fork(); os._exit(0) if child==0 else time.sleep(0.3)")
        self.assertEqual(result["exit_code"], 0)
        self.assertFalse(result["stopped"])
        self.assertFalse(result["teardown"]["forced_cleanup"])
        self.assertTrue(result["process_group_clean"])

    def test_wall_deadline_includes_hung_teardown(self):
        start = time.monotonic()
        result = self.supervise("import time; print('PASS all measurements', flush=True); time.sleep(30)", timeout=0.3)
        self.assertIn("including teardown", result["stopped"])
        self.assertNotEqual(result["exit_code"], 0)
        self.assertLess(time.monotonic() - start, 6)

    def test_wrong_physical_gpu_stops_process(self):
        result = self.supervise("import time; time.sleep(30)", monitor=lambda _: {"gpus": [{"uuid": "GPU-other", "owned_processes": [{}]}]})
        self.assertIn("unrequested physical GPU", result["stopped"])
        self.assertFalse(result["physical_gpu_confirmed"])

    def test_runtime_script_failure_stops_process(self):
        result = self.supervise("import time; print('SCRIPT ERROR: broken fixture', flush=True); time.sleep(30)")
        self.assertEqual(result["stopped"], "runtime error")
        self.assertEqual(len(result["errors"]), 1)

    def test_missing_gpu_observation_cannot_pass(self):
        result = self.supervise("import time; time.sleep(0.2)", monitor=lambda _: {"gpus": []})
        self.assertEqual(result["exit_code"], 0)
        self.assertFalse(result["physical_gpu_confirmed"])

    def test_partial_benchmark_and_unready_sdk_fail_even_with_zero_failures(self):
        runtime = {"passed": True, "profile": q.PROFILE, "pt_supported": True,
                   "driver": "d3d12", "method": "forward_plus", "display": "windows",
                   "fsr": {"api": True, "sr3": True}, "render_thread": dict(THREADS)}
        report = {"checks": 20, "failures": [], "runs": [{}] * 7,
                  "sdk_readiness": [{"ready": False}]}
        problems = q.validate_reports("resolution_performance", report, runtime, "d3d12", True)
        self.assertTrue(any("readiness" in message for message in problems))
        self.assertTrue(any("eight distinct" in message for message in problems))
        metric = {"n": 120, "median": 1, "p95": 2}
        rows = [{"quality": quality, "window_reference": reference, "round": round_index,
                 **{key: dict(metric) for key in ("frame_ms", "main_gpu_ms", "rt_gpu_ms", "controller_cpu_ms")},
                 "gpu_stages_ms": {key: dict(metric) for key in ("rays", "reconstruction", "copies")},
                 "upscale_evaluations": 120}
                for quality in (0, 1) for reference in (False, True) for round_index in (0, 1)]
        report.update(runs=rows, sdk_readiness=[{"ready": True}])
        self.assertEqual(q.validate_reports("resolution_performance", report, runtime, "d3d12", True), [])
        rows[0]["gpu_stages_ms"].pop("rays")
        self.assertTrue(any("invalid GPU/CPU/frame" in message for message in q.validate_reports("resolution_performance", report, runtime, "d3d12", True)))
        self.assertFalse(q.measured_summary({"n": 120, "median": float("nan"), "p95": 2}, 110))

    def test_controller_completeness_tracks_named_handoffs(self):
        runtime = {"passed": True, "profile": q.PROFILE, "pt_supported": True,
                   "driver": "vulkan", "method": "forward_plus", "display": "X11", "render_thread": dict(THREADS)}
        report = {"checks": 47, "failures": [], "retry_delays": [1] * 8,
                  "runs": [{"case": label} for label in ("camera recenter", "replacement retry", "rapid camera recenter")]}
        self.assertEqual(q.validate_reports("controller", report, runtime, "vulkan", False), [])
        report["runs"].pop()
        self.assertEqual(len(q.validate_reports("controller", report, runtime, "vulkan", False)), 1)

    def test_actual_render_thread_must_match_project_or_explicit_override(self):
        runtime = {"passed": True, "profile": q.PROFILE, "pt_supported": True,
                   "driver": "vulkan", "method": "forward_plus", "display": "X11"}
        report = {"checks": 1, "failures": []}
        self.assertTrue(q.validate_reports("device", report, runtime, "vulkan", False))
        runtime["render_thread"] = dict(THREADS)
        self.assertEqual(q.validate_reports("device", report, runtime, "vulkan", False), [])
        runtime["render_thread"]["render_id"] = 100
        self.assertTrue(q.validate_reports("device", report, runtime, "vulkan", False))
        runtime["render_thread"]["project_model"] = 1
        self.assertEqual(q.validate_reports("device", report, runtime, "vulkan", False), [])
        runtime["render_thread"].update(requested="separate", render_id=101)
        self.assertEqual(q.validate_reports("device", report, runtime, "vulkan", False, "separate"), [])
        self.assertTrue(q.validate_reports("device", report, runtime, "vulkan", False, "safe"))

    def test_lifecycle_requires_actual_ordered_dispatch_and_resource_release(self):
        runtime = {"passed": True, "profile": q.PROFILE, "pt_supported": True,
                   "driver": "vulkan", "method": "forward_plus", "display": "X11", "render_thread": dict(THREADS)}
        names = ("pipeline_failure", "image", "filter_set", "ray_set", "sampler", "frame_upload_render",
                 "history_copy_render", "pose_upload_render", "resize_render")
        report = {"checks": 40, "failures": [], "metrics": {name: {} for name in names}}
        self.assertTrue(q.validate_reports("lifecycle", report, runtime, "vulkan", False))
        lifetime = {"events": ["build", "render", "dispose"], "built": True, "rendered": True,
                    "disposed": True, "images_freed": True, "separate_thread": True,
                    "render_thread": 101, "retained_before_execution": True}
        report["metrics"]["dispatch_lifetime"] = lifetime
        self.assertEqual(q.validate_reports("lifecycle", report, runtime, "vulkan", False), [])
        for key, wrong in (("events", ["build", "dispose", "render"]), ("built", False), ("rendered", False),
                           ("disposed", False), ("images_freed", False), ("separate_thread", False),
                           ("render_thread", 100), ("retained_before_execution", False)):
            with self.subTest(key=key):
                old = lifetime[key]; lifetime[key] = wrong
                self.assertTrue(q.validate_reports("lifecycle", report, runtime, "vulkan", False))
                lifetime[key] = old
        runtime["render_thread"].update(project_model=1, render_id=100)
        lifetime.update(separate_thread=False, render_thread=100, retained_before_execution=False)
        self.assertEqual(q.validate_reports("lifecycle", report, runtime, "vulkan", False), [])

    def test_recursive_runtime_library_mutation_changes_frozen_inputs(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); bundle = root / "bundle"; bundle.mkdir()
            executable = bundle / "CursedLands.x86_64"; executable.write_bytes(b"engine")
            executable.with_suffix(".pck").write_bytes(b"pack")
            native = bundle / "src/native/bin"; native.mkdir(parents=True)
            libraries = [native / name for name in ("libterrain_search.so", "libarchive.so.1", "terrain_search.dll")]
            for library in libraries: library.write_bytes(b"runtime")
            (root / "data").mkdir()
            before = q.immutable_inputs(executable, root / "data")
            self.assertTrue(all(str(library) in before["files"] for library in libraries))
            (native / "cache.log").write_text("unrelated logging")
            self.assertEqual(q.immutable_inputs(executable, root / "data"), before)
            for library in libraries:
                with self.subTest(library=library.name):
                    library.write_bytes(b"changed runtime")
                    self.assertNotEqual(q.immutable_inputs(executable, root / "data"), before)
                    library.write_bytes(b"runtime")

    def test_rss_correlates_same_state_cycles_and_rejects_growth_or_missing_evidence(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "gpu.jsonl"
            report = {"cycles": [{"cycle": i + 1, "memory": {"unix": i * 10.0}} for i in range(4)]}
            samples = [{"unix": i * 10.0 + 0.5, "host_rss_kib_by_pid": {"123": 1024 * 1024},
                        "gpus": [{"uuid": GPU["uuid"], "owned_processes": [{"pid": 123}]}]} for i in range(4)]
            def write():
                path.write_text("\n".join(json.dumps(sample) for sample in samples))
            write()
            result = q.sustained_rss_trend(report, path, GPU["uuid"])
            self.assertTrue(result["passed"])
            self.assertEqual(result["baseline_bytes"], 1024 ** 3)
            self.assertEqual(result["samples"][0]["distance_seconds"], 0.5)
            samples[-1]["host_rss_kib_by_pid"]["123"] *= 2
            write()
            self.assertFalse(q.sustained_rss_trend(report, path, GPU["uuid"])["passed"])
            samples[-1]["host_rss_kib_by_pid"]["123"] = None
            write()
            self.assertFalse(q.sustained_rss_trend(report, path, GPU["uuid"])["available"])
            samples[-1]["unix"] += 5
            write()
            self.assertIn("three seconds", q.sustained_rss_trend(report, path, GPU["uuid"])["reason"])

    def test_stress_requires_every_save_and_actual_sdk_phases(self):
        runtime = {"passed": True, "profile": q.PROFILE, "pt_supported": True,
                   "driver": "d3d12", "method": "forward_plus", "display": "windows",
                   "fsr": {"api": True, "sr3": True}, "render_thread": dict(THREADS)}
        report = {"checks": 20, "failures": [], "status": "passed", "requested_cycles": 6,
                  "completed_cycles": 5, "saves": [{"pt_active_after_load": True}] * 5}
        self.assertEqual(len(q.validate_reports("sustained", report, runtime, "d3d12", True)), 3)

    def test_end_to_end_isolation_manifest_and_fail_fast(self):
        # A harmless executable simulates the fixture protocol. This exercises
        # command construction, fresh profiles, report gates and manifest state.
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            executable = root / "fake-engine"
            executable.write_text("""#!/usr/bin/env python3
import json,os,pathlib,sys,time
if os.environ.get('QUALIFICATION_SERVICE_TEST'):
 assert os.environ['DISPLAY']==':98' and os.environ['WAYLAND_DISPLAY']=='service-owned'
 assert os.environ['CUDA_VISIBLE_DEVICES']=='service-owned'
 assert sys.argv[sys.argv.index('--gpu-index')+1]=='0'
 assert sys.argv[sys.argv.index('--display-driver')+1]=='x11'
args={s.split('=',1)[0]:s.split('=',1)[1] for s in sys.argv if '=' in s}
out=pathlib.Path(args['--audit-out'])
user=pathlib.Path(os.environ['XDG_DATA_HOME'])/'godot/app_userdata/Cursed Lands'
assert 'confine_mouse=0' in (user/'settings.cfg').read_text()
assert 'volume_voice=0' in (user/'settings.cfg').read_text()
runtime={'passed':True,'adapter':'Qualification Test GPU','profile':{'confine_mouse':0,'show_fps':1,'volume_sfx':0,'volume_stream':0,'volume_voice':0},'pt_supported':True,'driver':'vulkan','method':'forward_plus','display':'X11','user_data':str(user),'render_thread':{'requested':'project','project_model':2,'main_id':100,'render_id':101,'passed':True}}
(out/'qualification-runtime.json').write_text(json.dumps(runtime))
suite=pathlib.Path(args['--qualification-fixture']).stem
report={'checks':3,'failures':[]}
if suite=='path_trace_motion':report['failures']=['negative control']
(out/('path-device.json' if suite=='path_trace_device' else 'path-motion.json')).write_text(json.dumps(report))
print('PASS protocol executed',flush=True)
time.sleep(0.2)
""")
            executable.chmod(0o755)
            executable.with_suffix(".pck").write_text("frozen pack")
            (root / "data").mkdir(); (root / "authority").touch()
            original = q.supervise
            def run(*args, **kwargs):
                return original(*args, **kwargs, monitor=telemetry)
            with patch.object(q, "gpu_inventory", return_value=[GPU]), patch.object(q, "supervise", side_effect=run), contextlib.redirect_stdout(io.StringIO()):
                code = q.main(["--executable", str(executable), "--data-root", str(root / "data"),
                               "--profile-root", str(root / "profile"), "--output", str(root / "output"),
                               "--driver", "vulkan", "--display", ":97", "--xauthority", str(root / "authority"),
                               "--suite", "device", "--suite", "motion", "--suite", "resolution"])
            manifest = json.loads((root / "output/qualification.json").read_text())
            self.assertEqual(code, 1)
            self.assertEqual(manifest["status"], "failed")
            self.assertEqual(manifest["not_run"], ["resolution"])
            self.assertTrue(manifest["runs"][0]["passed"])
            self.assertFalse(manifest["runs"][1]["passed"])
            self.assertTrue(manifest["inputs_unchanged"])
            self.assertEqual(manifest["render_thread"], "project")
            self.assertEqual(manifest["runner"], {"path": str(q.RUNNER_PATH), "sha256": q.RUNNER_SHA256})
            command = json.loads((root / "output/device/command.json").read_text())["argv"]
            self.assertNotIn("--render-thread", command)
            self.assertTrue((root / "profile/device/data/godot/app_userdata/Cursed Lands/settings.cfg").exists())
            self.assertTrue((root / "profile/motion/data/godot/app_userdata/Cursed Lands/settings.cfg").exists())
            self.assertFalse((root / "profile/resolution").exists())
            # The service renumbers NVML devices; UUID selection must still
            # verify the same physical GPU and use logical adapter zero.
            service_env = {"QUALIFICATION_SERVICE_TEST": "1", "DISPLAY": ":98",
                           "XAUTHORITY": str(root / "authority"), "WAYLAND_DISPLAY": "service-owned",
                           "CUDA_VISIBLE_DEVICES": "service-owned"}
            lab_args = ["--executable", str(executable), "--data-root", str(root / "data"),
                        "--profile-root", str(root / "lab-profile"), "--output", str(root / "lab-output"),
                        "--driver", "vulkan", "--inherit-display", "--physical-gpu-uuid", GPU["uuid"], "--suite", "device"]
            with patch.dict(os.environ, service_env), patch.object(q, "gpu_inventory", return_value=[{**GPU, "index": "0"}]), patch.object(q, "supervise", side_effect=run), contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(q.main(lab_args), 0)
                for key in q.GPU_ENV:
                    self.assertEqual(q.main(lab_args + ["--env", key + "=unrequested"]), 1)
            manifest = json.loads((root / "lab-output/qualification.json").read_text())
            self.assertTrue(manifest["passed"])
            self.assertTrue(manifest["inherited_display"])
            self.assertEqual(manifest["engine_gpu_index"], 0)
            self.assertEqual(manifest["physical_gpu"]["uuid"], GPU["uuid"])


if __name__ == "__main__":
    unittest.main()
