# E2 investigation and fixes — 2026-10-26

Changes originated on canonical `main` at `d4765c56` and were integrated with
`cf214d30`, including the newer NRD, PT water, DLSS RR, RTXDI and transmission
work. No release or remote update was made. The original recordings and report remain
in `/home/llm2x/Documents/EI/Evidence/e2/`; hashes are in `inputs.json`.

**The mountain flashes remain unresolved.** A live follow-up reproduced a
5.05-second PT compilation stall and verified a fix for that cause. The exact
two events in the supplied Windows/FG recording have no per-frame trace, so
their attribution remains an inference rather than a confirmed match.

## Implemented changes

| Area | Verified failure and change | Regression |
| --- | --- | --- |
| Knife attack after casting/hit | A finished one-shot could leave the hero in a neutral animation mask. The next dagger attack then selected the generic bow fallback. Explicit new attacks now resolve their combat posture before selecting a clip, on both authority and replica. Locked casts still keep their queued posture. | `attack_after_action`: 25 checks, 6 failures before, 0 after; real hero, stone dagger/bronze, targeted/direct attacks and replicated clips. |
| High-resolution hint and book | The card enlarged glyphs rasterized at its old size; hidden/reopened cards also retained a stale scale after resizing. Glyph sampling now follows the displayed scale and is refreshed after resize/reopen. The book uses a private DPI SVG texture, centered icon alignment and symmetric physical padding. HUD font sampling inherits the same policy. | `high_resolution_ui`: 108 checks, 48 failures on the original pack, 0 on the final pack. 1920×1080, 2560×1440, 3840×2160 × EN/RU/DE; actual glyph-cache scale, visible glyphs, clipping, button pixels and guide opening. |
| PT loading camera race | Moving a camera more than 32 m while its initial snapshot was pending canceled the preparation owner without reopening it, because the settings request was already marked seen. Retiring that snapshot now retains the explicit preparation request and requires the replacement's render acknowledgment. | `path_trace_loading_recenter`: original run 11 checks / 5 failures; fixed 14 / 0. A real scene and NRD output are required before completion. This demonstrates the race; it does not prove that it caused the recording's exact 18-second delay. |
| PT scene reconstruction | Each replacement scene recreated immutable reconstruction and SHaRC compute shaders and pipelines. These now share the controller's program cache; images, buffers, descriptor sets and mutable history remain private to their scene. | `path_trace_recenter_programs`: Windows DX12 12 checks / 6 failures before, 12 / 0 after; also passes with the Linux production render-thread model. Six shader/pipeline handles stay identical across a real scene replacement. |
| Spell illumination | Visible casting and selected impact/status particles now emit bounded local light. Healing adds a blue-violet light around its body sparks. One source per carrier/type avoids recast stacking, and a 24-light pool bounds allocation. Lights follow actual particle position/alpha, respect hidden actors and the existing lighting option, and disappear when their particles expire. | `spell_effect_lighting`: original pack 130 checks / 57 failures; fixed 134 / 0. `path_trace_healing_glow`: 8 checks / 3 failures before, 8 / 0 after. |

Campaign lightning now also prepares its actual position/color/UV vertex layout,
instead of a generic quad with normals/tangents. The registered
`lightning_pipeline_warmup` test fails 1 of 26 checks before the fix and passes
26/26 after it. It checks native and script builders, ordinary/demon bolts,
weather/spell/wall parameters, visible pixels and absence of first-draw pipeline
compilation. Related vegetation preparation passes 124/124.

PT now prepares both emission states for the selected depth/cache mode before
acknowledging its first rendered frame. This includes the existing non-SHaRC
fallback; scene replacements share the immutable programs. The registered
`path_trace_emitter_sharc` test fails 3 of 14 checks before the fix and passes
14/14 after it. Ordinary PT, deeper SHaRC and Windows DX12 each pass 14/14 too.
The real campaign receivers must brighten and return to baseline, and moving
or expiring emission must compile no programs during play.

The high-resolution requirement is recorded in both workspace and repository
`AGENTS.md`. No player-visible strings or options were added; existing EN/RU/DE
strings are retained. Translation checking reports 0 errors.

## Spell audit

All 42 installed spell prototypes were exercised through their real casting,
impact and status dispatchers on two real actors. The conventional gallery
passes 42 capture checks; the PT gallery passes 85 checks, including actual PT
readiness and discovery of each casting source. Both sets of 84 views were
visually reviewed. The audit intentionally uses a dark cave to expose light
spill; it is not a normal gameplay brightness preset.

LiA’s separate installed database was also audited: 134 checks, zero failures.
Its 42 spell codes and complete illumination audit are identical to the base
campaign’s. Both campaigns use the same visually reviewed dispatchers.

Healing is restrained blue-violet (peak energy 0.85, 3.2 m range); casting lights
have peak energy at most 0.45 and a 2.5 m range; persistent status glows are
smaller/dimmer. Particle alpha supplies their fade. The added sources participate
in the existing conventional shadow budget and the shared PT light list. They do
not add halos or fog volumes. Native missile, elemental impact, wall and original
spell-light trajectories remain intact.

Non-emissive smoke, invisible transformations, and UI modifier glyphs deliberately
do not create outcome lights. The script-only campfire damage prototype has no
standalone visual dispatcher; authored TORCH particles/lights supply its existing
world presentation. `spell-audit.json` records every prototype, including these
intentional exceptions.

The dedicated PT healing case occupies the previous seven-light capacity first,
then creates actual healing particles. Their first displayed PT frame adds blue
illumination before the geometry poll, and expiry removes both the source and
its old lighting history. The original warm fire remains visible before/after.

## Original comparison

The base game ran under the registered Wine 11.20 toolchain with an isolated,
locked writable prefix and copied save. Native UI inputs cast healing and then
attacked a living wolf with a dagger. The retained screenshots show the healing
pose/particles and the subsequent dagger strike and damage. No console state
mutation was used. This checks the original third-person behavior; the original
game has no corresponding remake first-person presentation.

The original animation resolver at `0x5301b0` was inspected using REA/Ghidra,
against executable SHA-256
`d0fc0bb2acf45f0e59fae89e55c16a59848ffa89fb68feee9f298a680b660ad8`.
Evidence ID:
`ev_4bdfa2fe8a17d59e87ad5f968f8e52f2863a0d32d63963f48431cb3b430538f4`.
The source ADB mask selection and the native dagger-after-heal behavior support
the posture fix. The REA snapshot is retained with the original screenshots.

The pre-existing independently executed x86 healing-light oracle also passes:
11 checks, 68 native ticks compared. Native RGB, range, motion and lifetime are
unchanged; the body-particle illumination is an explicitly requested remake
addition. The original executable does not implement Godot font oversampling,
DPI SVGs, PT, NRD or SHaRC; original Wine comparisons of those mechanisms are
inapplicable. Their visual expectations and limits are recorded here instead.
The lightning change prepares an existing renderer resource layout; it does not
alter native bolt geometry or trajectories. The original fixed-function renderer
has no corresponding Godot first-draw pipeline to compare under Wine.

## Remaining investigation

### Mountain flashes

The supplied first recording was reviewed around 3:25 and across 3:20–3:52;
the native-frame audit below corrects an omission in the initial sampling.
Linux PT/SHaRC sweeps and a Windows DX12/DLSS Performance/PT/SHaRC camera
sweep in LiA `gz2h` did not reproduce the reported black flashes. The Windows
probe saved 240 frames at 1920×1080, with 960×540 internal raster and 480×270 PT.
Streamline confirmed successful DLSS evaluations and error 0. These viewport
readbacks are visual evidence, not a performance benchmark.

The recording uses an RTX 4090 Laptop with native NVIDIA frame generation. This
workstation has RTX 3090/3090 Ti adapters and reports that native FG is
unsupported. That path has therefore not been reproduced. The user was asked
whether the flash also occurs with FG off; no answer had arrived during these
checks. No speculative terrain/shading change was made.

Initial follow-up inspection resampled 202–212 s to 60 FPS, with motion-
compensated darkening checks over 195–232 s and enlarged cliff-face crops.
A later native-cadence audit found that the constant-FPS conversion can omit
source frames despite the clip’s nominal 60 FPS rate; that initial pass must
not be described as inspecting every recorded frame.
These did not isolate a mountain-wide black frame. A further LiA sweep advanced
real weather and world simulation instead of freezing them; its 180 captures
also did not show the reported flash. The indicated cliff/ridge is still being
clarified. These negative observations do not establish that the symptom is absent.

The corrected pass decoded all **2,214 native frames** from 195 s to the end
without frame-rate conversion. In this interval, `fps=60` omitted 389 native
frame occurrences and added 390 repeats (by decoded frame-hash multiset). All
30 strongest spatial darkening candidates were reviewed as consecutive-frame
triplets; none conclusively identifies the mountain flash. Most are foreground
weapon/foliage or camera motion. `runs/frame-cadence/` retains hashes, the full
scan and its limitations; two representative sheets are retained with the visuals.
The scan ranks brief darkening events; its thresholds, reduced resolution and
three-frame comparison cannot exclude smaller or longer-lived shading changes.
See `runs/frame-cadence/README.md` for reproduction and `completion-audit.json`
for the remaining requirement gaps.

### Large stutters

Freeze detection confirms pauses at 130.799–132.937 s and 141.270–143.316 s in the
second video. The report records a 5,258.711 ms foreground maximum at app uptime
264.794 s, with a substantial rise in resources/memory over that reporting
interval. The video start offset approximately aligns the first event with that
interval; it is not a per-frame profiler trace.

The original 1.30.0 Windows build was tested over the report's `gz1g` camera
corridor with DX12, DLSS Performance, PT and SHaRC. Across 600 measured presented
frames and three scene generations, its maximum was 65.067 ms. Simulation was
frozen for this controlled traversal and native FG was unavailable. This does
not reproduce a combat/script-dependent or native-FG-dependent stall.

The isolated reconstruction test observed maximum frame times of 80.038 ms
before and 81.899 ms after the program-cache change, on automatically assigned
GPUs. It verifies removal of redundant shader/pipeline creation, **not** a proven
frame-time improvement or a fix for the reported multi-second stalls. Attributing
those exact recording events still requires the failing runtime path or a more
detailed trace.

The subsequent live-world route exposed a different, confirmed problem. Even
with the newly added spell glows disabled, the first two emissive triangles
caused PT program count to rise from 3 to 5 during a **5,051.912 ms** frame; a
later replacement raised it to 6 during a **3,241.986 ms** frame. Draw-pipeline
count did not change at those events and simulation/controller work remained
short. The corrected route saw emissive geometry for 64 frames, kept program
count at 6 throughout, and had no corresponding ray-program stalls. Its worst
frame was 1,725.525 ms, associated with a separate first raster draw. Both runs
used the same diagnostic harness and automatically selected the RTX 3090 Ti.

That early harness moved the camera before deferred material preparation had
finished, so it is unsuitable for qualifying normal first-use raster behavior.
A corrected harness waits for actual preparation and then runs 1,800 live
frames: maximum 127.177 ms after the fix. Its before-fix comparison peaked at
1,136.113 ms. Neither of these two runs admitted emissive triangles, so their
timings are **not evidence for the emissive-variant improvement**. The registered
14-check regression supplies the deterministic before/after reproduction; the
first diagnostic pair supplies live-game corroboration. No flawless frame-pacing
or native-Windows-FG performance claim is made.

First preparation now does the selected PT/cache variant work up front; a cold
load can take longer. No unselected depth mode or additional gameplay light is
enabled by this preparation. SHaRC fallback and real material-emission changes
are still exercised.

## Validation and evidence

Final related checks include `attack_path_current_target` (41),
`cast_posture_queue` (12), `equipment_animation_continuity` (56),
`creature_weapon_animations` (196), `healing_presentation` (22),
`local_shadow_fades` (726), and `contextual_tutorials` (496), all with 0 failures.
The regression-runner's 10 Python tests pass. Translation coverage passes.

`shader_compilation_scene` passes 62 checks. Its fixture now observes preparation
ownership independently of visible progress: the accepted 500 ms display delay
means fast cached changes correctly have no drawn cover. Cancellation is bounded
by 16 actual presented frames and the existing 90-second pipeline deadline;
a cold raster draw may itself exceed the previous five-second polling timeout.
Separate-thread captures wait for actual covered pixels instead of asserting
against the preceding swapchain image. These changes retain readiness,
ownership, pause, stale-acknowledgment, and actual visible-cover assertions.
The runner preserves each exported project's production render-thread model.

Before/final results and compressed full logs are in `runs/`, with runtime/pack
hashes in `runtime-hashes.json`. Failed fixture attempts are retained and are not
counted as passing validation. The final Linux production-thread suite exercises
loading, scene preparation, PT healing and cached reconstruction. Windows runs
use the shipping Safe model. All graphical runs used GPU Lab with automatic GPU
assignment; development profiles keep the cursor free, show FPS and mute audio.

Visual evidence is retained at
`/home/llm2x/Documents/EI/Evidence/e2/fixes-20261026/`:

- `ui/ui-4k-recording.mp4`: native 3840×2160 viewport recording, 162 captured frames
  over 28.261 seconds, preserving capture timing. It shows compact/expanded hints
  and the guide in EN/RU/DE. Capture readbacks affect FPS; it is a UI record,
  not a performance measurement.
- `ui/`: native 4K PNGs, centered book crops and the 108-check result.
- `spells/`: all 42 casting/effect pairs in conventional rendering and PT, plus
  six indexed contact sheets.
- `pt/`: actual healing illumination before, first frame, settled and expired.
- `original/`: native-game healing/dagger screenshots and the REA snapshot.
- `lia/`: reported-video reference frames and the Windows DLSS sweep contact.

Re-run registered checks with `tools/check_regressions.py` and installed campaign
data. PT cases require the qualified renderer template and adjacent exported PCK;
the stock editor does not supply that native RT backend. Native trajectories use
`tools/tests/healing_light_oracle.gd --fixture=<retained original x86 fixture>`.
Probe scripts are retained in `probes/` as investigation provenance; their
workspace-specific runtime paths are documented in the maintenance ledger.

Follow-up results are in `runs/followup/`: 155 assertions pass across the seven
focused PT/preparation cases, plus 26 lightning, 124 vegetation and 134 LiA
spell assertions. These overlap earlier checks and must not be summed as wholly
new coverage. The first Windows attempt failed DX12 device initialization and
fell back to Vulkan; it is retained but not counted as DX12 validation. A retry
initialized `d3d12` and passed. The emitter fixture now waits for actual snapshot
replacement after a material change, since the bounded topology scan may need
more than its previous two-frame head start. Before-fix evidence with that same
corrected fixture still fails exactly the three runtime-compilation assertions.
The follow-up Python runner checks pass 10/10 and translation coverage has 0 errors.

`accepted-checks.json` deduplicates the latest accepted evidence: **2,390
assertions across 23 registered cases, zero failures**. It combines the focused
runs above; it is not a claim that every case was rerun on one final pack.

Cleanup and retained-size details are recorded in
`/home/llm2x/Documents/EI/local/maintenance/e2-2026-10-26.md`.

## Local main integration

The local main integration at `cf214d30` preserves all E2 fixes and the newer
rendering features. PT emitter preparation includes the selected RTXDI mode,
and SHaRC fallback preserves that mode. The additional registered
`path_trace_emitter_deep_sharc_rtxdi` regression passes 15/15; its negative
control fails exactly the three runtime-compilation assertions.

The integration run passed **369 assertions across 11 Vulkan/DX12 runs**,
including PT loading, healing, recentering, lifecycle, directional NRD, water,
RTXDI and transmission. Before committing these changes, all 2,648 recorded
source files and the complete tracked working patch matched that executed
run. The 13 Python camera/runner tests and translation coverage were rerun
successfully. The game source did not require another change or GPU rerun.

`runs/main-integration/` retains the source manifest, results and compressed
logs. These checks overlap the earlier E2 aggregate and are not added to it.
The mountain-flash and exact-recording attribution gaps remain open.
