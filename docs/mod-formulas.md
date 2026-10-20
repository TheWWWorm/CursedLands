# Formula mods

**1.20.0 · package API 3 · formula API 1 · Windows/Linux x86-64**

This is an initial extension of the existing mod system, based on stable 1.19.0.
It supports small Lua 5.1 formulas over plain values. It does not expose Godot
objects, engine memory, original-game functions, DLL loading or DLL conversion.
Single player and campaign co-op are supported; original multiplayer, Android,
macOS and the browser cannot activate formula packages in this version.
Other documented mod types remain available on their existing platforms.

## Create a mod

Copy one of the examples:

| Example | What it demonstrates |
| --- | --- |
| [Expedition experience](../examples/mods/expedition-xp/mod.json) | A numeric setting and an experience multiplier |
| [Quest focus](../examples/mods/quest-focus/mod.json) | Declared modules, event context and ordering after another mod |
| [Field medicine](../examples/mods/field-medicine/mod.json) | Two hooks, bounded output and unit attributes |

Give the copy a new `id`, update its title/descriptions in all three languages,
and use a new version for every distributed change. Build it from the repository:

```sh
python3 tools/package_mod.py examples/mods/expedition-xp expedition-xp.eimod
```

Import the resulting ZIP-format `.eimod` from **Mods and rules**, enable it in a
named profile and restart. Profile saves are separate from original saves.
Existing compatible original saves can be copied into the mod profile.

The manifest retains the documented API 1 fields for overrides, patches,
dependencies and modes. Set `"api": 3` and add:

```json
"script": {
  "api": 1,
  "entry": "main",
  "modules": {"main": "main.lua", "rewards": "rewards.lua"},
  "hooks": ["experience_reward"]
}
```

`entry` is a module name, not a file path. `require("rewards")` reads only the
declared `rewards` module. Missing and cyclic modules fail. All declared hooks
must exist as global functions after initialization. Unknown hooks are rejected.
The module is ordinary UTF-8 Lua source; precompiled bytecode is rejected.

API 3 requires English `title`/`description` and this translation structure:

```json
"translations": {
  "ru": {
    "title": "Название",
    "description": "Описание.",
    "options": {"multiplier": {"label": "Множитель", "help": "Описание настройки."}}
  },
  "de": {
    "title": "Titel",
    "description": "Beschreibung.",
    "options": {"multiplier": {"label": "Multiplikator", "help": "Hilfe zur Einstellung."}}
  }
}
```

Each numeric option has an English `label` and `help`, plus matching RU/DE
entries. Use `type: "number"` or `"integer"`, `min`, `max`, `step` and `default`.
For a script-owned option, omit `binding`; the callback receives it under its
local ID in `options`. Bounds must be within ±1,000,000, steps at least 0.001,
and defaults must lie on a step. Boolean/enum controls are not part of this
preview. Existing `revival.seconds` and `revival.health` capability bindings
remain available with their existing bounds and conflict rules.

## Callback contract

Each function receives `(value, context, options)` and returns a finite number.
It has no other way to change the game. Every invocation creates a fresh VM,
initializes its declared source modules, invokes the function and discards the
VM. Globals, module tables, captured locals and modifications to input tables
do not survive. There is no persistent script state or random-number API.

All contexts also contain `campaign` (`cursed_lands` or `lost_in_astral`) and
`mode` (`single_player` or `campaign_coop`).

| Hook | Input and additional context | Allowed result |
| --- | --- | --- |
| `experience_reward` | Entire event reward before distribution, intelligence bonuses and death debt; `context.source`: `kill`, `quest`, `talk`, `side` | 0–1,000,000,000 XP |
| `revival_seconds` | Configured revival duration; `helper_intelligence`: helper's recorded intelligence before perk bonuses; `target_max_health`: current corpse pool | 1–30 seconds |
| `revival_health` | Configured revival health; `target_max_health`: refreshed maximum health including XP earned while downed | 1–1,000,000 HP, then capped at the target's maximum |

The experience hook runs once per nonzero reward event, not once per recipient.
The original party distribution and intelligence calculations still run after it.
Revival hooks run only when ordinary campaign revival is enabled and applicable.
Revival health is an absolute amount; the example converts a percentage to HP.
Hooks do not grant the ability to create units, execute commands, change UI,
replace quests, alter inventories, or intercept arbitrary engine functions.

Multiple mods can implement the same formula. Each receives the preceding
mod's result in resolved profile order. `requires` and `after` determine that
order; unrelated mods retain the profile's selected order. Distinct script-owned
settings never conflict merely because they share a local option ID. Existing
database-field and capability-binding conflicts still block activation.

Do not depend on table iteration order, printed function addresses or
cross-platform floating-point identity. The authority executes gameplay
callbacks; replicas receive their results through normal game replication.
Initialization validation also runs locally when activating a package.

## Saves, failures and limits

Script source bytes, metadata and declared assets all contribute to the
package fingerprint. Co-op requires matching gameplay fingerprints and effective
option values. Save loading restores the saved options; changing next-run
defaults does not alter an existing run. API 1 save/session envelopes remain
unchanged. There is no implicit script migration between source bundles.

A hook result is checked before its caller commits the event. A failed
experience chain awards no partial reward. Initialization errors refuse
activation. Runtime errors stop further simulation and commands, notify peers,
and block campaign saves and returned co-op progress. Existing save files are
not replaced. Return to the main menu before loading a valid matching save;
live repair of a stopped session is not supported. Diagnostic details go to
the game log; the player receives a translated failure message.

Limits:

- Eight formula packages per profile; 16 declared modules per package.
- One MiB per module and four MiB across the module bundle.
- 128 MiB total for API 3 packages; existing API 2 texture packs retain 1 GiB.
- Two million metered steps and a checked 200 ms deadline for each initialization
  and callback. String pattern matching also has metering and recursion bounds.
- 32 MiB VM allocation ceiling, with 4 MiB reserved for boundary handling;
  successful initialization is limited to 8 MiB.
- Bounded plain-data conversion; finite numeric hook outputs only.

Available libraries are restricted base functions, `math`, `string` and `table`.
There is no `io`, `os`, `debug`, `package`, coroutine, file loader, dynamic source
loader, bytecode loader or native-module loader. These bounds contain tested
mod mistakes; the embedded interpreter is not a claim of perfect isolation
against hostile code. Install code mods from sources you trust.

A fresh unmodded launch never loads the formula native library. An installed
but inactive script package is only inspected as data. Returning to the original
profile clears formula bundles; no callback VM runs on the ordinary path.

## Reused groundwork and next steps

The earlier Jamais Vu work supplied Lua 5.1 integration, memory/instruction
limits, bounded string operations, declared-source loading and plain-data
conversion. This version extracts those pieces into `ModLuaKernel`, adds
StringName-to-string conversion at the Godot boundary, and removes the old
native-address bridge, LuaJIT return coercions and checkpoint machinery.
It does not claim Jamais Vu compatibility.

Future capabilities should be added as explicit, independently testable hooks.
Likely follow-ups are training-cost formulas, broader data definitions and a
versioned explicit state API. These are proposals, not implemented features.
Persistent state needs a separate save/migration design; DLL conversion remains
outside the current work.

See [validation](validation/release-1.20.0-2026-10-20.json) for actual test coverage
and remaining platform limits.
