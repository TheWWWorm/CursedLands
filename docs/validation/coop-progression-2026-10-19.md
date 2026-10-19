# Shared campaign checkpoint recovery

Local validation on 2026-10-19, using the supplied original-campaign save pair
and isolated profiles. No original save or archive was overwritten. This is
not a published release or a Windows runtime acceptance result.

## Findings

The host's quicksave contains 31 persistent maps; the friend's latest generated
co-op save contains 24, despite both listing 31 visited locations. Seven map
snapshots are absent from the guest copy. The host's continuity record is marked
unclean, so later packages correctly avoid moving an independently divergent
campaign but consequently cannot repair this already divergent pair.

The save history also exposes an identity error: a partial progress package can
copy a live network actor's `unit_name` into the independent protagonist. The
friend's save contains `Geagon` where the original protagonist expects `Hero`.
That causes subsequent authored-role checkpoint comparisons to fail. A missing
`unit_name` now continues to mean the default authored protagonist, rather than
accepting the network alias. Explicit expansion chapter identities are preserved.

A second regression occurs when the host reloads a normal save made before the
guest's final progress flush. The guest's newer acknowledgement can contain
later shared story flags, so the old equality check treats the return as solo
divergence. Complete shared packages now record consistency digests for story
and persistent world state. An unchanged acknowledged source can resume the
host's recorded shared checkpoint, including removals, while keeping the guest's
own skills, equipment and purse. These digests are continuity checks, not
authentication. New solo quests, visits, location changes, quest items or
persistent kills/loot invalidate the receipt.

## Tests

| Check | Result |
| --- | --- |
| Shared-checkpoint and partial-identity regression | 25 checks, no failures |
| Actual ENet host save, final guest flush, host reload and guest return | 24 checks, no failures |
| Independent solo-return guards | 18 checks, no failures |
| Original fresh-start guards | 76 checks, no failures |
| Progress-travel guards with Lost in Astral assets | 15 checks, no failures |
| Private recovered pair: solo load, actual ENet rejoin, progression update, save/load | 26 checks, no failures |

The network regression retains a newer personal stat/gear/purse fingerprint
while rolling the shared story back to the host's deliberately selected save.
The original source slot remains byte-for-byte unchanged. The private pair
test additionally checks the saved arrival positions and original-script
lookup of the independent protagonist.

## Recovery copies

Separate host and friend copies were created outside the repository. They use
the host's Necromancers' Desert checkpoint and all 31 map snapshots. The friend's
latest personal attributes, skills, equipment, experience and inventory are
preserved, and the host's reserved guest retains the friend's lobby identity.
The repair normalizes only the proven erroneous protagonist alias in this pair;
it is not a generic migration of arbitrary named campaign roles.

Both copies were loaded through the game, joined over ENet, advanced with a
progress package and saved again. Automatic future receipt handling cannot
retroactively establish provenance for unrelated old saves.

Input SHA-256:

- Host quicksave: `2c670e0bfeffcc3f0945550befb093819169d45ce8f52862b525170ec20ffb07`
- Friend's latest co-op save: `04d9726ee4de0d856d91cc4af17d6551cd01a03f30e784112bcee2cb7a84123f`
