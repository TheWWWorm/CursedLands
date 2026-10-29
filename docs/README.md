# Documentation index

The guides below describe how the engine works and how it is tested. Dated
files in this folder and everything under [`validation/`](validation/) are
investigation and validation records: they document one piece of work at one
point in time and are not updated afterwards.

## Playing and modding

- [Mods, profiles and game rules](mods.md), [formula mods](mod-formulas.md), [mod menus and options](mod-menus-and-options.md)
- [Legacy mod compatibility](legacy-mod-compatibility.md) and the [legacy mod converter](legacy-mod-converter.md)
- [Internet games](internet_games.md) and the [online Autochess](autochess-online.md)
- [Encyclopedia](wiki.md) (the public and in-game wiki)
- [Developer console](console.md)
- [Game library and Lost in Astral](campaign_library.md)
- [First- and third-person controls](experimental-third-person.md)

## Design

- [Trials of the Allods](arena-pve-design.md) and [Autochess](arena-autochess-design.md)
- [Reactive AI activity scheduling](ai_activity.md)
- [Graphics preparation](graphics-preparation.md) and [path-tracing qualification](path-tracing-qualification.md)
- Branding under [`branding/`](branding/) and design notes under [`design/`](design/)

## Testing

- [Focused regression checks](regression-checks.md): `tools/check_regressions.py` over the catalog's `focused` entries
- [Gameplay regression suite](gameplay-testing.md): `tools/parity/gameplay.py` and its catalog
- [Original-engine comparison suite](original-parity.md) with its families:
  [dialogue](original-parity-dialogue.md), [NPC AI](original-parity-npc-ai.md),
  [NPC commands](original-parity-npc-commands.md),
  [perception triggers](original-parity-perception-triggers.md),
  [quest commands](original-parity-quest-commands.md),
  [quest query](original-parity-quest-query.md),
  [quest scheduler](original-parity-quest-scheduler.md)
- [Quest checkpoints from original saves](original-checkpoints.md)
- [Wine and Proton development workflow](wine-proton-workflow.md)
- Asset-free checks and the contribution checklist: [CONTRIBUTING.md](../CONTRIBUTING.md)

## Releases

- [Versioning policy](versioning.md)
- Release notes under [`releases/`](releases/); the changelog is [CHANGELOG.md](../CHANGELOG.md)
- Android: [stability](android-stability.md) and [startup recovery](android-startup-recovery.md)

## Maintenance

- [Project review, 2026-10-28](project-review-2026-10-28.md): ranked open improvements (repository size, web build reproducibility, unregistered tests, runner drift, script-only platform lane, native provenance, UI scale, code structure)

## Records

Dated performance, checkpoint and handoff files in this folder (for example
`performance-*`, `portal-*`, `*-validation.json` and `*-2026-10-*`) and the
folders under `validation/` are retained evidence for past changes. Start from
the release notes or the changelog to find the record for a change.
