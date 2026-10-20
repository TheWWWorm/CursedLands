# Gameplay test report

**Remake regressions and original-executable comparisons are separate evidence.**

Overall status: **failed**.

Completed 3 of 3 selected programs.

| Category | Programs | Passed | Failed | Errors | Completed checks |
|---|---:|---:|---:|---:|---:|
| dialogue | 1 | 1 | 0 | 0 | 42 |
| inventory | 1 | 0 | 1 | 0 | 41 |
| spells | 1 | 1 | 0 | 0 | 17 |

## Program results

| Program | Status | Checks | Failed checks | Log |
|---|---|---:|---:|---|
| `spells/spell_requirements_coop` | passed | 17 | 0 | [log](tests/spells/spell_requirements_coop/run.log) |
| `dialogue/dialogue_highlights` | passed | 42 | 0 | [log](tests/dialogue/dialogue_highlights/run.log) |
| `inventory/coop_loot_network` | failed | 41 | 1 | [log](tests/inventory/coop_loot_network/run.log) |

### inventory/coop_loot_network

Failed assertions:

- FAIL each player receives one corpse pickup notice at 1.0x race=false

## Scope

0 configurations requested a real OpenGL renderer on a private display; the remaining configurations run headlessly. Rendered checks qualify only their specific UI/pixel assertions, not overall visual quality or other rendering backends. Sound output, a full ordinary campaign playthrough and external Internet play are not validated. C++-versus-GDScript checks compare two remake implementations.

Each program runs in a fresh process and isolated muted profile. Runtime source hashes and required-asset hashes are retained. No failure is automatically approved.

Run `reproduce.sh NEW_OUTPUT_DIRECTORY` to repeat this selection against the current source.
