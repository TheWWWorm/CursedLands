# LiA party quest-inventory correction — 2026-10-24

This follow-up resolves the two strict original-inventory differences recorded
in [the campaign qualification](lia-campaign-checkpoints-2026-10-23.md).
The original checkpoint manifests and their expected results are unchanged.

| Checkpoint | Original result | Corrected remake result |
| --- | --- | --- |
| `lia_campaign_shaina_return` | `HaveItem(0,8) = 0` after returning to FSusel | Samples remain in Shaina's stored bag; the subsequent ordinary `brief_24` gives them to FSusel. |
| `lia_kel_rescue_all_fragments_synced` | `HaveItem(0,101/102/103) = 1/1/1` | The ritual consumes the live fragments, then `AddLoot` restores the earlier stored fragment set in Jigran3. |

## Inventory behavior

`CampaignState.quest_items` is the live inventory. `party_quest_items` stores
named-party snapshots, and `quest_party` identifies the loaded quest bag.
`current_party` selects the next roster. Selection alone does not change the
live quest bag. Actual travel and `RedeployParty` collect the loaded inventory
and deploy the selected snapshot. Saving and loading preserve both inventories
without performing this collection.

`CopyLoot` and `AddLoot` read and write stored quest bags, even when a named
party is currently selected or deployed. Copying between different parties
preserves the source. Native `CopyLoot` to the same resolved bag clears its
stored items before reading the source; unknown-name aliases follow the same
rule. This also corrects the ordinary-item self-copy edge case. Live quest
items remain untouched by these operations until collection/deployment.

Co-op progress carries the live bag, archives and loaded identity in each
eligible player's resumable context. Deployment does not become a false
acquisition/removal credit. A complete context takes precedence over stale
cumulative quest-item credits. Checkpoint receipts include the archived story
inventory, and network state includes both party identities.
An absent empty archive and an explicitly stored empty archive compare equally;
every nonempty archive and the loaded owner still participate in checkpoint
matching. Partial credits can update only the matching loaded party.

Older saves retain their existing live inventory. Migration seeds only the
known active party's snapshot; it does not invent historical inventories for
inactive parties. Existing partial co-op contexts remain readable. This cannot
reconstruct archive history that an older build never saved or retroactively
recover fragments already lost by an older completed rescue.
When a legacy co-op context adopts another party, its global live inventory
adopts that party as its loaded owner. The next real collection therefore
keeps its earned items; applying the context does not refresh archived bags.

## Original evidence

The retained original target is official LiA 1.02, executable SHA-256
`9ecd475f5776681b8ffe1a8bb05cf67fe7adcceb62d0949135261ed7d3616c12`.
The prior native experiment supplied an item, saved, copied to a fresh party
and redeployed: the destination lacked the item. Returning to the source kept
it. Repeating with real same-zone travel before copying transferred it.

Static corroboration identifies named lookup `0x460020`, live give/erase
`0x58ef20` / `0x58f0e0`, collection `0x4edac0` / `0x4e73d0`, loaded-party
storage `0x4621b0` / `0x461fb0`, and selected-party loading `0x4613d0` /
`0x461260`. Dispatcher `0x4712c0` distinguishes `SetCurrentParty` (`0x9c`),
`CopyLoot` (`0xcb`), `RedeployParty` (`0xd3`) and `AddLoot` (`0xe0`).

Local retained provenance:
`local/scratchpad/lia-kel-checkpoints-20261023/native-party-loot-notes.md`,
`native-party-loot-evidence.json`, and
`original/experiments/native_transfer_unique/operations.json`.

## Validation

Detailed counts, hashes, retained logs and replay commands are indexed in
[results.json](lia-party-inventory-2026-10-24/results.json). Runs use isolated,
muted headless profiles with a free cursor and FPS enabled. No player profile
is modified, and these inventory checks require no GPU rendering.

The latest passing evidence for each selected case has these totals. The
groups overlap; the distinct-program row counts each gameplay ID once.

| Selection | Programs or references | Checks | Result |
| --- | --- | --- | --- |
| LiA campaign checkpoints | 34 programs | 7,771 | Pass |
| Surrounding party, base and network regressions | 21 programs | 1,615 | Pass |
| Co-op and transport selection | 18 programs | 530 | Pass |
| Distinct gameplay programs | 61 programs | 9,508 | Pass |
| Original-reference comparisons | 39 references, two replays each | 2,798 | 39 matches; all repeatable |

The complete co-op batch passed 18 programs and 525 checks. The final legacy
loaded-owner correction then passed its expanded 45-check fixture and both
campaign context cases, 148 checks. Those three later results replace their
earlier rows in the per-case totals above. The corrected handoff, dependent
ownership and state fixtures pass 95, 23 and 24 checks respectively. Initial
failures remain indexed with their original logs.

Two long outer runners were interrupted before their final reports. The
remaining LiA cases and six original references ran in new evidence directories.
For the other 33 native reference pairs, recovery verified the complete result
records, clean-exit traces, declared fixtures, before/after saves, strict state
and probe comparisons, and repeatability. Their individual child exit codes
were not retained and remain null in the index. All 39 oracle files are
byte-identical to `a5d4472e`; raw and normalized JSON hashes are recorded.

This is an aggregate of explicitly hashed snapshots, not one all-cases run on
the final source. The retained offline campaign runs predate co-op-only changes;
the handoff uses its corrected targeted rerun. The final legacy co-op fallback
is covered by the three later targeted cases described above.

The Shaina gameplay route checks absent samples after the return and after
reload, the actual hand-in grant and the Elder's consumption. Kel's route
checks all three missing-fragment branches, the synchronized and unsynchronized
complete sets, archived character restoration, once-only party membership,
reunion and full save/reload. Separate tests cover deferred selection,
stale snapshots, source/destination aliases, legacy migration, co-op ownership,
network transport and repeated progress packages.

Declared checkpoint fixtures now deploy their starting party before supplying
previously earned prerequisite items. This establishes the recorded input
state; it does not change expected native observations or assign quest outcomes.

The broader co-op run also exposed two stale fixtures that fail identically at
the pre-fix `a5d4472e` baseline. The Nalo test inspected a transient travel queue
after the VM had already dispatched it; it now waits for the actual authored
arrival on both peers. The dependent test expected guest ownership of Kel,
although the existing LiA story-companion policy keeps Kel with the host. It
now checks that ownership alongside the guest's animal through replacement,
travel, network replication and reload. No production ownership or travel
behavior was changed to satisfy these fixture corrections.

These are bounded quest and inventory regressions using the shipped handlers
and independently captured original outcomes. They are not an uninterrupted
playthrough, exhaustive gameplay testing, or a claim of parity for every native
zone-specific quest-item filter. The earlier campaign report retains its
historical counts and failures; this follow-up records their resolution.
