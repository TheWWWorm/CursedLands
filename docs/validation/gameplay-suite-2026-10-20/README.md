# Gameplay suite qualification — 2026-10-20

**56 regression programs passed 135,899 assertions.** They cover the seven areas below. The independent original-game suite has **425 matching and five differing scenarios**, with two identical captures per side and 1,124 observations per capture.

| Area | Programs | Passing assertions |
|---|---:|---:|
| quests | 13 | 514 |
| creatures | 6 | 12,018 |
| animation | 8 | 2,655 |
| effects | 10 | 73,495 |
| stealth | 6 | 3,046 |
| commands | 6 | 1,212 |
| pathing | 7 | 42,959 |

The [validation record](validation.json) identifies every program, campaign, tested script, source fingerprint and log hash. The [native scenario results](original-scenario-results.json) retain all 430 original-comparison outcomes. See [gameplay testing](../../gameplay-testing.md) and [original comparison](../../original-parity.md) for commands.

## Qualification method

A full 56-program capture was followed by focused reruns for corrected collector/fixture cases. These results are consolidated by program; this is not a claim that the first full capture was green. Production game files were identical in all captures. Every selected test script and its explicitly inherited helpers were checked against the current source. Required asset hashes and the pinned executable were rechecked after execution.

The first full capture retained six errors: three unrecognized summary suffixes, one incorrect minimum count, an uninitialized lever-census helper, and base-campaign prototype names in the expansion projectile test. All affected programs were rerun successfully. The base projectile suite was also rerun after sharing its fixture-record hook with the expansion variant. Raw reports remain unchanged.

## Fixture and collector corrections

- Assign each program its actual campaign and verify it at startup. Astral projectile tests now use explicit authored Astral actor names and the Portal Terror map template, reusing the base geometry/replay assertions.
- Preserve the normal `Main/Session` scene path when bootstrapping tests, so the separate solo simulation worker can communicate with its frontend.
- Apply synthetic guest hero stats using the correct owner before transferring control to the host in the group-lever fixture.
- Let the native 8–11 tick candidate cache expire after frozen-world fixture teleports/spawns. Update navigation occupancy and reset prior-phase suspicion before hearing checks.
- Test both ordinary patrol escape and scripted persistent pursuit. The earlier stealth expectation predated the intentional patrol change in stable 1.19.0 (`0bb29c2e`, documented in the changelog). Two extra patrol/quest programs cover that distinction.
- Initialize `LeverSystem` in the record-only census, which never performs ordinary map loading.
- Accept numeric summaries with their existing trailing metrics while still requiring a unique completion marker. Set the direct-interaction minimum to its eight authored checks (one setup, one mechanism lookup, four camera-mode checks and two exclusions). No behavioral assertion was removed.

## Harness and negative controls

All **50 harness tests pass**. They cover missing/duplicate/partial outputs, exact comparisons, campaign/profile mismatches, coverage minima, runtime errors, timeout cleanup, incomplete JUnit results, frozen selections, protected output paths and existing-result preservation.

A deliberate change from `_talk_posted == 9` to `_talk_posted >= 9` in an isolated game copy made `village_gate/current_0_posted_10` return true instead of the original false. Both repeated captures caught the first differing field and returned failure. The ordinary source matches that case. No production game code was changed.

## Remaining original difference and scope

The five original mismatches are the same unaimed hit-probability discrepancy recorded in the [initial qualification](../original-parity-2026-10-20/README.md). They remain failures; no exemption or gameplay change was added. All 304 newly added native scenarios match.

The suite checks prepared gameplay states, quest scripts, models, animation transforms, particle logic, network ordering and navigation. Counts include large parameter sweeps and comparisons between remake implementations; they are not games played. This qualification does not establish rendered-pixel fidelity, sound correctness, external Internet reliability, full-campaign equivalence or whole-game RNG order.
