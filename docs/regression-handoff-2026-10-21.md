# Cursed Lands regression handoff — 2026-10-21

The previous investigation stopped at the user's explicit request: “summarize remaining work, put it into handoff and chat and stop.” On 2026-10-21 the user explicitly reopened the deferred mine report with a new video and requested reuse of the branch worked on by chat `01a15913-b559-7803-b29d-d29650ddbed4`. That bounded follow-up is recorded below. The broad investigation is incomplete; unresolved reports must not be described as fixed. Other unreproduced reports remain low priority and require a specific request. A general request to resume engine work does not reopen them. This handoff supersedes older next-step notes, but preserves their evidence.

## Workspace and delivery state before the console/release follow-up

- Repository: `/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/repo` (abbreviated **R** below).
- Runtime, packages and test outputs: `/home/llm2x/Documents/EI/local/scratchpad/original-parity-20261020/fsr-first-use-20261020` (**W**).
- Branch: `test/original-parity-expanded`; HEAD: `5d95878afc00dce5d4b569cd176cd20e30a1e89e`.
- The worktree contains extensive authorized modified and untracked source, native binaries, tests and evidence. Preserve it; do not reset, clean, overwrite or assume HEAD contains the fixes.
- `/home/llm2x/Documents/EI` itself is not a Git repository.
- Follow-up fixes are local. No new release, push, GitHub comment or issue closure was performed in this follow-up. Several externally open issues already have local fixes.
- `W/package/CursedLands.exe` was rebuilt after the redress texture-mod change. Staging in `W/game` and the export must be refreshed deliberately when source changes; do not assume all copies automatically track R.
- The segment before the stop request only read source and retained evidence. The subsequent mine-video follow-up added a rendered regression fixture, catalog registration and evidence; it changed no production source or binaries.

## Mine video follow-up — explicitly resumed 2026-10-21

- Continued in the existing `test/original-parity-expanded` worktree; the earlier dirty source and fixes were preserved. Of 465 source/native-library files compared with `W/game`, 464 match byte for byte and `ai.gd` differs only in comments. Reused the existing Windows export; its hash is retained in the evidence.
- New clip: `/home/llm2x/Downloads/баг-SnapYT.App.mp4`, SHA-256 `0269404463ae95d6ab015631d9d5c468c872194ee3f8cd18f8007cc2e82adc34`, approximately 15.93 seconds. The user is forwarding another player's report and has no further version/save/reload information; do not repeat that question.
- Matched the gate, plate, green passage and water to **CDoorY, object 4306, near (129.515, 135.658) in LiA gz24k**. The clip shows animation with very little apparent displacement; it does not expose enough timing information to establish a simulation, collision or display cause.
- New `tools/tests/mine_passage_presentation.gd` / catalog `commands/mine_passage_presentation_astral`: actual mine, full save/load with three independently saved party records, separate solo authority, group/follow orders, normal/accelerated speed, 20 FPS rendered frontend. All authored actors/scripts/obstacles remain; combat is neutralized and the gate is opened as controlled setup. Replicated and displayed movement and actual model-animation progression are measured separately.
- **101 movement/setup assertions pass on each platform.** Windows D3D12 under Wine exits without engine errors. Linux OpenGL exits 0 after the assertions but logs two 349,524-byte GL texture-leak diagnostics at shutdown; explicit test cache cleanup did not remove them. This is retained as an unresolved renderer diagnostic, not a clean Linux run or an established cause of the player's slowdown.
- **Severe slowdown remains unreproduced and unresolved. No gameplay fix is claimed.** The prepared party does not reproduce the reporter's equipment, wounds, spell effects, saved script state, graphics workload or hardware. The older three-hero timing fixture also did not verify distinct restored start positions; the new fixture does.
- [Detailed video evidence, captures, measurements and reuse commands](validation/regressions-2026-10-21/mine-video/README.md). Rejected setup attempts are recorded separately and are not treated as player defects. The next useful discriminator is the reporter's save and exact build/settings, if they become available.

## Resume scope: work grounded in engine findings

**Do not use the unreproduced bug backlog as the default work queue.** Prioritize an observed engine mismatch, an established source/binary behavior, or validation of an already implemented fix. Cite the source/native location and expected behavior before changing code. A coverage gap is not itself a confirmed defect, and a suspected cause is not an engine finding.

No additional unfixed gameplay defect was confirmed during the last read-only inspection or the mine-video follow-up. The new Linux renderer-shutdown diagnostics are qualified separately above. The remaining evidence-backed work is:

| Priority | Work | Engine evidence and scope |
| --- | --- | --- |
| 1 | Reconcile and validate the existing local engine fixes when development resumes. | Original comparisons and before/after records exist for spell provocation/size effects, objective completion, mechanism permissions, movement-byte rounding, future-position queries, clocks and co-op quest handoffs. Preserve the fixes, check staged/exported source consistency, and run checks appropriate to any integration change. Do not rerun all passing suites without a reason. |
| 2 | Close a bounded original-code comparison gap in AI warning delivery if further comparison work is resumed. | Original hit/help functions and delayed warning semantics have been located. The current native dispatch fixture hooks the notification, so it does not qualify recipient selection or queue delivery. Compare those engine operations directly before deciding whether a change is needed. This does **not** authorize chasing the unreproduced #64 whole-scene report. |
| 3 | Add further original/LiA comparisons only when a specific engine operation lacks independent qualification or shows a discrepancy. | Use the retained native evidence, executable hashes and installed scripts. A useful result is a demonstrated behavior or mismatch; do not manufacture new bugs from test counts or broadly expand reproduction attempts. No additional mismatch in legacy LMP clock switching has been established. |

Console basics and the expanded command surface are already implemented. Preserve the qualified syntax and authority checks. Additional command work should start from a specific original-engine function/behavior, not a generic obligation to keep adding commands. Enhanced `GodMode` mode 2 is currently unsupported and rejected; this is a documented limitation, not an uninvestigated regression.

Platform and publication requirements remain delivery constraints, not speculative bug investigations: current Windows tests run under Wine, Android helpers have no device qualification in this pass, and a future release must be exported from the actual integrated source. No new publication was performed or started here.

## Deferred reports — low priority, specific request required

**Do not automatically investigate, reproduce, fix, or add scene-specific tests for these items on resume.** Retain the evidence for a later explicit request naming the issue/scene. An open GitHub issue, an older broad request, or a general instruction to continue is not a reason to reopen this deferred queue. These reports remain unconfirmed/unresolved; they are not declared fixed or dismissed.

| Deferred item | Current evidence / limitation |
| --- | --- |
| Host camera after talking to Zako | Existing topic, initiator/closer, journal and direct-control checks pass; no freeze reproduced. Tests force focus and call camera handlers directly, so they do not establish all viewport-input behavior. The worker test covers the bz18h ending, not the exact bz14h Zaku S64 conversation. These are test limitations, not an identified freeze cause. |
| Exact ally-alert encounter, #64 | The confirmed missing non-damaging-spell notification has been fixed. Prepared encounter checks pass. The reported whole scene has not been qualified against the original; do not infer a remaining defect from the video alone. |
| LiA mine and slowdown, #47/#62 | Explicitly revisited with the new video: matched CDoorY / 4306 in gz24k and added rendered group/follow controls through that gate. Slowdown remains unreproduced; see the bounded follow-up above, including the Linux shutdown diagnostic. |
| Village camera, #61 | Default orbit retention and the optional authored .cam transform checks pass. The exact report remains unqualified. |
| Remaining jumping shadows / blinking particles | Shader-buffer exhaustion is a confirmed fixed fault. Other reported maximum-settings Windows motion artifacts are not demonstrated by that finding. |
| Audible “Подслушать разговор” scene | Quest progression is covered. No explicit speech was found at the inspected script/audio step; audible original playback remains unverified. Do not invent missing dialogue. |
| Border-fog adjustment | The 16 m quadratic versus 32 m linear visual audit is complete; production is unchanged. A visual difference alone is not a confirmed engine defect. Further tuning needs a specific request. |
| Other unqualified external reports | Previously seen open issues include #60 animations, #59 ping, #57 scroll-to-bottom, #53 item cells, #48 the older release report, #45 frog spit, #42 order delay, #29 footprints and #20 pause frame. They are references, not an active task list. Revisit only on a specific request and establish engine evidence first. |

#63 menu exit, #65 basic GodMode and #66 redress mods have local changes and checks. Their external open status must not be confused with proof of remaining engine failures; no remote closures were made in this follow-up.

## Latest user clarification: the Portal torch

The user confirmed **quest accepted, both host and client had no hand icon**. This is covered by the existing local fix, not a new unresolved precondition question.

The original paid-rumour conversation hands its completion to a durable quest flag through a delayed watcher. A co-op catalogue refresh could erase the transient completion first; leaving the map before the next poll could also strand it. The fingerprint-qualified compatibility code commits/recovers that handoff while leaving the original `Raja`/`TorchBase` scripts in charge of permission and entrance activation.

- Production: `game/src/game/script/story_astral_fortunes.gd` and its existing integration.
- `tools/tests/astral_torch.gd`: actual torch mesh picking, hand cursor, ENet use command, approach/use animation, original unlock script and one-shot behavior; separate fresh host and guest runs, **17 checks each**.
- `astral_fortune.gd`, `astral_paid_topics.gd`, `astral_paid_topics_coop.gd`: the paid dialogue and other rumours, both purses and timing boundaries.
- Evidence: [visual follow-up](validation/regressions-2026-10-21/followup/index.html), `torch-host.json`, `torch-guest.json` and six before/available/activated peer images in that directory.
- Do not re-run the same torch fixtures solely because this clarification arrived; use a new failing save or sequence if further investigation is needed.

## Completed local work to preserve

The visual report and its per-run records are authoritative for precise scopes and counts. Completed areas include:

- Attacker retention after ranged hits; restoration of context-sensitive E self-cast and its hint.
- Arhar first-attempt purchases using the actual buyer's purse; LiA trade/party ownership and co-op dialogue staging.
- Alt-target selection, right-button hold to lower stats/skills, curse placement/presentation and ending audio handling.
- Eavesdrop quest recovery when speakers die; fingerprint-qualified trigger fixes; an intentional LiA challenge-reward addition.
- Non-damaging spell provocation, lasting Enlarge/Shrink effects, finished-item names in the wiki, and mechanism permission consumption/reset/reload behavior.
- Original objective-chain timing/completion, movement-byte rounding, movement-based future-position queries and independent campaign/scene clocks.
- Full town-save continuation: both original loaders use mission-save state for field **and town**; preserve clocks on a full town reload. **178 assertions** across Linux and Windows-under-Wine base/LiA runs. Deliberately failing negative copies are test controls, not production.
- FSR initialization responsiveness, independent frame generation, presented/rendered FPS reporting, integrated Screen settings and capability guidance. The cold preparation work can still take time; the fix keeps frames progressing. AMD FSR 4/native Windows behavior is not fully qualified by the RTX/Wine checks.
- Original-style console and EN/RU/DE help; base GodMode comparisons with both executables.
- Most recent implementation: `redress.res` texture packages through the existing overlay system, API 1/2/3 manifest acceptance, converter support and localized validation. Three baseline acceptance failures were reproduced before the fix. **255 runtime assertions** across the selected new/existing runs pass, plus converter/runner checks and translation coverage. Source archives stay unchanged. See `W/redress-handoff.json` and the visual report's `#redress-mods` section.

## Why regressions appeared

The inspected history **does not support a general claim that merging old mod data overwrote these fixes**. The formula merge `4118bbc7` adds guarded hooks and does not replace the implicated AI, input, wiki, briefing or original map-script files; the no-mod/formula suite passes 106 assertions. This is bounded evidence, not proof that every mod combination is safe.

Known origins are mixed: the patrol-escape change `0bb29c2e` introduced attacker forgetting; direct-input refactor `f2bad5e8` lost self-cast priority; several spell, objective, mechanism, movement and clock mismatches date to early October reconstruction; co-op exposed races/ownership assumptions in original single-player flags. Some old tests repeated the implementation's assumptions rather than independently checking the original. Keep native comparisons and complete multi-step player actions separate in reports.

## Retained engine findings and comparison boundary

`original_spell_alerts.py` executes the original dispatch/hostility branch but hooks AI notification. Retained base/LiA evidence identifies hit hooks `0x5d7e90` / `0x51bee0`, help callers `0x5d5990` / `0x51bb30`, and hostility functions `0x455680` / `0x427620`. The next bounded engine comparison can cover help recipients, queue replacement and delayed delivery; no additional mismatch has yet been demonstrated there.

The native hostility function propagates to an actor's party/group. Remake `_hate` explicitly updates all units sharing a nonnegative controller. These facts do not establish a missing NPC-group feature; the prior speculative group hypothesis is not an active task.

Retained original dossiers: `R/../issue64-analysis/original-base-evidence.json`, `original-astral-evidence.json`, `original-astral-effects-evidence.json`. Reuse matching evidence rather than re-analyzing identical functions. The report video and samples in that directory are deferred scene evidence, not grounds to automatically resume reproduction attempts.

## Evidence and how to resume

- Main current report: [followup/index.html](validation/regressions-2026-10-21/followup/index.html); `checks.json` records individual runs and limitations. It now records 151 final programs: 150 clean results and the Linux mine control with two renderer-shutdown diagnostics. These are not counts of independently fixed bugs; the two new mine programs pass their movement assertions without reproducing the reported defect.
- Fog: [fog/report.html](validation/regressions-2026-10-21/fog/report.html).
- Earlier report: `docs/validation/regressions-2026-10-21/report.json`. Some fields, especially its console estimate/status, are historical; use the newer follow-up and this handoff.
- Scratch handoffs: `W/redress-handoff.json`, `W/campaign-clock-handoff.json`, `W/town-load-handoff.json`.
- Original base executable: `/home/llm2x/Documents/EI/inspection/extracted/app/game.exe`, SHA-256 `d0fc0bb2acf45f0e59fae89e55c16a59848ffa89fb68feee9f298a680b660ad8`.
- Original LiA executable: `/home/llm2x/Documents/EI/inspection/lost-in-astral/game/game.exe`, SHA-256 `f04a305b77c84ea29c18ad2996d23072ccef1c0c46876c9b93bae4ce9351d1ff`.
- Native replay Python with Unicorn: `R/../venv/bin/python`. Address maps must stay qualified to those hashes.
- `python3 W/test_linux.py SUITE UNIQUE_TAG headless|opengl3 [extra arguments]` uses an isolated profile and R's test script against W's staged game.
- `python3 W/test.py SUITE UNIQUE_TAG headless|d3d12|opengl3 [extra arguments]` tests the exported Windows package under Wine. Export with `python3 W/export.py` after staging relevant source.
- Standard registration/catalog runner: `R/tools/parity/gameplay.py`; catalogs are `gameplay_catalog.json` and `player_features.json` beside it. Use fresh output directories and inspect parse errors promptly instead of waiting for the timeout.
- Never stage `W/town-load-negative-source` or other deliberate negative copies over production.

## Constraints and latest state

- No subagents/delegation. Follow root and repository `AGENTS.md`.
- Every changed player-facing string needs EN/RU/DE, including dynamically selected options and help.
- All development/test profiles: `confine_mouse=0`, `show_fps=1`, `volume_sfx=0`, `volume_stream=0`, `volume_voice=0`. Keep normal player preferences untouched.
- Native computer-use APIs are disabled. Historical original-game X11/Win32 helper scripts are evidence, not authorization to bypass that restriction. Programmatic original-code fixtures remain available.
- The most recent browser refresh/navigation attempt was blocked by the browser protocol policy. Do not retry the same outcome through another surface/raw API. Saved reports and native captures are available, but do not claim a new browser preview was verified.
- The previous stop check found no active game, test or native-analysis processes and shut down the owned static report server on `127.0.0.1:8764`. The mine-video follow-up did not restart that server or attempt the blocked browser preview.
- At the end of the mine-video follow-up, its frontend/authority/test processes had exited. Video and source hashes, retained result counts, evidence links, catalog registration and whitespace checks were verified. Unrelated application processes were left alone.
- The user's later request resumed the mine investigation in the existing branch. This follow-up preserves a reusable control and the new location evidence; the external slowdown report remains unresolved. Other deferred scenes are still outside scope. No release, push, issue comment or closure was performed.

## Console and release follow-up — completed 2026-10-21

The user subsequently requested a modern testing console and explicitly authorized pushing and publishing the combined work from this branch and chat `01a15913-b559-7803-b29d-d29650ddbed4`. That request supersedes the earlier no-publication state above. The new console extends the existing host/VM path with completion, syntax highlighting, persistent history, localized help, output search and diagnostics, and bounded testing shorthands. See [console guide](console.md) and [1.21.0 validation](validation/release-1.21.0-2026-10-21.json). The unresolved mine finding and other deferred scenes remain qualified as above.

Published [1.21.0](https://github.com/TheWWWorm/CursedLands/releases/tag/v1.21.0) from immutable tag commit `d060ac6a303d0fa3b457d2680c4508d0b1da6910`, with game tree `69d17159b036ec9485a795c64243f3458c35532d`. The integrated branch and `main` were pushed. All 11 public asset downloads match the export hashes. The [hosted browser](https://cursedlands.wwworm.com/) serves the committed release; all 22 checked assets and isolation headers pass. Fresh startup, previous-cache upgrade with preserved IndexedDB data, and public wiki EN/RU/DE plus Back/reload were verified. Receipts: [publication](validation/release-1.21.0/publication.json), [deployment](validation/release-1.21.0/deployment.json), [browser update](validation/release-1.21.0/browser-cache-upgrade.json), [wiki](validation/release-1.21.0/wiki-browser.json).

At the user’s explicit request, fully resolved issues #63 (menu exit), #65 (console/GodMode), and #66 (redress mods) were commented exactly `fixed in 1.21.0` and closed. [Closure receipts](validation/release-1.21.0/issues.json) include the verified comment URLs and states. Other deferred or partially resolved reports remain open. Later delivery-record commits do not change the published tag, game code, or artifacts.
