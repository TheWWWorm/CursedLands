# Gameplay coverage expansion — 2026-10-20

**45 additional test configurations passed 48,855 assertions.** Combined with
the 56 previously qualified configurations, the catalog now covers **101
configurations and 184,754 passing assertions across 14 areas**.

This includes two newly written regression programs: item-instance conservation
(run against both campaigns) and effect-duration boundaries. The other 42
registrations bring existing standalone programs into the isolated runner,
including campaign variants and distinct save/load scenarios. Transport and
fallen-companion tests now generate their own fixtures instead of requiring a
private save.

| Area | Configurations | Added | Passing assertions |
|---|---:|---:|---:|
| Quests | 15 | 2 | 569 |
| Creatures | 7 | 1 | 23,842 |
| Animation | 8 | 0 | 2,655 |
| Effects | 11 | 1 | 73,698 |
| Stealth | 6 | 0 | 3,046 |
| Commands | 8 | 2 | 1,284 |
| Pathing | 7 | 0 | 42,959 |
| Spells | 8 | 8 | 27,898 |
| Inventory | 9 | 9 | 3,425 |
| Progression | 5 | 5 | 345 |
| Party | 2 | 2 | 36 |
| Persistence | 9 | 9 | 122 |
| Combat | 3 | 3 | 4,624 |
| Network | 3 | 3 | 251 |

The [machine-readable record](validation.json) retains every selected capture,
script/helper hashes, log hashes, runtime fingerprints and negative controls.
[Runner documentation](../../gameplay-testing.md) describes commands, filters,
campaign requirements and report formats.

## What the additions check

- **Inventory:** 150 wear/charge combinations per campaign; repairs preserve
  spent charge, recharge preserves damage, edits commute, repeated operations
  do not duplicate value, and all copies survive disk saves. Existing repair,
  construction, exchange, unique-equipment and legacy-rune tests are included.
- **Spells and progression:** stamina waits and single acknowledgements,
  execution-time eligibility after training changes, paused crafting replies,
  seeded shop stock, refund/rank boundaries, XP distribution and downed Kel's
  earned XP through save/reload and revival.
- **Status effects:** signed counter endpoints, expiry on living/dead actors,
  client presentation versus authoritative removal, exact 32-bit save counters,
  the existing 16-bit snapshot representation, overlapping modifiers and
  legacy-duration migration.
- **Persistence and party:** pending paid casts, already-consumed potions,
  taming stages, pet references, hostility, wounds, frozen world time,
  alternating wall-effect checkpoints, substitute parties and guest ownership.
- **Combat, quests and transport:** authored ranged/melee/spell ranges,
  moving bow release, wounds and severance, lift cycles and separate storeys,
  dragon story timers, stale/reordered snapshots and large campaign documents.

## Qualification and fixture corrections

The first 42-configuration capture recorded 35 passes, one failed program and
six errors. The independent three-configuration matrix capture passed.
Focused reruns then qualified all seven affected registrations. Earlier raw
reports are retained unchanged; this record does not claim the first run was
green or that all 101 registrations were rerun in a single capture.

Four errors were incorrect catalog minima: the network stamina program has
four setup checks plus five checks for each of two control modes (14 total);
training reset performs 99 checks in each campaign; snapshot recovery has 18.
Their behavioral assertions were unchanged, and all four were rerun.

The remaining fixture repairs were:

- **Archer range:** `_perceive_next` did not suppress perception queried during
  attack rechoice. Ordinary patrols correctly abandoned targets outside their
  notice range. The range fixture now explicitly establishes hostility,
  notices the target and uses the existing scripted Aggression motivation.
  All 13 previously failing assertions pass, and 26 added precondition checks
  verify that setup. Separate patrol-escape tests retain ordinary behavior.
- **Body records:** a synthetic actor had no presentation adapter, but quiet
  snapshots also settle presentation. Supplying an empty adapter permits the
  production snapshot/body path to complete. No rendered behavior is claimed.
- **Unit-state lifetime:** deliberate script replacement re-ran initialization
  with old visibility signals still attached. The fixture now detaches those
  subscriptions before replacement while retaining the native record/lease
  whose invalidation is being tested. Normal gameplay does not perform this
  actor-script swap.

No behavioral assertion was removed, and no production game code was changed.
All 1,074 production files, selected test dependencies, engine binary and 21
declared required assets were rechecked. The original 56 configurations retain
their prior evidence because their production and test dependencies match.

## Negative controls and remaining differences

Both newly written programs were also run against a separate deliberately
damaged source copy:

| Injected defect | Detected failures |
|---|---:|
| Repair resets spent charge to zero | 200 |
| Authoritative effects expire one tick late | 9 |

The negative-control run correctly exited with failure; ordinary-source
versions pass. All **50 Python harness tests** also pass.

The independent original-executable suite remains at **425 matches and five
differences out of 430 scenarios**. These are the previously recorded unaimed
hit-probability cases. The original suite was neither expanded nor recaptured
in this change; its production source and parity tooling were checked unchanged.
No exemption or combat fix was added.

Assertion counts include parameter sweeps, not unique games or playthroughs.
These are headless gameplay regressions. They do not establish rendered-pixel
or audio fidelity, external Internet reliability, whole-campaign equivalence,
or ordinary availability of the directly exercised taming transition.
