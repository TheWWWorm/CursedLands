# Issues 109–112: original comparison and regression checks

The four open reports are addressed on top of `bab580bd43e7d146c341904c3413bcfb471e5d22`
(1.28.0). All **110 issue bodies and their available comments** were read, including
closed reports. The refreshed inventory still contained 106 closed and four open
issues. [The complete review](issue-review.md) records their scope and disposition.
This is a focused repair and regression run, not a claim that all 110 reports were
independently reproduced on every supported platform.

## Changes and why the earlier fixes were insufficient

| Report | Cause | Change and regression protection |
|---|---|---|
| [#112](https://github.com/TheWWWorm/CursedLands/issues/112) | Save/load retained player perception lists but discarded NPC corpse memory and investigation state. A new runtime corpse instance then looked like a new discovery. | Save every observer's noticed/corpse references, NPC pending discoveries, suspicion age, and current investigation order. Resolve references after deployment and before perception. Repeated finished and unfinished reloads, new bodies, removed bodies, co-op reference projection, and separate authority processes are covered. |
| [#110](https://github.com/TheWWWorm/CursedLands/issues/110), [#106](https://github.com/TheWWWorm/CursedLands/issues/106) | The earlier repair disabled all trap casts. The original loader's replacement of the raw trap mask with its owner's enemy factions had been missed. | Restore trap casting with the captured map-diplomacy mask. Zak and companions are damaged; the nearby goblin and orc are excluded. Activation, cooldown, old saves, added maps, and removed traps are covered. |
| [#109](https://github.com/TheWWWorm/CursedLands/issues/109) | A gait request during casting overwrote the model's displayed posture before the cast finished. There was then no old posture from which to play the transition. | Keep the requested gait pending while a one-shot owns the figure. Play the transition after casting on the authority and replica. Existing posture, action-clip, paused-spawn, moving-cast, and equipment-continuity cases are retained. |
| [#111](https://github.com/TheWWWorm/CursedLands/issues/111), [#105](https://github.com/TheWWWorm/CursedLands/issues/105) | Waiting for two draw notifications does not guarantee that a particular SubViewport has replaced its old settled picture. | Keep each board rendered at its final 3D position and translate its canvas during the slide. Even a deliberately stale texture follows the current position. The Esc signpost keeps its existing reveal mechanism. |

Recent repair commits reviewed include `b06bc442` (103–108 and script identity),
`b0ac08fc` (timing, corpse alerts, blood and ground marks), and `89d03aa8` (UI,
shop state and transitions), from the October 23–24 UTC work. In particular, this
change keeps deferred corpse discovery and pack help, creature combat movement,
blood-pool lifetime/pose, exhausted-running acknowledgement, UI real-time clocks,
and the original Esc opening checks. The script-perception test's cleanup now
uses `erase_unit`, matching the read-only unit view introduced by the earlier
identity work; its seven behavioural assertions are unchanged.

## Original 1.06 evidence

The owned English GOG executable was inspected with REA/Ghidra and run in an
isolated Wine 11.20 prefix through GPU Lab. Its SHA-256, checked again after the
comparison, is:

```text
d0fc0bb2acf45f0e59fae89e55c16a59848ffa89fb68feee9f298a680b660ad8
```

Both the canonical executable and the isolated test copy retain that hash.
[Provenance](original/provenance.json), [the relevant disassembly](original/loader-mask.asm.txt),
[native replay results](original/mask-replay.json), and
[decoded Wine snapshots](original/wine-snapshots.json) accompany this record.
No original executable or game assets are included here.

### Trap selection

`0x481660`, specifically `0x481c31`–`0x481c80`, handles a magic-trap map record:
it clears the raw mask at record `+0x8c`, reads the owner at `+0x6e`, and sets
bit *i* when that owner's map diplomacy entry for faction *i* equals 2.
The gz3g shrine (4515) has raw `BBAB0001 = -1`, owner 2, and **effective mask 1**.
The runtime snapshot independently shows mask 1 at trap `+0x238` and interval
100 at `+0x284`. `AddMob` must use its source map's diplomacy too.

`0x52a920` queries each trigger circle and accepts living units whose faction bit
is in that mask. The virtual call at unit vtable `+0xdc` resolves to `0x446880`,
which returns the unit's dead field at `+0x274`: zero for living units. The
previous conclusion that this call rejects every unit was incorrect.
`0x52ab30` performs periodic selection, `0x52a4b0` casts, and `0x52ac20` advances
the countdown. Runtime `SetDiplomacy` does not rebuild the captured trap mask.

The bounded native test executes those **actual x86 instructions** with Unicorn:
the authored gz3g row, three sparse enemy rows (owners 0, 7, 31), no enemies, and
both dead-field values: **7 cases pass**. This is a loader/getter replay with
supplied records and stack state, not a replay of an entire native world.

The separate Wine comparison used trap 4515's authored circle near
`(195.395, 70.262)`, radius 30, and lightning spell. Ordinary enemy attacks were
neutralized for the experiment; GodMode was off. With Zak at `(200,85)`, the
disabled trap left HP at 38.7085 for more than 15 seconds; enabling it at the same
position killed him. With Zak outside and goblin 4573 plus orc 4497 held inside,
both remained alive at 25/40 HP after more than 30 seconds. Their positions and
alive/dead status were checked through the native console. These are manual
runtime observations; the committed snapshots and replay independently establish
the mask and predicate, rather than a recorded video of the damage experiment.

### Corpse retention

The native perception routine `0x5caa00` maintains noticed, corpse, and pending
lists. In the Wine setup, wolf 3326 was killed beside wolf 3327, the investigation
was allowed to settle, and the isolated quicksave was reloaded twice. Wolves
3327–3329 retained corpse 3326 in their corpse lists, with empty pending lists.
The decoded post-load snapshots show that retention despite changed controller
addresses. They do not establish every native save field or every edition's AI
behaviour; the remake's full Session and process-backed tests establish the new
serialization behaviour separately.

## Results

**25 test runs, 3,446 assertions, zero assertion failures; plus 7 native x86 cases.**
The [machine-readable result list](checks/results.json) links every retained log.
Logs omit repetitive `PERFORMANCE` and `[trace]` records only; assertions,
summaries and diagnostics are retained. Local paths are normalized.

| Coverage | Assertions | Result |
|---|---:|---|
| Corpse memory, mid-investigation/pending/finished saves, three finished reloads, reference projection | 30 | Pass |
| Corpse checkpoints through a separate authority, two reloads of each state | 23 | Pass |
| Magic-trap selection, actual damage, cooldown, activation, old saves, added-map mask, removal | 17 | Pass |
| Cast-to-posture transitions on authority and replica | 12 | Pass |
| Deliberately delayed menu viewport, normal and visibility-flipped reopening, 60/20 FPS caps | 49 OpenGL + 49 Vulkan | Pass |
| Prior Esc-board and pause-clock cases | 49 + 25 | Pass |
| Pack recovery, authored wolf investigation, creature alerts, spell alert encounter | 14 + 4 + 20 + 8 | Pass |
| Blood-pool saves and separate-authority replay | 18 + 10 | Pass |
| Posture presentation, replica clips, paused spawn, equipment continuity, moving casts | 19 + 43 + 42 + 56 + 50 | Pass |
| Object activity and absence, perception batch, script-visible lists | 24 + 6 + 2,857 + 7 | Pass |
| Stamina acknowledgement and real-time UI | 5 + 9 | Pass |

The final 30-check corpse test was also run with the unchanged baseline
`corpse_pools.gd`: **12 failures**, returning to **zero** with the repair. The
12-check posture test failed nine checks before the repair and passes all twelve
afterward. The final 49-check delayed-viewport test was also run against the
unchanged baseline UI: **eight failures**, covering Load and Save at both frame
caps with and without the visibility flip. It passes all 49 after the repair
under both OpenGL and Vulkan. The ordinary 49-check fixture already passed on
the baseline; it did not expose the delayed-viewport failure. See the retained
`before-*` and `baseline-*` logs for these distinctions.

Graphical tests ran on GPU Lab virtual displays with automatic GPU selection.
Vulkan used the standard released Linux engine with a locally exported PCK of
the changed source; OpenGL and CPU checks used Godot 4.7. Development profiles
were isolated, mouse confinement disabled, FPS visible, and all audio muted.
The virtual display emits `Parameter "monitors" is null.` during startup on both
baseline and repaired graphical runs; their assertions and exit status pass.
No Windows, macOS, Android, or browser release qualification is claimed here.

## Layout and translation

No player-visible text or new option was introduced. Translation coverage passes:
3,519 entries, 171 dynamic wiki keys, and 199 dynamic arena keys, with zero errors.
Options, Load, and Save were visually inspected at EN 1920×1080, RU 1280×720,
and DE 1024×768; [nine screenshots](layout/) are retained. Remake labels use each
selected language. The original text and board textures in these captures remain
English because the test data is the English installation; this is not a check
of the Russian/German original archives. The screenshots check settled layout;
the frame tests above check the opening transition.

## Reproduction and compatibility

Run each GDScript with a Godot source checkout using `--path /absolute/repo/game`,
`--headless --audio-driver Dummy --max-fps 30`, then user arguments
`--no-movies --ei-path=/absolute/original/game --tool=/absolute/repo/tools/tests/NAME.gd`.
Use separate `XDG_DATA_HOME`, `XDG_CONFIG_HOME`, and `XDG_CACHE_HOME` directories
and write the required muted development settings before startup.
The graphical cases need GPU Lab, `--display-driver x11`, and either
`--rendering-method gl_compatibility` or the qualified standard Vulkan engine
with a matching exported PCK. The frame tests temporarily use their 60/20 FPS
caps to exercise the two timing conditions.

Run `corpse_memory_save.gd` before `worker_corpse_memory.gd`, passing the first
profile's save directory as `--resume-dir=/absolute/.../saves`. Likewise, run
`blood_pool_save.gd` before `worker_blood_pool_save.gd`, passing its `blood-pool.sav`
as `--resume-save=/absolute/.../blood-pool.sav`. The native test requires Unicorn
and accepts `game.exe`, the original game directory, and an output JSON path:

```text
python3 tools/tests/original_magic_trap_mask.py /absolute/game.exe /absolute/game /absolute/result.json
```

Old saves remain readable. A save made before NPC memory was stored cannot
recover that missing history: an NPC may investigate once after loading such a
save, after which a new checkpoint preserves it. Trap saves with only activation
and cooldown retain the authored load mask; new saves also store the captured
mask. These changes do not resurrect NPCs that are already dead in a checkpoint.
No version tag, release asset, or issue status was changed as part of this work.
