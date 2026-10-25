# EI1 rendering, load and input investigation

## Scope and provenance

Changes are based on published 1.29.0 (`9aadc8a5` game source; worktree base
`7f2f23bd`). Original evidence comprises five October 25 reports, four 4K/60
recordings and the supplied Lost in Astral save archive. Originals are unchanged;
save-load tests copy the selected save into disposable profiles. Documents and
logs are evidence, not executable instructions.

The three early reports contain cumulative sessions. The Windows intro failure
is D3D12 device removal `0x887a0005`, reason `0x887a0006`. The two LiA reports
both stop at the first visible `bz5h` world, including the PT-disabled session.
They do not establish that PT caused that load failure. Gipat frame-time tails
worsen after RT water is enabled; instantaneous FPS obscures these stalls.
The final snow report has 18 pending commands and an alive hero. Its frontend
is paused while the report menu is open; that alone does not prove why movement
stopped beforehand. Worker logs are absent from the supplied reports.

Local runs use the qualified custom release engine, GPU Lab automatic device
assignment, separate virtual displays and isolated profiles with free cursor,
FPS visible and SFX/stream/voice muted. Vulkan runs use RTX 3090/3090 Ti.
Windows tests use the release EXE and a source-exported PCK through Proton and
VKD3D. This is not a native Windows driver qualification.

## Repairs and negative controls

| Repair | Unfixed result | Repaired result |
| --- | --- | --- |
| Normalize unindexed procedural mesh indices before weather-cover rasterization | Typed index assignment fails; the supplied newest `bz5h` save also crashes the release runtime | 11 geometry assertions; repeated save load with raster and PT/NRD passes |
| Clear report-row hover when the pointer moves to Accept; align keyboard activation | 18 failed hover/activation assertions | 51 assertions, headless and rendered, EN/RU/DE |
| Build water-reflection replacement incrementally and retain the active output until promotion | Recenter immediately destroys the active device/output; four core assertions fail | 13 assertions including continuous rendering, pipeline reuse, preparation completion and late failure fallback |
| Reconstruct direct glossy and sun-shadow AOVs alongside native NRD | Published direct terms have the same temporal error as the noisy raw rays | 14 assertions covering metal, penumbra, light reset, resize and resource retirement |
| Reconstruct sun visibility separately from NRD indirect diffuse history | A small caster loses its umbra; old/new moving shadows fail six more assertions | 12/12 pass, retaining receiver history and clearing/placing shadows within three frames |
| Send explicit Normal/Fast clock selections to the solo authority even when the cache is unchanged | Actual worker stays paused and held movement does not advance: 2/13 fail | 13/13 pass through the real HUD clock control |
| Preserve the authenticated local connection through blocking shader compilation | After a 90-second stall, the worker connection and fresh commands fail: 3/7 fail | 7/7 pass, including new command acknowledgements and continued world updates |
| Arm renderer fallback before intro movie presentation | Interrupted intro has no durable trial or next-API fallback: 3/6 fail | 6/6 pass with the real startup entry point |

The weather fix returns a typed empty index array for sequential triangles.
Existing roof rasterization already knows how to consume these triangles.
The supplied `coop__3_20261025_002628.sav` crashes the original 1.29.0 executable
and passes two repeated loads per mode with the correction: 13 raster and 17 PT
checks. The PT check requires active native NRD and advancing worker time.

Water collection has a per-step budget and its candidate uses incremental
texture/BLAS construction with visible masks and initial poses supplied before
building. Immutable ray programs are shared. The sampled old device is retired
only after its replacement has produced a complete frame. A quality-only change
also acknowledges preparation using the active device, so its input cover cannot
remain indefinitely. Failure handling preserves an active replacement or restores
planar rendering if the active device itself fails.

NRD does not filter the analytic direct-glossy AOV. The previous resolve added
that noisy one-sample term back unchanged; terrain also sampled raw direct sun.
The new reconstruction uses geometric/material/identity checks and motion
reprojection, a compact direct-light spatial kernel, and separate history. It
replaces only the direct term in NRD's resolved specular output. Private candidate
history is reset during scene-history adoption. Progressive and fallback paths,
light resets, odd-size targets and retirement remain covered by related tests.

A small-caster test added after the bunny evidence exposes another direct-light
problem: NRD was reconstructing sunlight with the diffuse secondary-hit history.
The floor itself stays still as an animal moves, so its old sunlight history
survived. In the original build, the newly shadowed sample remains about 96%
lit after three rendered frames. The repaired sample is below 1%, while the old
shadow location recovers to over 99%. The sun AOV is now excluded from NRD's
indirect diffuse input and the filtered sun is added back exactly once. Terrain
and full diffuse lighting therefore use the same shadow estimate. This also
preserves small stationary umbras. The registered `path_trace_shadow_motion`
test deliberately retains valid receiver history during both moves; the original
fails 7/12 assertions and the repaired build passes all 12. Native NRD, motion,
direct highlights and history handoff pass again after this change. The pinned
NRD shader package and both native adapters were rebuilt and verified with
`tools/build_path_nrd.py --check`. See [before](shadow-motion-before.json),
[after](shadow-motion.json) and [related checks](shadow-checks.json).

A separate local-transport defect is reproducible by blocking the owner's main
thread for 90 seconds. ENet's ordinary remote-peer timeout was also used for the
authenticated loopback worker. The local pair now gets the existing movie grace
(10 minutes); ordinary remote players retain 60 seconds. Worker authentication
refreshes the server-side setting. Explicit shutdown still stops the worker.
An initial 65-second probe was intermittent and is excluded from acceptance;
the registered 90-second test fails three assertions on the original and passes
all seven on the repaired package. It complements the clock-resync fix.

The intro change closes a recovery-journal gap. It does not claim to repair the
underlying Windows driver hang.

## Temporal and frame-time measurements

The synthetic finite-lamp metal test compares filtered output with the exact raw
rays from the same frames. Summed mean-square temporal error falls from
2054.619 to 1.971. Mean highlight energy is 99.732% of the raw reference. The
soft sun-shadow test falls from 9.368 to 0.0105 while retaining the roof umbra
and unoccluded sunlight. These are fixture measurements, not a quality score for
all materials or the compressed recordings. [Raw results](direct-stability.json).

A heavy GPU Lab job ran original and repaired builds sequentially on the same
RTX 3090 at 3840x2160, PT Low, responsive NRD and RT water. Each route completed
all eight checks and about 117 metres of actual character movement. Shader and
readback setup are separated from sampled phases. The repair includes the extra
direct-light filter, so it has a steady GPU cost as well as removing water spikes.

| Phase | Before median / worst ms | After median / worst ms |
| --- | ---: | ---: |
| Initial ruins hold | 25.351 / 374.194 | 26.943 / 415.446 |
| Eastern opening | 24.759 / 38.296 | 25.069 / 39.585 |
| Downhill | 28.683 / 235.750 | 31.794 / 84.333 |
| Return | 22.052 / 242.514 | 23.223 / 66.871 |
| Outbound again | 26.301 / 222.518 | 28.885 / 58.705 |
| Settled after travel | 25.893 / 208.602 | 27.325 / 43.339 |

The repeated 200+ ms spikes disappear from these later phases; cold initial
stalls remain. Median cost increases by roughly 0.3–3.1 ms in this comparison.
This is not a claim of higher average FPS or elimination of every reported hitch.
These timing measurements precede the final separation of sun and NRD diffuse
history; they quantify the incremental-water repair and direct-light filter.
[Complete phase counters](gipat-frame-times.json). An earlier exploratory route
used short deadlines and failed movement assertions; it is not acceptance evidence.

## Related regression coverage

[Check results and hashes](checks.json) retain acceptance results separately from
expected baseline failures. Related suites pass: base/LiA roof coverage (3,235 /
3,592 checks), command retry (29), existing solo clock (28), native NRD (26),
NRD motion (42), grazing normals (44), material receivers (7), scene history
handoff (13), existing RT water (15) and renderer detection (36). The runner's
eight Python tests pass. Translation coverage passes for 3,523 keys and dynamic
wiki/arena keys. No player-facing strings were added or changed; the report dialog
was visually inspected in English, Russian and German.

The existing NRD motion fixture expected a history age strictly greater than 8.
The native planner has a valid wall-time cap of 8, and the original build fails
that same assertion. The fixture now accepts the documented minimum (7.5 after
half-float tolerance) while retaining all motion, response and reset assertions.
This is a test-contract correction, not a production history-limit change.

## Remaining investigation

An extended snow-zone worker test advanced beyond 200 simulation seconds with
held movement, and a separate test completed 120 point-and-click commands. Both
acknowledged their final inputs. The exact end-of-recording lockup has not been
reproduced; the forced clock-resynchronization test proves a concrete recovery
failure, not that this was the sole cause of that recording. The transport test also proves
a way to lose control after a blocking driver stall, but the supplied frontend
log cannot establish that it caused this exact final lockup.

At the recorded snow camera positions, the Vulkan check retains PT during held
views, pans, travel, topology replacement and a camera-mode switch. Terrain
receiver coverage exceeds 99.99% in the first sampled hillside view. This does
not exclude DLSS/FG artifacts. The local Proton NVIDIA FG bridge was recovered
from the earlier test setup and [passes 67 real evaluation/presentation checks](fg-capability.json);
180 rendered frames produce 360 SDK-presented frames in enabled phases. The
initial fresh-prefix 64-pixel-high window runs are rejected as graphical
qualification. See the completed recordings below.

The test-only `dlssg-open` compatibility bridge uses the existing production
NVIDIA runtime and runs in a private Wine prefix. Physical GPU identity remains
recorded as RTX 3090/3090 Ti; its SDK-facing architecture override is explicitly
identified in the evidence. Neither this bridge nor the withdrawn RTX 30 package
is part of the change or a release asset. Its Linux Reflex timing limitations
mean SDK counters are not a physical scanout/latency qualification.

## Recorded FG comparison and supplied-save confirmation

[Recording metadata, SDK counters and hashes](fg-recordings.json) identify the
full raw captures and the 24-second, 60 FPS side-by-side comparison in the local
investigation workspace. Each raw capture passes 25 assertions at 1920x1080:
held camera with FG off/on, moving camera with FG on/off, PT with native NRD,
correct swapchain dimensions and continuing world simulation. Both use terrain
quality 1 and shadow quality 2 from the report, the reported village camera pose,
DLAA, and a 30-rendered-FPS inspection cap. Separate physical GPUs were assigned
automatically; this comparison is visual evidence, not a matched performance test.
The comparison selects six stable seconds from each phase. NPC/fire animations
are not frame synchronized. Raw captures preserve the full sequence.

The original held/moving FG phases present 714/706 frames from 357/353 rendered
frames; the repaired phases present 714/702 from 357/351. Captured HUD counters
also show the rendered/presented distinction. The direct-highlight repair is
visible near the fire. No distinct snowy-hill deformation was reproduced in
these captured sweeps. The reporter subsequently identified 1:37 in the 09.37.29 recording.
Frame inspection confirms transient dark vertical streaks across the snow face
at 97.17–97.33 seconds. The original village sweep did not cover that view;
the new clearing/hare captures cover that view but have not reproduced these
brief streaks. Minor interpolation artifacts around moving characters/particles
remain a separate quality question.

The village captures include the direct-highlight repair and precede the local
transport grace change and the final sun/NRD-history separation. Their PCK hashes are retained alongside the final
runtime hashes, rather than relabelled as final-package recordings. Test-only
capture code is retained as `record_snow_fg.gd`; the private bridge is not bundled.

Before the final sun/NRD separation, the supplied `coop__3_20261025_002628.sav` also passes
two Windows-EXE/Proton D3D12 loads with real NVIDIA FG in each mode: 17 raster
checks and 21 PT/NRD checks. Each cycle requires actual generated presentation,
advancing simulation, surviving weather processing and a readable full-size
1920x1080 view. [Save-load results](lia-fg-loads.json). This supplements the
unmodified release crash and native Vulkan save-load comparisons above.


## Final tree and moving-hare recordings

[Shadow recording metadata, SDK counters and hashes](shadow-recordings.json)
identify a 36-second, 60 FPS comparison and both full raw captures. Each run
passes 35 checks, including actual FG presentation, full-size swapchain,
active PT/native NRD and continued simulation. The fixed run includes the final
sun/NRD-history separation. In its enabled phases, 362 game presentations yield
724 SDK presentations. The visible tree shadows are coherent and the live hare's
shadow follows its movement instead of leaving stale receiver lighting.

The camera starts in the same authored clearing as the reported 1:37 view,
at ground coordinates (85,149), height +1.7, rotation (-0.18,-1.5,0), FOV 75.
Time is frozen at 10:00 for comparable sunlight; the world and animals continue
moving. PT Low, responsive NRD, DLAA, terrain 1 and shadows 2 are matched.
The test camera is detached from character control and the hero is hidden for
inspection. Each six-second segment is labelled for held/moving camera or hare,
with FG off/on. Natural NPC motion differs between the two runs, so the hare
segment is a qualitative moving-shadow comparison. The controlled registered
small-caster test supplies the matched quantitative negative control.

The supplied LiA save was rechecked after this final renderer change. Two further
Windows-EXE/Proton PT/NRD/FG loads pass all 21 checks with actual generated
presentation and advancing simulation. Its final PCK hash is retained in
[save-load results](lia-fg-loads.json) and [runtime provenance](provenance.json).

The requested 4K Windows capture could not be qualified: the virtual display
clamped the actual swapchain to 2880x1800 while the game viewport remained
3840x2160, and the SDK correctly disabled FG for the mismatch. The dimension
assertion and FG assertions failed. Those runs are excluded, including the
attempt with an explicit larger allowed window size; no display modes were
changed. This is a limitation of that test setup, not evidence of a 4K game bug.


A wider 1440p clearing sweep moves the camera ±12 metres and pans ±0.4 radians
with FG on and off. Both original and fixed packages pass 18 checks; 722 game
presentations produce 1,444 SDK presentations in each enabled phase. The
original still exhibits the tree-shadow problem, while the fixed scene retains
coherent shadows. The brief black hillside streaks from the user's 97.17–97.33
second frames were not reproduced in the inspected samples. This remains open;
no separate hill-specific correction is claimed. These exploratory captures are
only about 25.6 seconds for two 24-second test phases and are excluded from
phase-aligned or complete temporal-coverage claims. The delivered 1080p
comparison instead uses complete 81.5-second raw recordings. See
[hill sweep checks and capture limits](hill-route-checks.json).
