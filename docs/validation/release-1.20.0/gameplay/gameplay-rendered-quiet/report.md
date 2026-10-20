# Gameplay test report

**Remake regressions and original-executable comparisons are separate evidence.**

Overall status: **passed**.

Completed 2 of 2 selected programs.

| Category | Programs | Passed | Failed | Errors | Completed checks |
|---|---:|---:|---:|---:|---:|
| animation | 1 | 1 | 0 | 0 | 13 |
| network | 1 | 1 | 0 | 0 | 35 |

## Program results

| Program | Status | Checks | Failed checks | Log |
|---|---|---:|---:|---|
| `network/menu_lmp_flow_ingos` | passed | 35 | 0 | [log](tests/network/menu_lmp_flow_ingos/run.log) |
| `animation/worker_response` | passed | 13 | 0 | [log](tests/animation/worker_response/run.log) |

## Scope

2 configurations requested a real OpenGL renderer on a private display; the remaining configurations run headlessly. Rendered checks qualify only their specific UI/pixel assertions, not overall visual quality or other rendering backends. Sound output, a full ordinary campaign playthrough and external Internet play are not validated. C++-versus-GDScript checks compare two remake implementations.

Each program runs in a fresh process and isolated muted profile. Runtime source hashes and required-asset hashes are retained. No failure is automatically approved.

Run `reproduce.sh NEW_OUTPUT_DIRECTORY` to repeat this selection against the current source.
