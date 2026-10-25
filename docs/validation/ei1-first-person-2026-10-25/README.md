# First-person campaign zone audit — 2026-10-25

Ten bounded first-person routes completed with PT Low, native NRD, DLAA and
NVIDIA frame generation off/on. The reviewed samples did not establish a new
repeatable PT shimmer or flashing-terrain defect. Dar Leanos remained
substantially slower than the other routes and is an open performance finding.
This is additional coverage of the [EI1 fixes](../ei1-2026-10-25/README.md), not
a claim that all campaign locations or the original snowy-hill artifact are
cleared.

## Source and method

The tested production source is `e6c63ba90ad2b3ca782d86be885abf9e92c08d0c`, a
merge of local integration main `8f8dfd77` and the EI1 fixes `18b58726`. The
integration checkout was verified through `git worktree list --porcelain`.
This audit adds a fixture and documentation; it changes no production renderer
or gameplay behavior. No publication was performed.

The Windows D3D12 export ran under GE-Proton 11 in GPU Lab on automatically
assigned RTX 3090 / 3090 Ti GPUs. It used a local FG compatibility bridge, not
native Windows hardware. Native Linux Forward+ separately ran the registered
regressions. All profiles were isolated, muted, FPS-visible and cursor-free.
The actual gameplay/capture window was 1920×1080, with a 30 rendered-FPS cap;
the recorder sampled the display at 60 FPS. These are visual inspections, not
uncapped benchmarks or a reproduction on the reported 4K RTX 4090 Laptop GPU.
The compatibility bridge's diagnostic text is visible in some FG captures.

The fixture loads authored geometry through the real separate-process solo
authority and injects W-key events into the production first-person controller.
It scripts camera turns and selects navigable targets without teleporting the
hero. Four walking legs alternate forward and downward views, with held views
and pans between them. God mode prevents death; actors and collisions remain
active. FG is disabled for the first two legs and enabled for the last two.
Every measured frame checks PT, native NRD, the first-person body and usable
controls. FG checks require active SDK status and approximately two presented
frames per game frame, rather than only an enabled option.

## Coverage and recordings

The ten accepted runs total **719 checks, zero failures, 620.6 metres of actual
movement and 12 minutes 7 seconds of recordings**. PT, native NRD, first-person
view and usable controls were observed in all **18,390 measured frames**. The
FG-enabled phases total 9,286 game frames and 18,564 SDK presentations; each
run's measured presentation ratio was 1.999–2.000.

| Campaign / zone | Authored ID | Evidence directory | Distance | Video | Checks |
| --- | --- | --- | ---: | ---: | ---: |
| Gipat — Remote Mountains | gz4g | base-mountains-final | 64.1 m | 85.53 s | 72 / 0 |
| Gipat — River and islands | gz7g | base-river | 69.7 m | 76.57 s | 71 / 0 |
| Gipat — Cave | gz5g | base-cave-final | 26.7 m | 56.03 s | 72 / 0 |
| Ingos — City environs | gz11k | base-snow | 69.8 m | 85.53 s | 72 / 0 |
| LiA — supplied Black Market save | bz5h | lia-market-final | 52.9 m | 65.52 s | 72 / 0 |
| LiA — Catacombs | gz1d2 | lia-catacombs-final | 57.8 m | 65.05 s | 72 / 0 |
| LiA — Necromancers' Desert | gz3h | lia-desert-final | 70.1 m | 71.52 s | 72 / 0 |
| LiA — River and islands | gz16g | lia-river | 72.1 m | 75.03 s | 72 / 0 |
| LiA — Snow Wasteland | gz25k | lia-snow | 69.7 m | 70.52 s | 72 / 0 |
| LiA — Dar Leanos, neutral NPC relations | gz31j | lia-city-explore | 67.6 m | 75.55 s | 72 / 0 |

[Machine-readable coverage](coverage.json) records adapters, per-phase timings,
checks and fixture/runtime hashes. The Black Market input was a copy of
`coop__3_20261025_002628.sav` from the supplied LiA archive; the original was
not modified. Other routes start from isolated authored-zone fixtures.

Full local evidence is under
`/home/llm2x/Documents/EI/local/scratchpad/ei1-investigation-20261025/fp-zone-audit/`.
Each directory in the table contains `traversal.mp4`, `zone-traversal.json`,
`result.json`, adapter/capture metadata, phase PNGs, `run.log`, and reviewed
frame samples. Disposable Wine prefixes may be removed after completion;
profile logs/configuration are retained under `profile-evidence/` in that case.

The 79-second [movement reel](/home/llm2x/Documents/EI/local/scratchpad/ei1-investigation-20261025/fp-zone-audit/recordings/first-person-zone-audit.mp4)
contains one FG-off and one FG-on walking excerpt from every zone.
`recordings/segments.json` gives source timestamps. Clips retain real display
timing; only labels and concatenation were added. The older Gipat river capture
started about 8.8 seconds late because its recording marker was buffered. Its
walking phases are present, but the initial held view is missing. Subsequent
fixtures explicitly close the marker file. That older run also predates the
additional preparation-settled assertion, hence 71 rather than 72 checks.

## Findings and limits

- Tree shadows, snow/rock slopes, moving NPCs, cave walls and market geometry
  were inspected in phase samples and closer consecutive-frame comparisons.
  No new repeatable PT-specific shimmer or geometry flash was confirmed.
  Passing state/control assertions do not by themselves establish visual
  quality. The named river-zone routes chiefly cover banks/forest terrain;
  this is not a dedicated water-reflection stress test.
- A dark shape appearing behind the Ingos snow ridge was traced in full frames
  to an exposed tree stump as the camera advanced. The exact hill streak around
  1:37 in the supplied recording remains unreproduced.
- Some outward views in LiA snow/desert expose the finite authored terrain and
  background. Those sampled boundaries are stable, but remain a first-person
  presentation limitation; the audit does not hide or repair them.
- Dar Leanos is still slow. In the neutral exploration run its four walking
  phases averaged **16.7, 18.3, 23.3 and 24.6 rendered FPS**; their 95th-percentile
  frame intervals were **107.5, 81.4, 67.9 and 63.3 ms**. Capture, a 30-FPS cap,
  screenshot readbacks and Wine affect these measurements. The earlier normal
  hostile encounter was also slow (about 13–20 FPS), and guards physically
  surrounded the novice fixture. Neutral initial diplomacy allowed a complete
  route while preserving geometry, actors and collisions. It did not eliminate
  the low frame rate. This establishes an expensive scene, not a proven new
  renderer or simulation regression; no causal performance fix is claimed.
- No crash, lost control or stalled simulation occurred in the accepted routes.
  These short traversals do not establish long-session stability or campaign
  progression correctness.

The original game has neither this first-person controller nor path tracing,
so a matching original-Wine PT/first-person comparison is inapplicable here.
No new behavior fix was inferred from that absence. Original comparisons and
baseline-failing tests for the earlier fixes remain in the linked EI1 report.

## Pilot failures and fixture corrections

Failed pilots remain in the evidence directory and are excluded from the
accepted totals. Boars, rats and city guards physically blocked naive straight
routes. The fixture now tries alternate navigable bearings after no progress,
retaining normal collisions. An earlier supplied-save route crossed an exit
and opened the travel map; the route planner now avoids crossing exit regions
and asserts usable gameplay controls in every measured frame. Starting within
an entrance margin initially rejected all cave/desert routes; the planner now
allows leaving that starting margin while rejecting re-entry. A market pilot
began measuring during shader preparation; later runs wait for 90 consecutive
ready frames before recording. These were harness/gameplay conditions, not
evidence that PT caused the character to freeze. The city's neutral relations
are explicitly recorded and are not applied to the supplied-save run or the
registered regressions.

## Registered regression results

The new river and LiA snow cases run through `tools/check_regressions.py` with
Forward+ and an isolated profile. Both passed 50 checks. The related rendered
cases passed: shadow motion (12), direct-light stability (14), native NRD
device (26), and history handoff (13). The five clock/transport cases passed
106 checks, including the real 90-second local shader stall. Together this is
**271 checks across 11 passing cases**. The runner's eight Python unit tests
also passed.

The first shadow-motion CLI wrapper timed out waiting for a busy GPU queue,
before reporting a fixture result. Its failed record is retained; a fresh
`shadow-recheck` passed unchanged. See [compact regression results](regressions.json)
and the full local `integrated-clock/`, `integrated-rendered/` and
`shadow-recheck/` logs. The first rendered batch therefore has an overall
failed status despite the subsequent successful recheck.

Example portable invocation from the repository, with paths to a qualified
custom engine/PCK and owned game data:

```sh
python3 tools/check_regressions.py --engine /absolute/native-runtime/godot \
  --packaged --base-data /absolute/base-data --astral-data /absolute/lia-data \
  --only path_trace_zone_traversal_river \
  --only path_trace_zone_traversal_snow --output /absolute/evidence
```

The fixture also accepts a direct Windows D3D12 run with `--zone-route-fg`,
`--zone-route-zone=ZONE`, `--zone-route-save=/absolute/save.sav`, and
`--audit-out=/absolute/evidence`. The local `run_windows.py` records its exact
arguments, adapter and binary hashes. Supplemental `--zone-route-peaceful`
changes initial relations only when creating a synthetic save. Neither an
unsupported FG runtime nor merely requesting FG qualifies as a passing FG test.
