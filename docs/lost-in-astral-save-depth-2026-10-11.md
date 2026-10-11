# Lost in Astral: deeper save audit, reflections and health bars

11 October 2026. Follow-up to the [playability and save audit](lost-in-astral-completeness-2026-10-11.md).

## Published experimental package

The save, reflection and health-visibility repairs are available in [1.0.4 Experimental 3](https://github.com/TheWWWorm/CursedLands/releases/tag/v1.0.4-experimental.3) for Linux, Windows, Android ARM64 and macOS. The isolated package passes 487 save/health checks, 32 reflection-geometry checks, the 57-view bridge/tree matrix and clear-camera sweep, and 62 Android checks. Its combined-effects scene exits normally. [Package validation](https://github.com/TheWWWorm/CursedLands/blob/v1.0.4-experimental.3/docs/validation/experimental-1.0.4-3-2026-10-11.json) records the exact scope and remaining limits. Co-op requires network protocol 15. The working-checkout and development-runtime notes below are retained as historical evidence.

## Working checkout repair

Paid delayed casts now keep their remaining delay and already-paid state, including consumed healing potions. Taming stages, faction history and peace masks survive reload. Persistent pet identities reconnect VM variables, effects and projectiles after save/load and travel, including dead and looted pets. Guest-return projection maps physical actor references without confusing a same-named host with the guest.

The related frozen-clock, NPC mana/hostility, hero-facing, scripted-order and direct-projectile omissions from the earlier audit are also repaired. Lost in Astral's two inspected `gz13g` acid traps now register later arrivals through their original guarded script families. Spell-sound teardown clears callbacks that retained their world.

Mirror water on Forward+ now has one reflected scene view, clipped at the active water level. It captures bridge undersides and tree geometry that the main screen cannot see. The view uses half resolution, capped at 1,024 pixels on its longest side, and excludes water to prevent recursive rendering. Natural, other renderers and other water levels retain screen-space tracing. The rejected silhouette-filtering experiment is absent from the working source.

Validation and remaining limits are recorded separately in the [repair receipt](validation/lia-save-repair-2026-10-11.json). The accepted save/co-op suite contains **488 passing checks**, including real loopback guest returns and late trap registration. Reflection inspection covers **30 bridge views and 27 tree views**, grazing/elevated/oblique angles, and a camera-angle sweep in base-campaign `gz3g` / `zone3obr`. The earlier `zone1` captures are preliminary controls from before the village. [Bridge and tree comparisons](/home/llm2x/Documents/EI/local/scratchpad/lia-save-repair-20261011/mirror-comparison.jpg).

The combined-effects scene renders, but its process hangs during shutdown with both the current and original water code; the existing patched runtime also times out. This remains an unresolved validation limit and is excluded from passing results.

The changes are in the working checkout and isolated QA artifacts. Existing player saves were not modified, and no release package was published. Full campaign-route acceptance, extended multi-machine continuation and the proposed story-checkpoint/debug controls remain open. The sections below retain the original findings against the frozen Experimental 2 package.

**Four more save-state gaps are reproduced in 1.0.4 Experimental 2:** paid casts can disappear, partial taming is lost, references to restored pets break, and guest return saves can drop projectiles aimed at the guest. The cast defect also consumes healing potions without delivering their effect after reload. These findings strengthen the case for fixing persistence before declaring complete playability. They do not establish an unavoidable campaign softlock.

The reflection complaint was investigated in that same published build. The separate request to hide full-health overhead bars, except for enemies currently in combat, is implemented in the working checkout. Save and reflection fixes have not been shipped by this audit.

## Evidence boundary

Save probes use the frozen Linux **1.0.4 Experimental 2** package, original Lost in Astral data, isolated profiles and full `Session.save_game` / `load_game` disk round trips. They prepare edge states in actual maps; they are not played campaign routes. The package and fixture hashes, commands, raw results and exclusions are recorded in the [validation receipt](validation/lia-save-depth-2026-10-11.json).

The checkout contains concurrent work. Consequently the published package, rather than the mutable working tree, is the save and reflection baseline. Health-bar validation uses a separately frozen copy of the modified source. No existing player save was opened for writing.

The five principal save probes contain **52 diagnostic assertions: 42 setup/control assertions pass and 10 preservation assertions fail**. Those failures are the reproduced defects, not a passing regression suite. All five processes exit normally without script errors or teardown warnings.

## New save findings

| ID | Prepared state and observed reload result | Control and practical consequence |
| --- | --- | --- |
| S09 | Save during the delay after an ordinary healing spell pays mana. HP remains `5.484805`, mana is already reduced from `13.712013` to `3.712013`. Reload keeps the reduced mana but removes the pending effect. | Without loading, the same pending cast heals. After loading, advancing its timers does not heal. The equivalent test with an original `tiny potion 1` also removes the potion permanently without healing. |
| S10 | Save creatures at taming stages 1, 2 and 3. Stages 1 and 2 reload as stage 0; their `peace` state disappears. The stage-1 Scrab becomes hostile again. | Stage 2 retains its changed faction, but one further successful charm no longer completes taming. A fully tamed stage-3 Toad survives as a pet. |
| S11 | Fully tame Scrab UID `1121`, retain it in a diagnostic VM variable and launch a targeted arrow at it. Reload creates exactly one pet, now UID `1500000002`; the VM value becomes null and the arrow disappears. | Pet existence and health are not the issue: references still name its old identity. The VM variable was injected for this test; no mandatory original quest relying on that variable is claimed. |
| C02 | In a real loopback co-op session, put one arrow in flight toward the guest and another toward an NPC. Produce the guest's return save through the normal transfer/merge path, disconnect and load it solo. | Both arrows are present in the returned file. The NPC-targeted arrow resumes; the guest-targeted arrow disappears. The guest changed from controller 1 to controller 0, while the saved arrow still names controller 1. |

### S09: a paid action needs a save record

`GameUnit._do_cast` deducts mana or consumes the belt item before calling `Spells.cast_after`. That function schedules a weak-reference callback in `Spells.WorldTimers.pending`. `Spells.save_lasting` serializes established lasting effects and targeted arrows, but not these anonymous callbacks. The character and inventory therefore retain the payment while the promised effect is lost.

This is distinct from stopping a queued movement order on load, and from the previously reported omission of free-aim arrows. The spell has already committed its cost. Both the normal spell and original healing-potion tests use the production cast path; the no-load controls deliver healing.

A repair should represent a pending cast as data: stable caster/target references, spell, destination, remaining logic ticks and an already-paid marker. Restore it once, without charging again. Do not try to serialize a `Callable`. Test saves immediately before payment, after payment, at the effect boundary, and after delivery; also test a dead/removed caster or target and a guest returning to solo.

### S10: original intermediate taming state is serialized

The original LiA taming routine at `0x4c1220` uses creature-logic fields `+0x908`, `+0x90c` and `+0x910` for stage and faction history. The original logic writer `0x4c3900` writes those same fields; disassembly at `0x4c3b08`, `0x4c3b14` and `0x4c3b2c` corroborates the offsets. The original unit writer `0x4b0f90` also streams its allowed-hostility mask at `+0x248`.

The remake keeps partial taming and peace in runtime metadata but omits them from the ordinary NPC body record. A changed faction alone is insufficient. Save and restore the stage, original/tamer faction history and peace mask together, including ownership changes and interrupted taming. The fixture forces successful production charm transitions with high power; it is not evidence of an organic character progression route.

### S11: pet references need a persistent identity

`CampaignState.collect_pets` removes `nid` from each pet's copied object record; `Session._spawn_pet` assigns a fresh world UID. Both the VM object reference and `Spells._caster_ref` currently identify a non-hero pet by world UID. Restoring the pet therefore does not repair its references.

A persistent pet key, or an explicit old-to-new actor mapping applied before references are restored, is needed across the VM, effects, projectiles and other actor links. Simply forcing every pet to reuse its old world UID risks collisions after travel. Validate at least save/load, travel, multiple pets, dismissal/death and co-op ownership changes.

### C02: guest projection must include effects

The co-op return path projects hero references inside VM state, but copies the zone's `lasting` effect records without applying the same ownership mapping. In this test the target remains `["hero", "Depth Guest", 1]`, although the solo hero resolves as `["hero", "Depth Guest", 0]`. `Spells._caster_of` requires the controller to match and silently cannot resolve the old target.

Apply a common actor-reference projection to every saved reference format. Test guest-as-target and guest-as-caster separately, and distinguish host actors, companions and pets. Do not redirect an unrelated host's spell to the guest merely because a name matches.

This test uses two peers in one process over actual loopback ENet, followed by a separately constructed offline Session reading the returned file. It has 13 assertions, including the failing guest-target preservation check, and clean teardown. It is not a multi-machine or full-campaign network acceptance test.

## Candidates not promoted to confirmed LiA defects

- A pending guard-alarm test failed its setup: the chosen prison map had no alarm-raising NPC. A corrected scan of all 130 supplied LiA MOB files found no nonzero authored `alarm_raise` value. The first scan used the wrong record collection and is excluded. This does not support claiming a missing active LiA alarm mechanic.
- A Linux `/dev/full` probe is rejected at file open with error 12. It does **not** reproduce a post-open disk-full save failure. The first fixture omitted Session initialization and crashed; it is excluded. Source still warrants reviewing post-write error checks and atomic replacement, but this audit does not claim reproduced save corruption.
- Call-name coverage from the first report is not proof of every built-in's behavior. The five unresolved Haburu procedures remain unresolved original-data references; no new missing mandatory procedure was established here.
- Dialogue, combat scheduling, later chapter transitions and extended guest continuation still need route-level acceptance. The previous confirmed frozen-clock, NPC mana/hate, facing and direct-projectile gaps remain separate findings against the frozen package.

## Water reflection investigation

The supplied screenshot is from **1.0.4 Experimental 2**. Its exact map, preset, renderer and camera are unknown. The retained comparison uses a different original bridge: base-campaign `gz1g` / `zone1`, object `1982`, on Linux Forward+ with an RTX 3090 Ti. The same packaged enhanced-water shader is used. It is a reproduction of the artifact class, not an exact reconstruction of the screenshot.

Three low, fixed camera views were captured with reflections Off, Natural and Mirror. Natural and Mirror introduce irregular dark reflected silhouettes and gaps near the bridge/river vegetation; Off removes those scene-reflection fragments. Natural is less strongly weighted but does not eliminate the artifact. The native water clock is held; this is a still-image inspection, not a motion-stability or performance acceptance run.

Retained inspection images: [Off / Natural / Mirror comparison](/home/llm2x/Documents/EI/local/scratchpad/lia-save-depth-20261011/reflections-5/overview.jpg) and [40-step / 120-step / filtered tracing comparison](/home/llm2x/Documents/EI/local/scratchpad/lia-save-depth-20261011/reflections-6/overview.jpg). The receipt identifies the unchanged source PNGs and their hashes.

The shader in `game/src/ei/terrain.gd` traces only the current opaque depth/color buffers: 40 quadratic steps over 45 metres, followed by six binary-refinement steps. It rejects hits below the water, outside a thickness tolerance, or at the screen/ray limits. It samples the reflected color at mip level 0. Mirror reduces ripple distortion but raises the scene-reflection weight cap from 0.20 to 0.35, making broken silhouettes more prominent.

**Likely cause:** discontinuous screen-space visibility combined with hard hit rejection, accentuated by sharp sampling and a low camera angle. Geometry hidden behind a bank, the unseen underside of a bridge, off-screen scenery and transparent objects are not recoverable from that single opaque view. This inference is supported by the code and the mode comparison; it is not a pixel-by-pixel diagnosis of the supplied screenshot.

A private shader experiment increased tracing from 40 to 120 steps, then also filtered reflected color at mip level 1.5. It softened detail but retained the incomplete reflected shape. The experiment is not a production change and no performance improvement is claimed. Raising the sample count alone is not an adequate fix.

For the current package, **Water reflections: Off** is the verified way to remove these scene-reflection fragments. The subsequent filtering experiment did not repair the silhouettes and is excluded from the source change. The working-checkout update above uses a bounded reflected-camera pass for Mirror on Forward+; the frozen package remains unchanged.

This result is separate from the previously recorded Android/Mobile held-water flicker. No claim is made that they share a root cause.

## Implemented overhead health-bar behavior

Full-health characters and idle enemies no longer get an overhead bar. A healthy enemy keeps its bar when the local party is attacking or casting at it, during a committed direct swing/cast, or when it is attacking a local party member. Merely pointing at an idle healthy enemy does not expose its bar. Damage still shows a bar; leaving combat at full health allows it to fade out.

`Always` now means every input method, while preserving the same health/combat visibility rule. Hidden/dead actors, first-person self-hiding, safe areas and loading gates retain their existing exclusions. Hidden healthy entries no longer consume the classic view's visible-bar budget ahead of injured/fighting enemies. The option help and existing full-health expectation were updated.

An optional trailing combat-target field in unit snapshots gives co-op clients the authority's relationship without installing an order locally. Older snapshots clear that optional relationship. The separate visibility fixture covers actual models, direct crosshair input state, committed casts, attacking/being attacked, healing, hidden/dead targets, and snapshot round trips. Exact final results and source hashes are in the validation receipt. This source change has not been packaged or published here.

Final validation: **25 checks passed**, with no script errors or teardown warnings; the frozen source imported cleanly. These are headless behavior checks, not a rendered or multi-machine acceptance claim.

## Repair priority

1. Preserve already-paid actions and their exact-once delivery, then the original frozen-clock and NPC mana/hostility state.
2. Give saved actor references one stable identity/projection mechanism; use it for pets and guest-return effects, rather than applying independent name/UID patches.
3. Restore the complete intermediate taming state and repeat save/load at all three stages.
4. Repair late-join trap enrollment from the first audit, then exercise the later campaign and guest-to-solo routes with saves at script boundaries.
5. Add the previously proposed checkpoint/debug controls and regression cases for these states; keep simple map teleport distinct from a valid story checkpoint.
