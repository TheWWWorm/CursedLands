# LiA story and Кель rescue checkpoints — 2026-10-23

The existing gameplay and original-save comparison runners now include the
story leading to Кель's rescue, all three Rod of Life fragments, and the rescue
itself. Cheats supply declared prerequisites and shorten travel; ordinary
dialogue, item, mechanism, quest and travel handlers decide the measured result.
These are linked, bounded checkpoints, not an uninterrupted campaign playthrough.

**Result: all ten gameplay programs pass, with 1,062 checks. All nineteen native
references repeat consistently; eighteen match completely and one reports the
spent-fragment inventory difference described below.** Every native quest-state
delta, destination, money reward and party-presence observation matches. See
the [machine-readable evidence summary](lia-kel-checkpoints-2026-10-23.json).

Run [the single LiA command](../original-checkpoints.md#run-the-lia-quest-checks)
to repeat the ten gameplay programs and nineteen independent original-save
references. Each original reference runs twice in fresh muted profiles and
retains remake saves, observations, logs and hashes. The remake receives no
expected original results. The native comparison still returns failure for a
remaining inventory difference; it is not waived or reported as a match.

## Gameplay coverage

| Program | Checks | Coverage |
| --- | ---: | --- |
| `lia_kel_prologue` | 152 | Fresh opening, first portal key, prison, class/night gates, Kel joining, barriers, pursuit, catacomb lift/clothing and Shelter arrival; four save/load continuations. |
| `lia_kel_early_story` | 122 | Portal's early dialogues and prerequisites, coconut collection, Raja/cellar combat objective, trader key and document chest. |
| `lia_kel_torch_cellar` | 71 | Actual torch use, cellar entry, both ordinary return exits, save/load and presentation/authority consistency; closed/modified-map and retained-world particle controls. |
| `lia_kel_suslanger` | 106 | Required conversations, correct and incorrect lever orders, first fragment, rewards, revisits and save/load. |
| `lia_kel_gipat` | 114 | Tomb prerequisites, mechanisms, second fragment, rewards, revisits and save/load. |
| `lia_kel_ingos` | 149 | Water/mine prerequisites, blockers, mechanisms, third fragment, rewards, revisits and save/load. |
| `lia_kel_departures` | 84 | First fragment carried to Gipat; actual later death cinematic, archived character, belongings and return without premature revival; a default-party companion cannot impersonate the archive. |
| `lia_kel_handoffs` | 95 | Gipat → Ingos → Jigran, authored duel and later party change; earned fragments survive each transition and save. |
| `lia_kel_rescue` | 142 | All three missing-piece branches, synchronized and unsynchronized inventory fixtures, actual ritual/reunion, one living Kel, archived stats/equipment, topic recalculation and save/load. |
| `use_callback_orders` | 27 | Interaction completion preserves replacement orders and handles removal/party changes. |

An additional retained pre-fix trapped cellar save was exercised separately:
both returns recover without a story reset or a new save marker. It adds eleven
optional assertions in the earlier 66-check cellar run, all passing. The final
71-check portable run also includes the five retained-world presentation guards.

## Independent patched-original references

Official Russian patches 1.01 then 1.02 were applied to an isolated owned LiA
installation. All seventeen patched-file hashes were checked in both the
reference installation and the private Wine runtime. Actual `game.exe` SHA-256:
`9ecd475f5776681b8ffe1a8bb05cf67fe7adcceb62d0949135261ed7d3616c12`.
The base executable used only to decode saves is separately identified in
every reference. No original binaries, maps or saves are added to the repository.

The nineteen references cover slave-camp entry, the torch, cellar entry and both
ordinary exits; Raja, six coconuts, trader key and documents; the Suslanger
puzzle and each fragment reward; the complete death cinematic with explicit
final mercenary-topic recalculation; each missing fragment, successful rescue,
and reunion. Checks compare exact changed quest flags, exit gates, destination,
money, item/lever probes and party presence. Missing zero-valued transitions
cannot pass. Clock and zone bookkeeping are excluded; the capture nonce is an
explicitly declared recording diagnostic.

Fixtures reconstruct the original before-state, including party membership,
physical lever history and named-party inventory synchronization. Native
`RecalcMercBriefings()` is recorded explicitly where used. The untouched
death-scene capture is retained locally: Kel is already absent on return;
the explicit recalculation only changes his generic "nothing to say" flag.
Native rescue/reunion recordings start the authored briefing through the
console's `SendStringEvent`; the remake replay additionally requires the NPC
to offer that topic through the ordinary dialogue path. Fragment and combat
references identify direct state/kill operations as cheats. Both native cellar
return references use real ground clicks and the exit confirmation.

## Repairs and remaining differences

The stock Portal torch can open the cellar while the parent region flag is
still `1`. Both original return exits reject that flag. The remake now permits
both returns only for the recognized stock Portal/cellar script hashes and
matching passage geometry after the torch has opened the cellar. Quest and
region flags are unchanged. Modified maps and unrelated closed exits retain
their own gates. Exit hover, labels, particles, the objectives panel and actual
travel use the same availability decision.

Interaction callbacks can replace the current order or remove the actor.
Completing the old use action no longer overwrites that replacement. The
original death scene also removes Kel's persistent active-party record;
the remake now performs that removal for the exact stock scene, keeping the
archived record for the later rescue. Named active-party companions are
recognized when generic mercenary dialogue topics are recalculated.

One original/remake inventory difference remains deliberately visible. With
all three fragments synchronized into the original named-party bag before the
ritual, original `AddLoot` restores all three spent fragments. The remake's
global quest inventory consumes them. Both versions complete the ritual,
restore one living Kel and allow the reunion. Each missing-piece branch keeps
the other two fragments and refuses resurrection in both. Faithful native
stored-bag versus live-bag semantics require a broader inventory change; this
qualification does not claim that equivalence. The strict native reference
retains the original's three item observations and reports the difference.

The authored Ingos water completion also sets `q.gz22k.fq17` but calls the
`fq18` reward. That original content inconsistency is preserved and documented
by the tests; it does not prevent the fragment route from completing.

## Validation boundaries

Python comparator/runner controls include a missed `1 → 0` transition,
incomplete/duplicate output, wrong destination, non-finite data and malformed
actions. Engine negative controls prove that an unknown action or a mutating
or random probe cannot manufacture a passing comparison. Valid dialogue,
explicit script and clock fixtures still pass. Reproduction preserves source
paths and timeouts, and output inside the source tree is rejected.
The complete Python test run reports 167 tests, with one documented skip and
no failures. The final archive/particle guards were validated by rerunning the
two affected gameplay programs; the native death reference was also rerun.

The new programs run headlessly on Linux Godot 4.7. Original captures ran in
Wine 11.20 on a private Xvfb display; that session was shut down afterward.
Profiles use free cursor, FPS enabled, zero SFX/stream/voice volume and Dummy
audio. Normal player saves and settings were not used. No release is published.

Existing surrounding regressions were checked separately. Direct interactions,
the LiA tomb exit and travel command lifecycle in both campaigns pass. Three
older bounded base-game mercenary comparisons still differ, and the existing
co-op party-switch fixture ends before its required summary. Both issues
reproduce unchanged on the unmodified base checkout; they are not claimed as
passing coverage for this change. No overall co-op, audiovisual, platform or
complete-campaign equivalence is implied.
