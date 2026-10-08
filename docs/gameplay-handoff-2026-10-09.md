# Gameplay handoff — 9 October 2026

## Stop state and how to resume

**Continuation update, 9 October:** the user authorized the renderer chat to
continue the renderer list, then tackle this backlog, and confirmed that it is
the only agent working on EI. Renderer changes through `7202b8e` and this
handoff's gameplay source `09ffbf7` are now combined at `f6c8922` in the canonical
checkout below. Protocol remains 13; no release or installation was made.
See `docs/owned-renderer-improvements-2026-10-08.md` for integration evidence and
remaining renderer work. U45 still takes priority when gameplay work starts.
The following stop statement and export57 details describe the previous chat's
handoff, not a new stop instruction for the authorized continuation.

The user explicitly requested: finish the current task, write the remaining work and new reports into a handoff, then stop for now so another agent can continue. The current task is finished and committed; the overall backlog is **not complete**. Do not restart work without a new instruction to resume. No release or device installation was made during this final task.

**Canonical checkout:** `/home/llm2x/Documents/EI/local/scratchpad/cpu-animation-20261006/release-repo`  
**Branch:** `fix/catacomb-coop-deck`  
**Final production-code checkpoint:** `ad52a200bd5f3dadbbf66bb678d95d1a1b6a924f` (`ad52a20`, shared prison triggers). A subsequent documentation-only commit contains this handoff; use `git log` for the checkout's current HEAD.  
**Latest validated Linux export:** `gameplay-gaps57`  
**Current network protocol:** **13**; all peers, including the local simulation service, must match.

The full indexed tracker is [gameplay-gaps-2026-10-08.md](gameplay-gaps-2026-10-08.md): U01–U45 player reports and G01–G15 audit findings. It distinguishes implemented fixes from unverified playthrough/platform coverage. The original audit is `/home/llm2x/Documents/EI/local/implementation-gaps-2026-10-07.md`; it describes historical findings, many now fixed. Do not treat every item in that old audit as a new unfixed defect.

The previous long entry point, `/home/llm2x/Documents/EI/local/bugs-and-performance-handoff-2026-10-07.md`, now links here. This handoff supersedes its older current-work statements. Broad performance optimization remains deferred at the user's request.

## New requests queued for the next agent — none implemented yet

| Tracker | User report / intended result | Useful starting points and checks |
| --- | --- | --- |
| U39 | Healing produces effects that fly upward. | Inspect `game/src/game/spell_fx.gd`, `spells.gd`, native spell-particle code and original healing effect data. Compare original attachment, height, velocity, coordinate space and lifetime before changing the art. Reproduce on host/client; exact healing spell and failing scene were not specified. |
| U40 | Finished spells should display their installed runes, as weapons already do. | Inspect `game/src/ui/item_view.gd`, `camp_view.gd`, `spell_slots.gd`, and spell/item parsing. Preserve the already-fixed coloured artwork filling the slot. Derive markers from installed runes, not just the prototype. Check inventory, constructor and equipped spell displays as appropriate. |
| U41 | Entering a spell constructor should automatically filter to spells/relevant ingredients; weapon/armour constructors should do the corresponding filtering. | `game/src/ui/camp_view.gd` and `inventory_panel.gd`: mode changes, `reset_filters`, filter selection and ingredient compatibility. Ensure switching constructors updates visible items and usable components remain accessible. |
| U42 | Holding the item-transfer button should repeatedly add copies to the shop offer, like holding a skill-upgrade button. | `camp_view.gd`, `inventory_panel.gd`, the existing training repeat-button behavior. Stop on release, focus/mode change, unavailable inventory, or submitted trade. Preserve counted sale stacks, per-player inventory, wear/charge distinctions, and atomic authority validation. |
| U43 | Materials such as rocks/stones have no hover description. | `game/src/game/items.gd`, original material records/localization and `item_view.gd`/`camp_view.gd` tooltips. Check material IDs and description keys rather than fabricating missing lore. |
| U44 | The dragon in Dead City should remain grounded rather than flying. | Reference screenshot: `/home/llm2x/Documents/EI/local/bug-references/2026-10-09/dead-city-dragon-reference.png`. Compare that actor's original map placement, movement class, altitude and animation; inspect `game/src/game/unit.gd` and figure/animation selection. This is a separate report from Terror's disappearance and the amulet dragon's timed departure. Do not globally disable flying creatures or all dragon wing animation. |
| U45 — priority progression blocker | In co-op, «Подземные твари»: players poisoned every source except the middle one; that middle objective unexpectedly showed failed. Killing the weakened queen did not advance the quest. User asks whether this is a softlock. | Not reproduced or diagnosed. Establish the exact campaign/map and inspect original poison-source completion/failure conditions, queen weakness/death gates, script order and shared co-op quest state. Look for a disposable copy of a pre-failure save; do not rewrite success flags or award completion merely from this report. Test the actual poisoning → queen-death route, host/guest parity and save/reload recovery after diagnosing the cause. |

The dragon image is an unmodified copy of `/tmp/codex-clipboard-eac71246-209a-41e8-a778-b93f0695759f.png`. The durable local copy must accompany a handoff to another machine; it is deliberately outside release assets. There is no new screenshot for U39–U43 or U45.

## Unpublished fixes already available

Last release published by this chat: [Experimental 6](https://github.com/TheWWWorm/CursedLands/releases/tag/v1.0.3-experimental.6), source/tag `78498914b00842d216cd19544a5647bc9ad79555`, protocol 11, Android versionCode 16. Do not replace its existing tag or assets. The source version label still says Experimental 6; **that label does not mean the current local changes shipped**. A future release needs a new version and packaging pass.

All commits below are present in the canonical checkout, after the Experimental 6 tag:

| Commit | Implemented change |
| --- | --- |
| `433d5d9` | Another selected qualified actor can operate a lever when the selected leader cannot reach it. |
| `40ea5a9` | Preserve completed dialogue flags on explicit saved-VM load; release slave-camp bounds when the barrier breaks; stage and resume extra guests during the Terror escape. |
| `3b33723` | Widen the Catacombs lift/deck and support group boarding/unloading without changing the original lift script timing. |
| `6407b53` | Replace the incorrect LiA fallback route button with original adjacent-region discovery/selection behavior. |
| `a8eb6ff` | Decode promised quest money as float32: Маскировка is 230, not 1,130,758,144. XP remains 10; no purse rewriting. |
| `9e4576f` | Recover already-resurrected Terror only after the authored escape removal; expose the hidden third-person settings selector; enforce safe-zone direct attacks/casts; cover main-menu loading before showing HUD; retain/persist/recover Kel as a Shelter NPC so Маскировка can progress. |
| `2ff3d5a` | Real-time snapshot cadence, per-actor packet ordering and stop recovery, compact visibility history; controller self/ally spell targeting and body-part wheel; enforce learned-spell requirements after stat reset. |
| `ad52a20` | Finish the current task: original prison shared quest/discovery checks accept late co-op participants. |

Important behavior decisions already authorized by the user:

- Third-person mode still respects safe zones. This later request supersedes the earlier request to allow attacking everywhere.
- Stat reset refunds all trainable skills/abilities, initial ranks and gifts, including Zak's backstab. Base attributes remain. Spells may stay equipped, but cannot cast when requirements are unmet; they grey out. Intrinsic attributes may still satisfy a low-level spell.
- Gamepad friendly spells default to self; X self-casts, D-pad cycles allies, A/RT confirms. Body-part attacks use six equal labelled sectors with D-pad navigation and stick hysteresis/neutral-on-open.
- Terror recovery does not resurrect villagers already killed and saved by the old bug. Do not silently reset player saves to undo past consequences.
- Original campaign scripts/assets are evidence. Preserve established quest behavior; extend it consistently to additional co-op characters.

## Remaining investigation and validation

These are not all confirmed unfixed code defects. Read the linked tracker/receipts before reimplementing something that is already fixed.

### Priority reproductions and usability

- **U45, «Подземные твари»:** newly reported possible co-op softlock; prioritize this progression blocker before cosmetic requests. Details and investigation boundary are in the table above.
- **U36 / U11, 2× client freezes/teleports and walking in place:** local transport defects are fixed, but the reported multi-second internet/Windows symptom has not been fully reproduced and cleared. Latest measurements are short Linux loopback tests. Run a sustained busy LiA route at 1× and 2× with both peers on protocol 13; record authority tick progress, snapshot arrival gaps, packet sizes/loss, client presentation and freezes. Do not claim a blanket performance cure from isolated packet tests.
- **U37, controller ergonomics:** rendered ENet tests cover actual input dispatch, but the latest self-cast/ally/body-part menu changes have not been tried with physical Retroid/gamepad controls.
- **U08, ~4 FPS after Catacombs:** not reproduced by prepared Linux exit/reload/restart comparisons. User cannot remember whether reload or process restart fixed it. Windows original route, longer session and transition/cutscene presentation remain open.
- **U01, exact turn-only vision disappearance:** reproduced point-ray popping was fixed and checked on desktop/Retroid. The specific Windows facing-only enemy/corpse disappearance was not reproduced.
- **U23, stolen quest pair duplicating on later corpse loot:** current native carrier/turn-in/save/reload/revisit/death/loot checks pass. Full reported route remains unconfirmed; do not invent another fix from the report alone.
- **U26, changed client display name:** saved/live rebinding fix is implemented and save/load tests pass. Verify a real-network session using the same brought character, rename Ann → Alice, reconnect/reload, and compare overhead text and character preview while retaining stats/items.
- **U21, camp approach acknowledgement:** code now uses movement rather than stealing/use acknowledgement. An actual audio listening check remains.

### Campaign and world coverage

- **G07/G15:** the base `gz15h` late-join case is now fixed. Audit other startup per-character rectangles/timers only where reachable behavior justifies it. The final change is deliberately limited to eleven inspected shared checks on this one map; individual traps and named/cosmetic teleports remain separate.
- **G07/G08/G13:** full prison and temporary Nalo/Jun/captive/Shaina chapters, remaining base captivity predicates, and any co-op participants omitted from authored named/cosmetic moves still need broader route coverage.
- **G02:** later LiA Jigran/finale progression, extended reconnect and independent resumed guest saves have not received full chapter playthroughs. Prepared party/bag/companion/pet progress tests already pass.
- **Original audit unresolved-call candidates:** five undefined `BuyHaburuMain#2#N#0` helpers in `bz23k`, described in `/home/llm2x/Documents/EI/local/lost-in-astral/STATUS.txt` around line 324. Reachability and optional-quest impact are unverified. Base `Portal1`/`Portal2` are supplied by merged parent scripts and are not new missing builtins.
- **U04/U06:** full camp escape and Catacombs play with larger real-network parties. Three original-combat ENet escapes and a five-rider lift fixture already pass; boarding order can still matter.
- **U07/U17/U27:** other bridge/water camera shots, mobile/full dialogue coverage, long third-person play and decorative scenery camera behavior remain. Do not reopen the fixed basic Catacombs floor and same-floor/cross-floor melee rules without a reproduction.
- **U25:** finish the actual harpy quest route to confirm the tamed dragon's original delayed departure in context. Prepared native-timer and ENet save/reconnect checks pass.
- **U02/U12/U34/U35/G14:** cross-platform and full-chapter validation of loading, corrected LiA map flow, Kel progression and other dialogue save/wait sequences remains. Focused fixes are already committed.

### Packaging and performance boundaries

- No post-Experimental-6 packages are published. Future packaging must bump the displayed version and Android code, retain signing identity, use matching protocol 13 peers, audit content/checksums, and keep original game assets, private saves and probes out of distributables.
- Prior packaging recipes: `/home/llm2x/Documents/EI/local/scratchpad/portal-60-20261007/package_experimental6.py`, `audit_experimental6.py`, `publish_experimental6.py`. These contain version/tag/output assumptions; **do not rerun them unmodified against release 6**. See `docs/experimental6-validation.json` for proven prior inputs and caveats.
- Windows/macOS packages were cross-exported, not runtime-accepted on their target OS. macOS uses stock-engine/script fallbacks and is unsigned/unnotarized. Latest GDScript follow-ups have only the recorded Linux validation unless an earlier receipt explicitly says otherwise.
- Broad FPS optimization stays deferred. User accepts **1×, original graphics, approximately 60 FPS on Retroid Pocket 5**. Earlier desktop 100+ FPS statements did not establish the user's case: latest Experimental, Ryzen 7945HX/RTX 4090 Mobile laptop, 4K, 100% render scale, max remake settings, 2× co-op, about 40 FPS. User said shipped defaults; renderer was not explicitly confirmed. Do not present mismatched Linux or virtual-display tests as a fix for that Windows case.
- Keep useful service/terrain work, but any future CPU redesign must survive repeated complete-tick/simulation measurements. Rendering tests under Xvfb establish function, not FPS acceptance. Avoid overlapping unrelated project benchmarks.

## Final-task evidence

[Prison late-join receipt](gameplay-prison-late-join-validation.json) records export/source hashes and exact commands/logs:

- `prison-late-join-before-01`, export56: 39 focused checks, **14 failures**, no script errors.
- `prison-late-join-after-01`, export57: **39/39 pass**, no script errors.
- `prison-late-join-net-01`, export57: **15/15 pass**, real ENet arrival after native startup; guest completes the original objective while host remains outside, both peers retain it through save/load and reconnect.

This final task marks the inspected registration loops in `game/src/game/script/story_compat.gd`. `game/src/game/script/vm.gd` evaluates marked shared checks against currently eligible party members, retaining the native actor's priority and excluding chains that act on the individual. It suppresses duplicate copies for the same shared event. Native conditions/bodies, script names and saved instruction indexes are unchanged. Single-player and LMP preserve their prior behavior. No new per-actor polling threads or save schema were added.

The focused fixture controls positions/quest variables. The network fixture runs original startup, then isolates the relevant wait and freezes unrelated AI/combat to inspect delivery before automatic travel. Neither is a complete prison playthrough or platform/performance test.

The previous checkpoint's [network/controller/spell receipt](gameplay-network-pad-spells-validation.json) records export56: 17 spell-requirement, 19 rendered controller, 16 packet-recovery, 145 interpolation checks, plus the controlled transport and actual simulation-worker Portal runs. At 2×, the controlled transport payload fell from 862,996 to 338,432 bytes over eight seconds; it does **not** demonstrate general latency improvement. The short actual simulation-worker run's maximum guest packet gap was 212 ms. Do not extrapolate those eight seconds into a stable long-session guarantee.

## Working paths and reproducible commands

```text
C=/home/llm2x/Documents/EI/local/scratchpad/cpu-animation-20261006/release-repo
R=/home/llm2x/Documents/EI/local/scratchpad/cpu-redesign-20261006
P=/home/llm2x/Documents/EI/local/scratchpad/portal-60-20261007
N=/home/llm2x/Documents/EI/local/scratchpad/portal-throughput-20261007
Base original data=/home/llm2x/Documents/EI/inspection/extracted/app
LiA original data=/home/llm2x/Documents/EI/inspection/lost-in-astral/game
Base script text=/home/llm2x/Documents/EI/inspection/samples/scripts
LiA script text=/home/llm2x/Documents/EI/inspection/lost-in-astral/scripts
LiA original-code analysis=/home/llm2x/Documents/EI/local/lost-in-astral/native/decompiled
```

`C/game` is the canonical source. `R/candidate` is the export staging project; copy changed production files there before exporting. The two files changed in the final task match byte for byte. Export57 was built with the existing patched runtime and native library; no engine/native code changed this task. Do not use another stale checkout or assume `--path C/game` tests the exported production PCK.

Example commands after resumption (choose unused labels/output names; scripts intentionally refuse overwriting existing runs):

```bash
python3 "$P/export.py" gameplay-gaps58 --engine="$P/fast-runtime.x86_64"
python3 "$R/check.py" prison-late-join-resume-01 --variant=gameplay-gaps57 --campaign=base --fixture="$C/tools/tests/prison_late_join" --render-thread=safe
python3 "$R/check.py" prison-late-join-net-resume-01 --variant=gameplay-gaps57 --campaign=base --fixture="$C/tools/tests/prison_late_join_net" --render-thread=safe --extra=--ei-inline-host
```

The variables above must be assigned in the shell first. Fixture arguments use the absolute **stem**, without `.gd`. `check.py` uses isolated profiles in `R/users/<label>`, writes `R/<label>.log/.json`, and stops on script/parse/compile errors or its 300-second limit. `--campaign=astral` chooses LiA data. Rendered fixtures use `--rendered`; two-world rendered loads may need a 60–90 second fixture wait. `--ei-inline-host` prevents auto service startup from changing prepared two-world tests; the separate worker fixture intentionally exercises that service.

Export57 hashes:

```text
CPU.x86_64 5796d69b6eb9c256b3b22acb449f3ebe3f63d5eaf506645dc99859740ff9c98a
CPU.pck fa4d4dfdcf4b82553143275d7e7937d0dff41c6bd969b2c6ab2daf7b71854c47
libterrain_search.so 94c2ae2691a7eb96a26068ddc54c376fcdb32bb97d4b1923028fcec73f8cfa82
```

Existing ordinary LiA route fixture input, read-only:
`/home/llm2x/Documents/EI/local/lost-in-astral/checks/story-route6-profile/godot/app_userdata/Evil Islands Remake (PoC)/saves/lost_in_astral/lia_story_02_catacombs.sav`.
Despite the filename, its saved current zone is Portal (`gz1h`); it includes the old resurrected-Terror state now repaired on load. Tests must use disposable copies. Never overwrite the user's source save.

No task-owned test/worker process remains running after the final tests. Retroid was not touched during this final task. Its last recorded private package was APK67, stopped with autorun disabled; the public/normal app was unchanged. Recheck ADB/device state before any future test. New device installs were previously authorized, but the user has now asked this agent to stop.
