# Gameplay handoff — 9 October 2026

## Current continuation

**Current handoff, 9 October:** the user resumed the renderer list and remaining gameplay reports, with coordinated subagents. Canonical renderer/gameplay work remains combined on protocol 13. No release or device installation was made.

U45 supplied-save follow-up confirms two required small creatures remain alive; original completion works after their deaths. The one-of-three poison rule and separate premature queen-completion fix are confirmed. U39 healing, U40–U43 camp/inventory usability and U44 grounded dragon dialogue are locally fixed with dedicated evidence below. Renderer work continues from [OWNED_RENDERER_IMPROVEMENT_HANDOFF.md](/home/llm2x/Documents/EI/OWNED_RENDERER_IMPROVEMENT_HANDOFF.md); the earlier stop instruction is superseded by this resumption.

**Canonical checkout:** `/home/llm2x/Documents/EI/local/scratchpad/cpu-animation-20261006/release-repo`  
**Branch:** `fix/catacomb-coop-deck`  
**Current combined-export production checkpoint:** `79bee8a56f7a27a9897ae9ebe44fa6000d94cf21`. Includes the systemic solo/co-op fixes and bounded fresh-start correction as well as the renderer/cloud follow-up; later source checkpoints have separate acceptance records.

**Current combined private Linux export:** `/home/llm2x/Documents/EI/local/scratchpad/renderer-followup-20261009/integration/cloud-coop-final-01`. [Current combined validation](validation/renderer-coop-integration-2026-10-09.json) records 711 passing checks and 60 captures, including 157 representative gameplay checks: actual LiA reimport/travel, fresh-process solo resume, pending story actions and ordinary base NEW joins. The earlier 859-check [combined receipt](validation/renderer-followup-integration-2026-10-09.json), camp/queen routes and feature-specific results remain historical evidence.

**Included accepted source checkpoints:** `fdf7885` retains renamed guest identity (393 checks), `82b749f` fixes shared campaign travel (152 checks), `5c548be` adds optional natural terrain transitions, and `1b8b0f6` retains looted script-added actor identity (137 checks). `ec79e3f` protects stable saved hero references (106 checks), `74c4804` restores pending story actions on co-op-to-solo return (149 acceptance checks plus 36 formatting rechecks), and `80c96d4` preserves acknowledged solo earnings and compatible campaign checkpoints on rejoin (803 checks). `79bee8a` restores normal NEW joins after original opening initialization ([239 checks](validation/coop-fresh-start-2026-10-09.json)). Feature-specific receipts complement the current combined acceptance.

**Latest user scope:** fix systemic LiA solo/co-op progression sync. `coop_67_fps_20261008_224534.sav` is the latest client save and its matching host save is not supplied; the user explicitly says no exact-save repair is needed. Continue implementation and validation without treating the missing host save as a blocker.

**Current network protocol:** **13**; all peers, including the local simulation service, must match.

The full indexed tracker is [gameplay-gaps-2026-10-08.md](gameplay-gaps-2026-10-08.md): U01–U46 player reports and G01–G15 audit findings. It distinguishes implemented fixes from unverified playthrough/platform coverage. The original audit is `/home/llm2x/Documents/EI/local/implementation-gaps-2026-10-07.md`; it describes historical findings, many now fixed. Do not treat every item in that old audit as a new unfixed defect.

The previous long entry point, `/home/llm2x/Documents/EI/local/bugs-and-performance-handoff-2026-10-07.md`, now links here. This handoff supersedes its older current-work statements. Broad performance optimization remains deferred at the user's request.

## Follow-up requests and current evidence

| Tracker | User report / intended result | Useful starting points and checks |
| --- | --- | --- |
| U39 | Healing produces effects that fly upward. | Locally fixed in `1ee2336`: removed the extra billboard attached to the native rising light; original body-bound healing particles and light timing remain. [Receipt](/home/llm2x/Documents/EI/local/scratchpad/cpu-animation-20261006/release-repo/docs/gameplay-healing-validation.json): 56 passing checks, 68 original-x86 light samples and viewed ENet before/after captures. The exact originally reported spell/scene was unspecified. |
| U40 | Finished spells should display their installed runes, as weapons already do. | Implemented in `bd6ec28` / `e185314`: finished camp/equipped spells show original icons for actually installed runes, including duplicates, and name them in tooltips. Full spell artwork remains clear; empty legacy 3D previews no longer cover it. [Receipt](/home/llm2x/Documents/EI/local/scratchpad/cpu-animation-20261006/release-repo/docs/gameplay-camp-inventory-validation.json). |
| U41 | Entering a spell constructor should automatically filter to spells/relevant ingredients; weapon/armour constructors should do the corresponding filtering. | Implemented in `bd6ec28`: entering each constructor selects its combined matching bag/shop category, including compatible equipment, components and enchantment spells. Manual filters remain available. [Receipt](/home/llm2x/Documents/EI/local/scratchpad/cpu-animation-20261006/release-repo/docs/gameplay-camp-inventory-validation.json). |
| U42 | Holding the item-transfer button should repeatedly add copies to the shop offer, like holding a skill-upgrade button. | Implemented in `bd6ec28`: a held transfer captures the exact wear/charge item, starts repeating after 0.5 s and adds at most one per 0.075 s tick. Relevant input/UI/inventory changes cancel it; submission remains one atomic authority trade. [Receipt](/home/llm2x/Documents/EI/local/scratchpad/cpu-animation-20261006/release-repo/docs/gameplay-camp-inventory-validation.json). |
| U43 | Materials such as rocks/stones have no hover description. | Implemented in `bd6ec28`: material tooltips prefer the original localized MATERIAL description over the generic LITEM Material placeholder. [Receipt](/home/llm2x/Documents/EI/local/scratchpad/cpu-animation-20261006/release-repo/docs/gameplay-camp-inventory-validation.json). |
| U44 | The dragon in Dead City should remain grounded rather than flying. | Locally fixed in `8bb5ced`: the reference is a conversation, and original speaking/listening specials ground the Old Dragon there. Normal flight outside dialogue is preserved. [Receipt](/home/llm2x/Documents/EI/local/scratchpad/cpu-animation-20261006/release-repo/docs/gameplay-dialogue-poses-validation.json): 131 checks and viewed native-camera before/after captures; both peers honor phrase animations, idle updates and dialogue close. |
| U45 — priority progression blocker | In co-op, «Подземные твари»: players poisoned every source except the middle one; that middle objective unexpectedly showed failed. Killing the weakened queen did not advance the quest. User asks whether this is a softlock. | The supplied 9 October autosave has two required Baby armadillos still alive: UID 22 at (95.00, 75.50) and UID 23 at (103.09, 91.47), each 60 HP. The queen objective is already complete. [supplied-save receipt](/home/llm2x/Documents/EI/local/scratchpad/cpu-animation-20261006/release-repo/docs/validation/cave-queen-user-save-2026-10-09.json): 100 passing headless/rendered checks confirm original death gates, save/reload and visible unchanged actors from diagnostic nearby observers. This save does not demonstrate an all-dead softlock; no quest flags or user files were altered. Unused poison alternatives intentionally fail; separate premature queen-completion fix `8f0070d` remains valid. Separate generic fix `1b8b0f6` preserves explicitly looted script-added actor identity across reload; [tombstone receipt](/home/llm2x/Documents/EI/local/scratchpad/cpu-animation-20261006/release-repo/docs/validation/added-actor-tombstones-2026-10-09.json) records 137 passing candidate checks against 12 reproduced baseline failures. |
| U46 — solo/co-op continuity | LiA client gear progresses but its returned save remains at an earlier location/chapter. Players who progress together should be able to continue solo; compatible solo progress should carry into co-op and back. The user explicitly does not need the exact supplied save repaired. | Locally fixed: `82b749f` retains aligned guests through unflagged scripted travel; `80c96d4` imports acknowledged solo-earned stats/items, clears stale return checkpoints and admits matching new/returning campaigns while protecting divergent sources. [Solo-return receipt](validation/coop-solo-return-2026-10-09.json) records 803 passing checks, including original LiA chapter travel, real ENet, host rollback and fresh-process solo resume. `ec79e3f` prevents recycled unit IDs from changing saved hero identity; `74c4804` projects pending scripts/follow targets to the returned solo character. [VM-return receipt](validation/coop-vm-return-2026-10-09.json) records 149 acceptance checks plus 36 formatting rechecks. Whole-checkpoint compatibility conservatively requires matching nonexcluded authored flags, not only the journal. Original supplied saves remain untouched; full campaign/Windows/internet coverage is separate. |

The dragon image is an unmodified copy of `/tmp/codex-clipboard-eac71246-209a-41e8-a778-b93f0695759f.png`. The durable local copy must accompany a handoff to another machine; it is deliberately outside release assets. There is no new supplied screenshot for U39–U43. Two U45 diagnostic captures of the original surviving actors are linked in the [supplied-save receipt](/home/llm2x/Documents/EI/local/scratchpad/cpu-animation-20261006/release-repo/docs/validation/cave-queen-user-save-2026-10-09.json).

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

- **U45, «Подземные твари»:** The supplied 9 October autosave has two required Baby armadillos still alive: UID 22 at (95.00, 75.50) and UID 23 at (103.09, 91.47), each 60 HP. The queen objective is already complete. [supplied-save receipt](/home/llm2x/Documents/EI/local/scratchpad/cpu-animation-20261006/release-repo/docs/validation/cave-queen-user-save-2026-10-09.json): 100 passing headless/rendered checks confirm original death gates, save/reload and visible unchanged actors from diagnostic nearby observers. This save does not demonstrate an all-dead softlock; no quest flags or user files were altered. Unused poison alternatives intentionally fail; separate premature queen-completion fix `8f0070d` remains valid. Separate generic fix `1b8b0f6` preserves explicitly looted script-added actor identity across reload; [tombstone receipt](/home/llm2x/Documents/EI/local/scratchpad/cpu-animation-20261006/release-repo/docs/validation/added-actor-tombstones-2026-10-09.json) records 137 passing candidate checks against 12 reproduced baseline failures. This separate defect does not explain the two living survivors in the supplied save.
- **U36 / U11, 2× client freezes/teleports and walking in place:** local transport fixes are committed, but the reported multi-second Windows/internet symptom remains unreplicated. Current [hardware evidence](validation/sustained-coop-hardware-2026-10-09.json) uses two separate 120-second NVIDIA Forward+ runs of the final `79bee8a` pack with 415 Portal actors: 1× passes 52/52; 2× passes 51/52, retaining two jointly observed broadcasts absent at the guest. Both recover on the next matching state (247/139 ms after the owner observation); maximum guest gaps are 150/356 ms and frame gaps 60/76 ms. No gap exceeds 500 ms. Actual owner/guest views are 5120×2880 and 1280×720. Inputs and workers remain clean, with no foreign Godot process. The earlier [llvmpipe result](validation/sustained-coop-delivery-2026-10-09.json)—1,144 ms gap, 43 absences, 2× not run—is preserved; changed build/backend/view conditions do not establish its cause. The strict 2× failure, Windows/WAN/full-route coverage and user FPS case remain open.
- **U37, controller ergonomics:** rendered ENet tests cover actual input dispatch, but the latest self-cast/ally/body-part menu changes have not been tried with physical Retroid/gamepad controls.
- **U08, ~4 FPS after Catacombs:** not reproduced by prepared Linux exit/reload/restart comparisons. User cannot remember whether reload or process restart fixed it. Windows original route, longer session and transition/cutscene presentation remain open.
- **U01, exact turn-only vision disappearance:** reproduced point-ray popping was fixed and checked on desktop/Retroid. The specific Windows facing-only enemy/corpse disappearance was not reproduced.
- **U23, stolen quest pair duplicating on later corpse loot:** current native carrier/turn-in/save/reload/revisit/death/loot checks pass. Full reported route remains unconfirmed; do not invent another fix from the report alone.
- **U26, changed client display name:** `fdf7885` fixes a reproduced duplicate identity/tally on the normal menu → ENet rename/reconnect path. Ann → Alice → Ally retains the same actor, stats/items and private purse, including reload; 393 candidate checks and 43 captures pass. Current-name drawing was already correct in the baseline. [Receipt](validation/coop-rename-reconnect-2026-10-09.json).
- **U21, camp approach acknowledgement:** code now uses movement rather than stealing/use acknowledgement. An actual audio listening check remains.

- **U46, solo/co-op progress:** systemic shared travel, compatible personal reimport and pending-script return fixes are committed in `82b749f`, `80c96d4`, `74c4804` and `79bee8a`. Focused original-data/ENet, base/LiA fresh-start controls and fresh-process solo checks pass, including the current combined export. Independently played saves with different nonexcluded authored flags remain separate even if their journals look alike; full chapter/platform coverage remains open. No exact-save repair was requested or performed.

### Campaign and world coverage

- **G07/G15:** the base `gz15h` late-join case is now fixed. Audit other startup per-character rectangles/timers only where reachable behavior justifies it. The final change is deliberately limited to eleven inspected shared checks on this one map; individual traps and named/cosmetic teleports remain separate.
- **G07/G08/G13:** full prison and temporary Nalo/Jun/captive/Shaina chapters, remaining base captivity predicates, and any co-op participants omitted from authored named/cosmetic moves still need broader route coverage.
- **G02:** later LiA Jigran/finale progression, extended reconnect and independent resumed guest saves have not received full chapter playthroughs. Prepared party/bag/companion/pet progress tests already pass.
- **Haburu authored-call audit:** all five `BuyHaburuMain#2#N#0` calls are reached by the shipped `bz23k` WorldScript. Independent decryption and the current parser agree across all 130 supplied MOB scripts; none defines these helpers, and the pinned original executable has no matching entry among 227 native commands. This confirms absent authored procedures, not a demonstrated parser/builtin defect. No replacement routine was invented. Their intended optional-quest/shop behavior remains unverified. Base `Portal1`/`Portal2` are supplied by merged parent scripts and are not missing builtins.
- **Haburu first conversation:** a separate village approach regression is locally fixed. The authored display placement has no route even with every actor stamp ignored, so this exact LiA `bz23k`/Haburu/`fq15` case now uses the existing original conversation staging. Reachable conversations, cancellation and field path failures retain ordinary behavior. [Evidence](/home/llm2x/Documents/EI/local/scratchpad/cpu-animation-20261006/release-repo/docs/validation/lia-haburu-2026-10-09.json): 379 passing checks, including actual first-topic completion and pending/completed save reloads. Player 0/1 topic-context controls are host command tests, not new ENet or full-chapter coverage.
- **U04/U06:** full camp escape and Catacombs play with larger real-network parties. Three original-combat ENet escapes and a five-rider lift fixture already pass; boarding order can still matter.
- **U07/U17/U27:** other bridge/water camera shots, mobile/full dialogue coverage, long third-person play and decorative scenery camera behavior remain. Do not reopen the fixed basic Catacombs floor and same-floor/cross-floor melee rules without a reproduction.
- **U25:** the full ordinary harpy route remains open. The [source/checkpoint audit](validation/harpy-route-feasibility-2026-10-09.json) passes 85 checks: supplied saves are already past the harpies and amulet turn-in, assisted campaign checkpoints use explicit gameplay hooks, and 37 historical ordinary records reach no later completed phase than `hunt_return`. Bounded ordinary retries preserved ten living waypoint/retreat saves but ended in early theft/combat, establishing no new quest completion or product defect. Original harpy chest completion and the dragon's geographical return (`y < 295`, then `Guard` and `Sleep(150)`) are distinct. Prepared native-timer and ENet save/reconnect checks remain valid, but do not prove the full route.
- **U02/U12/U34/U35/G14:** cross-platform and full-chapter validation of loading, corrected LiA map flow, Kel progression and other dialogue save/wait sequences remains. Focused fixes are already committed.

### Packaging and performance boundaries

- No post-Experimental-6 packages are published. Future packaging must bump the displayed version and Android code, retain signing identity, use matching protocol 13 peers, audit content/checksums, and keep original game assets, private saves and probes out of distributables.
- Prior packaging recipes: `/home/llm2x/Documents/EI/local/scratchpad/portal-60-20261007/package_experimental6.py`, `audit_experimental6.py`, `publish_experimental6.py`. These contain version/tag/output assumptions; **do not rerun them unmodified against release 6**. See `docs/experimental6-validation.json` for proven prior inputs and caveats.
- Windows/macOS packages were cross-exported, not runtime-accepted on their target OS. macOS uses stock-engine/script fallbacks and is unsigned/unnotarized. Latest GDScript follow-ups have only the recorded Linux validation unless an earlier receipt explicitly says otherwise.
- Broad FPS optimization stays deferred. User accepts **1×, original graphics, approximately 60 FPS on Retroid Pocket 5**. Earlier desktop 100+ FPS statements did not establish the user's case: latest Experimental, Ryzen 7945HX/RTX 4090 Mobile laptop, 4K, 100% render scale, max remake settings, 2× co-op, about 40 FPS. User said shipped defaults; renderer was not explicitly confirmed. Do not present mismatched Linux or virtual-display tests as a fix for that Windows case.
- Keep useful service/terrain work, but any future CPU redesign must survive repeated complete-tick/simulation measurements. Rendering tests under Xvfb establish function, not FPS acceptance. Avoid overlapping unrelated project benchmarks.

## Gameplay continuation evidence

The [cave queen receipt](/home/llm2x/Documents/EI/local/scratchpad/cpu-animation-20261006/release-repo/docs/gameplay-cave-queen-validation.json) records 290 passing checks across all three actual original poison routes, host/guest parity, looted corpses, save/reload and reconnect. The baseline source3 route completed the quest before the weakened queen died; `8f0070d` corrects native IsDead semantics. The [supplied-save receipt](/home/llm2x/Documents/EI/local/scratchpad/cpu-animation-20261006/release-repo/docs/validation/cave-queen-user-save-2026-10-09.json) adds 100 passing checks on the actual supplied autosave: two living required armadillos explain the incomplete quest, and their real deaths complete it without success flags. No user save is modified or distributed as repaired.

The [dialogue receipt](/home/llm2x/Documents/EI/local/scratchpad/cpu-animation-20261006/release-repo/docs/gameplay-dialogue-poses-validation.json) records 131 passing checks and viewed before/after shots from the original Dead City dialogue camera. `8bb5ced` restores native speaking/listening specials on both peers and releases them at dialogue close. Grounding is limited to conversation; normal flying movement and idle remain original.

The [healing receipt](/home/llm2x/Documents/EI/local/scratchpad/cpu-animation-20261006/release-repo/docs/gameplay-healing-validation.json) records 56 passing checks, 68 retained original-x86 light samples and viewed before/after ENet captures. `1ee2336` removes the extra rising billboard while preserving original particles and illumination. The precise originally reported spell/scene was unspecified. A historical broad scratch light fixture fails identically before/after and is retained as excluded evidence, not reported passing.

All three use disposable Linux profiles and isolated exports; no user saves, shared release staging, publication, protocol/schema change or platform/performance claim. Full campaign and real-network/device coverage below remains open.


U40–U43 are implemented in `bd6ec28` and `e185314`. [Camp/inventory evidence](/home/llm2x/Documents/EI/local/scratchpad/cpu-animation-20261006/release-repo/docs/gameplay-camp-inventory-validation.json) records 480 passing assertions across six retained runs, including the latest base headless 88, LiA rendered 92 and a separate actual ENet trade 31. Screenshots were inspected. Held input uses a single-session fixture plus separate authority regression; physical touch/gamepad and Windows remain untested. LiA rendered Unicode-to-ASCII diagnostics are retained and not claimed fixed. No release or installation was made.

## Earlier prison checkpoint evidence

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

`C/game` is the canonical source. `R/candidate` is the export staging project; copy changed production files there before exporting. At the historical prison checkpoint, its two changed files matched export57 byte for byte. The current gameplay continuation used separate isolated snapshots and receipts above; those do not imply that shared staging has been refreshed. Export57 used the existing patched runtime and native library. Do not use another stale checkout or assume `--path C/game` tests the exported production PCK.

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

Historical device note: at the earlier stopped checkpoint, private APK67 was stopped with autorun disabled and the public/normal app was unchanged. The current continuation supersedes that old stop request. No device installation was performed in the current renderer/gameplay continuation; recheck live device/process state before future acceptance work.
