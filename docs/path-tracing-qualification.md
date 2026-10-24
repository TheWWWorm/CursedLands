# Path-tracing qualification

`tools/tests/run_path_trace_qualification.py` runs the committed PT fixtures
against an explicit exported executable and its sibling `.pck`. It supports a
Linux NVIDIA host with native Vulkan or a prepared Wine environment for the
Windows DX12 export. It does not build, change renderer defaults, download
dependencies, start Xorg, or publish anything.

Use a frozen export built from the intended source revision. The runner records
the executable, pack and recursively discovered bundle runtime-library SHA-256
hashes, its own source hash, repository revision/dirty state, and both source
and executed fixture hashes. External
fixtures are copied into the evidence directory; their `res://tools/tests/`
references are rewritten to that immutable copy. Original data gets a recursive
path/size/mtime inventory, not a full content hash. Keep the original installation
and the export unchanged throughout the run.

The runner preserves the exported project's render-thread model by default:
this branch uses a separate render thread on Linux and Safe rendering on
Windows. The wrapper records actual main-thread and render-callback thread IDs
and requires them to match the selected model. `--render-thread safe` and
`--render-thread separate` are explicit diagnostic overrides; neither replaces
qualification of production defaults. The choice is retained in the manifest
and each command.

## Hardware and virtual display

`--suite motion_quality` covers responsive spatial reconstruction, daylight and
torch history, a 4K Ingos camera/travel/topology route, three rounds of the actual
tactical/third-person/first-person cameras, snow footfalls, and resource failure
handling. The route advances daylight and records every movement frame; both the
fixture and runner reject inactive PT. `snow_tracks` measures receiver coverage
before/after real footprints; it does not require exact ray geometry for their
dynamic depressions. Individual suite names are `spatial`, `camera_routes`,
`camera_modes`, `snow_tracks`, `light_history` and `lifecycle`.

Run `--suite spatial_performance` separately in a GPU Lab **heavy** job. It
alternates filtering off/on/on/off at 4K, with 40 warm-up and 120 measured frames
per block. It is excluded from `full`, since ordinary shared visual jobs are not
valid performance comparisons. See the
[motion and snow validation](integrations/path-tracing-motion-and-snow-2026-10-24.md)
for captures, limits and the measured cost.

On the development workstation, submit graphical runs through GPU Lab. Each
job receives an isolated virtual display; up to three ordinary jobs can share
each GPU when load and free memory permit. This qualification runner additionally
locks its selected GPU against other runs of the same runner; schedule those
serially if GPU Lab assigns them to the same device.
Leave the submission's GPU choice omitted or `auto`; pin a card only for an
explicit device-specific comparison. Do not start
another Xorg/Xvfb, change the desktop, or override the service's display or GPU
environment. Use `--inherit-display`; the runner preserves those variables and
defaults to Godot's logical adapter **0** inside the job. The expected physical
UUID comes from the service's inherited `CUDA_VISIBLE_DEVICES` and is checked
against actual GPU process telemetry. Native launches use
`--display-driver x11 --audio-driver Dummy`. GPU Lab's private `/tmp` is separate
from the caller's, so keep inputs, profiles and evidence in project/home paths.
See `/opt/gpu-lab/README.md` for service commands.

Other hosts can use an already prepared accelerated X11 display by supplying
`--display` and `--xauthority` instead. A software Xvfb display is not a PT
qualification target. The GPU must support the patched engine's ray-tracing API.

`--physical-gpu 1` selects the physical index reported by `nvidia-smi`.
`--physical-gpu-uuid GPU-...` selects an exact UUID instead. In ordinary GPU Lab
runs omit both selectors and verify the scheduler-assigned UUID automatically;
device isolation can renumber NVML indices.
`--engine-gpu-index` selects Godot's enumeration index; these are separate
namespaces and may differ on another machine. The runner checks the actual
runtime adapter name, renderer and supported PT API, then observes the launched
process group's graphics-process UUID in `nvidia-smi`. Using another GPU, missing
UUID evidence, or failing GPU telemetry fails the run. A three-second interval
before each fixture gives even short topology tests an observable GPU context;
this interval is outside fixture measurements.

An advisory UUID lock serializes this runner's GPU jobs. Other applications are
listed in `gpu.jsonl`; stop competing workloads before interpreting benchmark
times. The monitor samples every two seconds and records per-process host RSS,
GPU allocations and utilization. Host RSS can include shared pages, and the
renderer's allocation counters are not total driver residency.

## Native Vulkan

All paths below are placeholders to replace with absolute local paths. The
profile and output directories must not exist, even after a previous test run.

```sh
gpu-lab submit --cwd /absolute/repository --timeout 7200 -- \
  python3 /absolute/repository/tools/tests/run_path_trace_qualification.py \
  --executable /builds/pt-linux/CursedLands.x86_64 \
  --data-root /data/EvilIslands \
  --profile-root /evidence/pt-vulkan-profile-01 \
  --output /evidence/pt-vulkan-01 \
  --driver vulkan --inherit-display \
  --suite full
```

Some NVIDIA virtual screens cannot report their refresh rate. Only on those
screens, add `--allow-virtual-refresh-diagnostic`. This retains the exact
`ERROR: An error occurred while trying to get the screen refresh rate.` line
under `allowed_diagnostics`. GPU Lab can instead report `Parameter "monitors"
is null` because its screen has no active RandR monitor; this is allowed only
when the immediately following engine call site is `screen_get_refresh_rate`
in `platform/linuxbsd/x11/display_server_x11.cpp`, which returns the same refresh
fallback. Missing context or another API remains a failure. Neither allowance
makes a failing process pass. Vsync is disabled in the isolated test settings.

## Windows DX12 and the actual FSR SDK

The Wine prefix template must already contain the qualified DX12/VKD3D and
NVAPI runtime. Supply the matching Wine binary, wineserver and libraries
explicitly. The runner copies this template into its new profile directory,
clears only the copied game profile, and uses a fresh game profile per suite.
It never moves or changes the template's saved settings. A template whose game
profile resolves outside the copied prefix is rejected. Wine paths require the
usual `Z:` mapping to the host filesystem.

```sh
gpu-lab submit --cwd /absolute/repository --timeout 7200 -- \
  python3 /absolute/repository/tools/tests/run_path_trace_qualification.py \
  --executable /builds/pt-windows/CursedLands.exe \
  --data-root /data/EvilIslands \
  --profile-root /evidence/pt-dx12-profile-01 \
  --output /evidence/pt-dx12-01 \
  --driver d3d12 --inherit-display \
  --wine /opt/qualified-wine/lib/wine/wine64 \
  --wine-prefix-template /opt/qualified-wine/pt-prefix \
  --wine-user tester \
  --env WINESERVER=/opt/qualified-wine/lib/wine/wineserver64 \
  --env LD_LIBRARY_PATH=/opt/qualified-wine/lib/x86_64-linux-gnu \
  --env 'WINEDLLOVERRIDES=winemenubuilder.exe=d;mscoree,mshtml=;dinput8=d;winedbg.exe=d;d3d12,d3d12core,dxgi,d3d11,nvapi64=n' \
  --env DXVK_ENABLE_NVAPI=1 --env DXVK_LOG_LEVEL=warn \
  --env DXVK_NVAPI_LOG_LEVEL=warn --env VKD3D_DEBUG=warn \
  --suite full --suite sdk --require-sdk
```

The `sdk` group and the `fsr` suite imply `--require-sdk`; an unsupported SDK
fails immediately. Resolution and sustained SDK phases wait at most 180 seconds
for the correct FSR 3.1 provider and viewport mode, matching applied scale, no
initialization state, no SDK error, and at least three new successful upscale
evaluations. Measurement rows retain before/after status and evaluation deltas.
Selected settings or smaller render buffers alone do not qualify as SDK use.
The FSR/FG fixture additionally requires actual generated and presented frames
through its seven production gameplay/resize/pause phases.

The test leaves the SDK active through ordinary game teardown. The runner's
wall deadline includes that teardown; completed measurements followed by a
hang are a failed run. Do not disable the SDK to turn such a failure into a pass.
After the launched process exits, live processes remaining in its process group
get at most five seconds to finish within the same wall deadline. Forced cleanup
or surviving live descendants fails qualification; already exited zombies own
no workload. Cleanup targets only the group created for that suite.

## Suites and deadlines

`--suite` is repeatable. Groups expand in order with duplicates removed.

| Selection | Coverage |
| --- | --- |
| `core` (default) | Device transport, rigid motion/disocclusion, lifecycle failures and resizing, topology, controller handoff/recovery, real detached geometry, applied resolution, sustained live campaign |
| `preparation` | Localized progress/input ownership, live material/temporal/SDK work, arena warmup, PT/RT/water settings, graphics detection cancellation and sampling; see [graphics preparation](graphics-preparation.md) |
| `full` | Core plus variance, quality, glossy paths, sampling, contacts, foliage, terrain, surface maps/detail, emitters, lighting/history, daylight, outdoor/cave, receivers, underwater and live water-reflection ownership |
| `sdk` | Resolution, production FSR/FG, sustained live SDK transitions; requires DX12 FSR 3.1 |
| `benchmark` | Eight alternating old/new PT resolution blocks with image comparisons and GPU/CPU timings |
| Individual name | Any fixture listed by `--help`; for example `--suite lifecycle --suite controller` |

The default per-suite deadline is 480 seconds; sustained stress gets 1200
seconds, and the aggregate limit is 7200 seconds. Override these explicitly
with `--timeout`, `--stress-timeout`, and `--total-timeout` when expanding
coverage. Stress has its own slightly shorter wall deadline so it can flush a
failure report before the runner terminates the process group. The runner stops
at the first failure, lists every remaining suite under `not_run`, and exits
nonzero. Requested unsupported suites are failures, not skips.

For a repeatable 1440p comparison, run `--suite benchmark
--benchmark-resolution 2560x1440` separately on each backend. Add
`--require-sdk` for actual DX12 SDK measurements. Native Vulkan explicitly
uses the engine's FSR 2 path. Performance reports require all eight blocks;
all frame, RT, ray, reconstruction, copy and controller sample summaries must
also be complete, finite and positive. The runner supplies `--ei-profile-rt`
to enable stage timestamps. There is no universal FPS pass threshold across GPUs. Compare their recorded
workload, image error, RT GPU timings and wall times on the same hardware.

Historical reference-pack experiments are excluded from the groups because
they require additional pinned reference inputs. Native Windows, Radeon/FSR 4,
other drivers and a full campaign playthrough remain separate qualification
targets; Wine coverage does not certify them.

## Sustained live coverage and memory

`path_trace_sustained.gd` extends the live campaign stability fixture and keeps
ordinary actors and simulation running. Each of six default cycles exercises:

1. Four-bounce High PT at half raster resolution; two-bounce Medium with
   progressive accumulation at 67%; and Low temporal PT (FSR 2, or explicit
   FSR 3.1 Performance when SDK coverage is requested).
2. Ordinary reachable hero movement with its following camera and visible
   actor instance updates, then transitions through scene RT, Off and restored
   PT. Weak references must confirm that retired device owners disappear after
   outstanding render-thread work drains.
3. A second campaign zone, a newly generated save with the production
   asynchronous thumbnail, the ordinary save-load API, restored active PT, and
   return to the starting zone at native Low settings. SDK runs also require
   fresh successful evaluations after the load.

The report requires every requested cycle and save roundtrip. `--stress-cycles`
accepts 4–30; `--stress-seconds` accepts 1–12 per hold, with three seconds as
the default. Hero movement uses twice that interval. Tests require actual
movement greater than 0.25 metres, rather than animation seeks or hidden actors.

Each transition must publish lighting and guide textures at the expected actual
render size. A timed hold requires the full requested interval of uninterrupted
ready output and at least 12 rendered frames. Ordinary topology replacements
reset that interval and may recover within 30 additional seconds; persistent
fallback or repeated rebuilds fail. A rendered frame receives at most 100 ms of
time credit, so a long compile or driver stall cannot satisfy the hold. Reports
also record notifications that arrive before the rendered-frame counter advances;
these earn no time or frame credit and do not interrupt otherwise valid output.
The hard wall deadline still applies while no new frames arrive. Reports
retain expected, reported and published dimensions; active and fallback frame
coverage; recovery resets and duration; and bounded state-change snapshots.
After hero movement the fixture allows at most 30 seconds to settle before
capturing a device-retirement reference. Same-state memory samples also require
a complete ready interval. Actors keep simulating during every wait, and the
retirement, SDK readiness and memory budgets remain mandatory.

Same-state memory samples begin after complete warm cycles. Cycle two is the
baseline; the final sample is compared with it. Available CPU allocation growth
has a budget of max(128 MiB, 25%); each GPU allocation counter uses max(256 MiB,
25%). Object/resource/node growth budgets are max(2000/400/100 respectively,
5%). The report includes values, slope and budgets, so these coarse leak guards
are not mistaken for proof of zero leaks. Missing release-template counters are
explicitly marked unavailable and are not treated as zero. At least one
allocation/object counter must be observable, and every device-retirement check
must still pass. Host RSS and GPU process residency remain available in the
separate runner telemetry. The runner matches each same-state timestamp to the
nearest telemetry sample within three seconds and compares cycle two with the
last cycle for the same actual GPU-owning process set. Host RSS growth must stay
within max(128 MiB, 25%). Missing matching RSS, a changed process set, or a budget
overrun fails the sustained run. Per-cycle values and matching time distances
are retained under `host_rss_trend` in `run.json`.

## Evidence and failure gates

The aggregate `qualification.json` contains the plan, source/build fingerprints,
hardware, limits, all run results and unexecuted suites. Each suite has its exact
`command.json`, `run.log`, `gpu.jsonl`, `qualification-runtime.json`, fixture
JSON, and generated captures. `run.json` records artifact hashes, exit code,
elapsed time, diagnostic classification, actual GPU evidence and report gates.
The live fixture flushes progress and the last phase before risky transitions,
so a crash or timeout retains useful context. Test saves remain in the isolated
profile for reproduction.

A pass requires a clean process exit within the deadline, no unallowed engine
or assertion errors, correct physical GPU/backend, correct isolated user-data
directory, all five mandated cursor/FPS/audio settings, positive fixture checks,
an empty failures list, and the suite's completion markers. Lifecycle reports
must contain their allocation/dispatch failure probes and ordered retained-owner
build/render/disposal evidence on the actual configured thread; controller reports must
contain all three handoffs and all eight retry probes; detached geometry must hit
real traced pixels during all four movement phases. Partial JSON written before
a crash does not pass. Input executable/pack/library hashes and the original
data inventory must remain unchanged.

Run the runner's CPU-only negative controls without a GPU or Godot:

```sh
python3 -m unittest discover -s tools/tests -p test_path_trace_qualification.py -v
```

These exercise service display/GPU environment preservation, logical adapter
selection after NVML renumbering, profile preservation, exact diagnostic allowance, graphics UUID
parsing, wrong-GPU and missing-GPU evidence, runtime errors, wall-time teardown
limits, surviving descendants after a zero-exit launcher, nested runtime-library
mutation, incomplete benchmark/SDK/stress reports, and an end-to-end fake-export
failure with manifest and `not_run` verification.
