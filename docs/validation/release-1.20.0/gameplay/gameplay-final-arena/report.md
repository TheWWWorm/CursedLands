# Gameplay test report

**Remake regressions and original-executable comparisons are separate evidence.**

Overall status: **passed**.

Completed 1 of 1 selected programs.

| Category | Programs | Passed | Failed | Errors | Completed checks |
|---|---:|---:|---:|---:|---:|
| arena | 1 | 1 | 0 | 0 | 12 |

## Program results

| Program | Status | Checks | Failed checks | Log |
|---|---|---:|---:|---|
| `arena/arena_shadow_surface` | passed | 12 | 0 | [log](tests/arena/arena_shadow_surface/run.log) |

## Scope

1 configurations requested a real OpenGL renderer on a private display; the remaining configurations run headlessly. Rendered checks qualify only their specific UI/pixel assertions, not overall visual quality or other rendering backends. Sound output, a full ordinary campaign playthrough and external Internet play are not validated. C++-versus-GDScript checks compare two remake implementations.

Each program runs in a fresh process and isolated muted profile. Runtime source hashes and required-asset hashes are retained. No failure is automatically approved.

Run `reproduce.sh NEW_OUTPUT_DIRECTORY` to repeat this selection against the current source.
