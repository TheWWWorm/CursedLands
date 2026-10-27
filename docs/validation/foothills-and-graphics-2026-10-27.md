# Foothills, co-op, rendering and autochess reports — 27 October 2026

Later evidence and fixes for white foliage, village weapon poses and ground
cover are recorded in [the follow-up](foliage-village-followup-2026-10-27.md).
That follow-up also extends the #119 investigation and supersedes the village
weapon limitation below.

Local changes based on `9cacce1a83f176753447d4cf6b4a72bf13c060a9` (1.32.0),
on `fix/foothills-118-119-20261026`. Nothing was published or pushed. The local
integration checkout has separate, uncommitted loading work and was not modified.

## Findings and changes

| Report | Confirmed cause and resulting behavior |
| --- | --- |
| #118: attacking after a prone hit skips standing | A committed attack could replace a completed hit before an idle tick selected the posture transition. Authority now preserves the transition before the strike; replicas follow it without restarting a late transition. |
| Highlight makes a character lose PT | Selection reused material emission and obscured the traced lighting. Highlight is now a separate presentation parameter; traced shadows, metal response and indirect light remain visible. |
| Strength/weakness briefly removes PT | Rebuilding a figure invalidated its trace instances until the asynchronous snapshot finished. Stable part identities allow compatible replacement meshes to bind immediately and submit updated vertices. Geometry is isolated per actor so changing one body cannot reshape an identical neighbour. Incompatible equipment topology still follows the full rebuild path. |
| Disabled graphics settings look enabled | The options panel now displays the effective fallback or “Off (unavailable)” when a saved technology cannot run, keeps the requested preference for later recovery, and refreshes when runtime capability changes. DLSS/FG runtime errors have separate localized explanations. |
| Missing metal on the chest | The Hadagan chest shares an atlas with other objects. A mask applies the metal response to the authored lid/frame regions, retaining rough wood and the jug/oven materials. Open and closed chest states were rendered with and without PT. |
| Co-op displays Easy while combat uses Hard | Online combat already uses the full original multipliers. The settings display now reports that effective difficulty without replacing the saved solo preference. Tested with two real ENet peers. |
| Repeated “too tired to run” speech | Exhaustion could be queued repeatedly while an earlier refusal was still playing or waiting behind dialogue. Only one outstanding exhaustion acknowledgement per actor is retained. Other acknowledgement types and story speech keep their ordering. |
| NPC menu contains only Talk later | Original archives contain offered legacy topics with no briefing title/text. Input, highlights and the menu now share a visible-topic filter. Missing topics do not create an empty menu, finish a conversation or grant rewards; their raw script/save variables are preserved. This does not invent replacement dialogue. |
| Black triangular terrain patches | On steep authored MPR facets, smooth lighting normals can cross the face hemisphere. The previous correction negated them downward. Terrain now projects them continuously into the visible hemisphere in both tracing and the raster guide; two-sided object rules are retained. The mechanism was reproduced, but the exact trench location in the screenshot was not identified. |
| Extremely stretched desert walls | The existing cliff correction omitted sand and dry ground/rubble families. Fingerprinted original atlas metadata now includes these natural surfaces. Protected ground types, snow, cave overrides and modified/unknown textures retain their previous handling. Terrain height, anchors and floor transitions are unchanged. |

Autochess also adds **Odalisque / Наложница / Odalisque** as a selectable commander,
using her original `pretty` portraits and expression paintings. The inspector
reserves the full portrait width so its controls do not overlap her shoulders.

Round damage follows the requested [Underlords damage table](https://dotaunderlords.fandom.com/wiki/Damage):
each surviving recruit contributes `1 + floor((tier + 2 * zero_based_rank) / 3)`;
summoned echoes contribute zero. Defeat adds `floor(round / 10)`, with no damage
from creep rounds. A PvP draw costs both players 10 health. Local and online
authority use the same survivor calculation. Commanders are portraits rather
than battlefield Underlord units, so there is no separate commander contribution.
The EN/RU/DE guide describes the new rules.

| Recruit tier | 1 star | 2 stars | 3 stars |
| --- | ---: | ---: | ---: |
| 1 | 1 | 2 | 2 |
| 2 | 1 | 2 | 3 |
| 3 | 2 | 2 | 3 |
| 4 | 2 | 3 | 3 |
| 5 | 2 | 3 | 4 |

## Still unresolved

- **#119, Foothills speed:** fresh Foothills checks passed in released 1.32.0 and
  the candidate, including mana/effect clocks, travel, worker/save boundaries
  and normal/double speed. An apparent slowdown in a legacy Suslanger sample
  was traced to an owner pause RPC; repeated unpaused samples advanced correctly.
  No speculative production clock change was made. The reporter's exact session
  state remains unavailable.
- **Actual NVIDIA FG SDK failure:** the supplied Windows report identifies an
  RTX 4090 Laptop, D3D12 and `sl::eErrorInvalidIntegration` during map loading.
  This explains why working DLSS super resolution could coexist with unavailable
  FG. The settings misrepresentation is fixed; the underlying SDK integration
  failure is not. Its shared error wrapper does not identify the exact failing
  SDK call, and this workstation's RTX 3090/3090 Ti cannot qualify standard NVIDIA
  FG for that laptop. No engine integration fix or support claim is made.
- **Village weapons:** original map/prototype inventory and native village
  appearance code were inspected. Existing protagonist/guard/companion appearance
  regressions pass, but the crossbow-bearing foreground actor in the screenshot
  was not conclusively identified and no incorrect assignment was established.
  It must not be labelled Aliya based on the adjacent dialogue text. No blanket
  removal of NPC weapons was made.

## Original-game comparison

Reference executables: base `d0fc0bb2acf45f0e59fae89e55c16a59848ffa89fb68feee9f298a680b660ad8`;
patched LiA 1.02 `9ecd475f5776681b8ffe1a8bb05cf67fe7adcceb62d0949135261ed7d3616c12`.
Registered Wine 11.20 and separate, locked base/LiA writable prefixes were used
through GPU Lab. Unique saves, recordings, memory observations and decoded data
were retained before removing those disposable prefixes.

- Native posture/model code was compared, but the exact prone-hit/stand/strike
  sequence was not captured reliably under Wine. The remake failure and correction are
  demonstrated by the released-package negative control and rendered regression.
- Native briefing enumeration (`0x607320`) and the original archives confirm
  that missing legacy topics can produce blank choices. Base `b.merc5.n5_2` and
  LiA `b.merc10.n11_10` are covered by real-data tests. The exact photographed
  NPC conversation was not independently matched under Wine.
- Native acknowledgement dispatch (`0x547890`, exhaustion code `0x1d`) was
  checked. Continuous stamina-regeneration/voice backlog parity was not captured
  under Wine; queue deduplication implements the user's explicit requested change.
- Native village enter/leave routines (`0x605da0`, `0x606280`) and equipment
  visibility (`0x52ebe0`) were inspected. Bounded Wine village probes did not
  establish the exact pictured actor's weapon visibility. See the unresolved
  item above; this evidence does not justify stripping every villager's weapon.
- PT, PBR masks, DLSS/FG and autochess have no original-game implementation to
  compare. Original figure/texture/portrait resources were inspected instead.
  Desert projection deliberately improves the original stretched mapping; a
  same-camera negative control with the original mapping was retained.

## Regression evidence

All new cases are registered in `tools/regressions.json`. “Before” counts below
come from unfixed source/released 1.32.0 runs, not an assumed failure. Some tests
were expanded after that negative control; both versions and logs are retained.

| Case | Before | Passing candidate | Evidence batch |
| --- | --- | --- | --- |
| `prone_attack_recovery` | 32 failures / 128 checks | 148 headless + 148 rendered | `released-posture-red`, `dialogue-and-posture-final`, `posture-rendered-final` |
| `foothills_actor_clock` | Already passes | 24 headless + 24 rendered | `released-actors`, `released-actors-refined`, `refined-checks` |
| `path_trace_figure_continuity`, `path_trace_figure_live` | 26/36 and 4/8 failures | 42 + 8 checks | `pt-figure-released-red`, `pt-neighbour-final`, `pt-figure-native` |
| `unavailable_graphics_ui`, `rtx_runtime_failure` | 36/82 and 4/6 failures | 82 + 6 checks | `options-red`, `options-green`, `rtx-runtime-red`, `rtx-runtime-green` |
| `arena_round_damage`, `arena_odalisque` | 28/40 and 8/13 failures | 40 + 13 checks | `autochess-red`, `autochess-green`, `arena-guide-final` |
| `arena_odalisque_ui`, `arena_portrait_feedback_ui` | New commander absent; prior layout overlap captured | 145 + 106 checks | `arena-guide-final`, `portrait-feedback-final` |
| `chest_surface_material`, `chest_surface_live` | 3/6 failures | 15 + 9 checks | `chest-red`, `chest-green`, `chest-live-green` |
| `coop_difficulty_display` | 8/21 failures | 21 checks | `coop-difficulty-red`, `coop-fatigue-green` |
| `exhaustion_voice_queue` | 8/11 failures | 11 checks | `coop-fatigue-red`, `coop-fatigue-green` |
| `empty_dialogue_topics_base`, `empty_dialogue_topics_astral` | 4/9 failures each | 9 + 9 checks | `empty-base-red2`, `empty-topics-red`, `empty-topics-green` |
| `path_trace_terrain_horizon` | 8/25 failures | 25 checks | `terrain-horizon-red`, `terrain-and-material-final` |
| `terrain_desert_cliffs`, `terrain_desert_live` | Four real missing-family failures; one corrected fixture threshold | 14 + 10 checks | `desert-cliffs-red2`, `desert-cliffs-green`, `desert-live-visible` |

Related existing regressions passed: attack/cast/kill posture and pathing,
equipment and creature animation, safe-zone appearance, PT topology/handoff/
first-person models, surface maps, cliff meshes/blends, caves/snow, FSR settings,
co-op dialogue clocks, authored dialogue/highlights, mod profiles, stamina
acknowledgements, autochess combat/tournament and portrait feedback. Four gameplay
programs covering effects, direct-attack stance, worker clocks and network render
clocks passed **8,666 assertions** (`final-gameplay/report.json`).

The existing authored-village fixture switches to base-campaign dispatch while
loading LiA archives. It now supplies the five base topic titles at its existing
mock text boundary and adds two visibility assertions; all earlier assertions
remain. Real missing-text tests use actual base and LiA archives. The existing
stamina test only changes its result-line order for the runner parser.

Initial packaged/native-library setup failures, the first obstructed desert
camera, and incomplete UI runs remain in their logs. They are not counted as
passes. The desert camera now checks line of sight before choosing the real
dry-ground wall; the original image-change assertion was retained.

EN/RU/DE commander/guide UI was exercised at 1280×720, 2560×1440 and 3840×2160.
Retained screenshots include selection and neutral/win/loss expressions. The
translation checker reports 3,570 keys, 171 dynamic wiki keys, 201 dynamic arena
keys and zero errors. Path-trace shader checks cover 36 binaries, plus 13 SHARC
and 16 RTXDI variants. `git diff --check` passes.

## Local evidence and reproduction

Evidence root:
`/home/llm2x/Documents/EI/local/validation/foothills-118-119-20261026/`.
Each batch's `results.json` records script, engine, source and pack hashes,
commands and log paths. The gameplay report separately records its source/data
hashes. `qualification-summary.json` selects 48 passing cases (3,087 assertions),
including all 30 newly registered cases, whose test hashes match the final
scripts. These are focused runs across the investigation, not a claim that the
entire repository test suite ran at once. Source snapshots preserve historical test revisions after disposable
staging is removed. Reporter originals remain in `reports/`.

Useful visual comparisons are in `desert-live-visible/terrain_desert_live/data/
godot/app_userdata/Cursed Lands/water-rt-artifact/` (`desert-original-mapping.png`,
`desert-raster.png`, `desert-pt.png`) and `chest-live-green/`. The final localized
commander/guide captures are under `arena-guide-final/arena_odalisque_ui/data/
godot/app_userdata/Cursed Lands/`.

From the task checkout, use `python3 tools/check_regressions.py --help` and select
the listed case IDs with repeated `--only`. Native PT cases require the custom
engine; the retained local candidate is at
`../native/CursedLands.x86_64`, with the adjacent verified PCK. Use `--packaged`,
the registered base/LiA data paths and a fresh output directory. Rendered cases
are scheduled through GPU Lab. Tests use isolated muted profiles, free cursor
and FPS display; no player settings or original reference assets were modified.
