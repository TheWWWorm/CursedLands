# Party pools across zone changes — 2026-10-29

Observed while measuring game speed after console `travel` round trips
(`speed_scaling_matrix`): the hero arrived in the next zone with full mana and
without the Eagle Sight buff. The in-process reproduction (`zone_change_pools`
before the fix) showed the hero record written on leaving holds `mana` and the
live effects (`body.magic`), but `CampaignState.apply_hero` restored only the
health on deployment; the global map's `_travel` and the console command share
`_enter_zone`, so both paths behaved the same.

## Original comparison (decompiled GOG English `game.exe`, ei-rebuild names)

- `CWorldServer::StoreParty` (`58fd90`) fills each party unit's record when the
  party leaves: items through `PartyUnitRecord::Add*` and the unit's whole
  stats block through `CUnitServer::CopyStats` (`553360`, a 0x704-byte copy
  from unit+0x1e0). No effect list is written.
- `CWorldServer::Redeploy` (`590700`) → `CreateUnits` (`58ef20`) →
  `CreateObject` (`5927c0`): a unit created from a record (case 5) receives the
  record through `UnitRecord::ApplyTo` (`477b00`), which writes the record's
  two pool fields (indices 4 and 5) into the unit's stats block (+0x208,
  +0x210) along with the other stats, and applies the item lists. The function
  skips the stats when both pools and the second field are zero (an empty
  record), which is the "fresh unit, full pools" case.

Confirmed: the party record carries the unit's stats block, not its spell
effects, and a redeployed unit gets the block back. Inferred: the current mana
is one of the two pool fields restored (the remake already restored the other
as health; the field-by-field layout of the stats block was not traced).

A run of the original under Wine was not performed: the original-executable
harness (`tools/parity/run.py`) has no zone-travel scenario, and a manual
play-through would show the pool only through the HUD. Remaining uncertainty:
whether the original clamps the restored mana to a maximum recomputed on
arrival; the remake clamps to `max_mana`.

## Fix and regression test

`apply_hero` restores `mana` next to `hp` when the record has one and the
unit is alive. `tools/tests/zone_change_pools.gd` (catalog
`party/zone_change_pools`, focused `zone_change_pools`) fails on the unfixed
tree with 3 of 8 checks (mana refilled after each zone change) and passes with
the fix; its spell-effect check documents the original's behaviour.
Evidence: `local/validation/review-followups-20261029/` on the workstation.
