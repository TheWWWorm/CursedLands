# Mods, profiles and game rules

Available in **1.0.4 Experimental 1**, using mod API 1 and network protocol 14. Stable 1.0.3 does not include this feature.

Open **Mods and rules** above the main-menu signpost, from the multiplayer screen, or beside the in-game Esc menu. **Options → Remake → Mod options and rules** opens the same editor. New Game includes a rules review before the difficulty screen.

## Playing with a profile

1. Open **Profiles and mods** and create a named profile. Choose **Create sandbox profile** only if you want the sandbox commands.
2. Import a `.eimod` or `.zip` package. Importing installs it without enabling it.
3. Select the installed mods, then choose **Activate selected mods and restart**. To switch back, select **Current defaults** and use **Use selected profile and restart**.
4. Configure **Game rules** and **Mod options**, then select **Apply**. **Cancel / Back** discards pending edits. In a running game, edits affect that run; from the main menu, they set the next run's defaults.

Named profiles have separate campaign saves and original-multiplayer character folders. Current defaults keeps the existing save locations and reads legacy saves. The manager can explicitly copy an ordinary save into a named profile; its source is retained. A sandbox save or character cannot be loaded or imported into an ordinary profile through the game's save, backup or network paths.

Rules say when they can change: **New game**, **At camp**, or **Live**. Guests can inspect shared rules; the host controls them. Running changes are stored in the save, so changing next-run defaults does not change an existing campaign. Package activation and profile switching require the main menu and a restart.

In a sandbox profile, **Sandbox** offers invulnerable party, unlimited party mana, heal living party and give 1,000 gold. Actions run on the authority, including when the local game uses a separate simulation process. They are unavailable during loading or movies. Sandbox supports single player and campaign co-op; original multiplayer is excluded. Disabling a cheat does not remove rewards already earned.

Mouse, keyboard focus and controller navigation use the same controls. D-pad up/down moves focus, left/right changes a choice or number, A activates, Y applies, and B goes back. Controls are at least 44 pixels high and pages scroll on narrow screens. Desktop/Android use the native package picker; the browser uses a local file chooser.

## Co-op compatibility

Everyone needs network protocol **14** (this source revision). The host checks the mod API, campaign, sandbox classification, ordered gameplay package IDs/versions/content hashes and effective mod option values before admitting a player. Existing original-map checks and database synchronization remain in place. No package is downloaded automatically.

Built-in host rules, such as full XP or shared loot, are published to guests without changing their local defaults. Gameplay mod values must match when joining. Choose the same package versions and values in the menu before connecting. A continued host save supplies its saved configuration before the lobby opens; stop hosting to choose a different save.

Texture/audio-only packages are local presentation choices and do not have to match. Any package with options or database patches is classified as shared gameplay by the engine. Authors cannot bypass matching with a cosmetic flag. Dependencies and load order are part of the resolved configuration. Imported heroes and returned co-op progress must remain within a compatible gameplay profile. Existing built-in co-op XP/loot options retain their prior progression behavior.

## Building a data mod (API 1)

See the complete, asset-free [Quick recovery example](../examples/mods/quick-recovery/mod.json). From the repository root:

```sh
python3 tools/package_mod.py examples/mods/quick-recovery quick-recovery.eimod
```

The result is an ordinary ZIP with `mod.json` at its root. The packaging tool includes only the manifest and declared replacement files, with stable timestamps/order. The game performs authoritative schema validation on import and activation.

Required manifest fields:

| Field | Meaning |
| --- | --- |
| `api` | Integer `1`. |
| `id`, `version` | Stable lowercase identifiers, 1–80 characters; letters, digits, `.`, `_`, `-`. No leading dot or `..`. Installed `id@version` folders are immutable through the importer; use a new version for an update. |
| `title` | Display name, up to 100 characters. |
| `campaigns` | Nonempty list of `cursed_lands`, `lost_in_astral`, or both. |
| `description` | Optional plain text, up to 3,000 characters. |
| `modes` | Optional nonempty list of `single_player`, `campaign_coop`, `original_multiplayer`. Omission allows all three; revival providers should declare only the two campaign modes. |
| `requires`, `after`, `conflicts` | Optional arrays of other mod IDs. `requires` must be selected; `after` orders an installed selected mod without requiring it. Cycles and conflicts block activation. Choose one version of each ID. |

### Generated options

An optional `options` array contains up to 64 objects. Each needs `id`, `label`, `type`, `min`, `max`, `step`, `default`, and `binding`; `help` is optional. Options use a slider and numeric entry; `type` is `integer` or `number`. Steps must be at least `0.001`, bounds must fit the capability, and the default must be on a step relative to `min`. Stored keys are `mod.id:option.id`.

API 1 exposes these bounded capabilities:

| Binding | Unit and allowed range | Engine fallback |
| --- | --- | --- |
| `revival.seconds` | Seconds, 1–30 | 5 seconds |
| `revival.health` | Total HP after revival, 1–100, capped by the unit's maximum HP | 1 HP |

Both require the built-in revival rule and affect campaign revival only. They can change at camp. The package's declared default is used when no stored value exists. This release does not expose arbitrary callbacks, option-controlled database patches, per-mod script state, or custom widgets. Built-in rules already use the game's enumerated choices and on/off controls.

### Texture and sound overrides

An `overrides` entry maps an existing archive entry to a package-relative file:

```json
{
  "archive": "sfx.res",
  "entry": "tools/gate.wav",
  "file": "audio/my-gate.wav"
}
```

Supported archives are `textures.res` (MMP), `sfx.res` (game-supported WAV), and `speech.res` (MP3). Use forward slashes in archive entry names. Textures must use an entry ending in `.mmp`. Supply files in the formats the existing readers accept. The overlay is consulted by those readers and leaves the player's source archives intact. It is not a filesystem-wide replacement mechanism. New entries can be read by name, but automatic archive directory listings still enumerate original entries; use replacements for existing content.

### Numeric database patches

An optional `patches` array changes supported fields on existing named records:

```json
{
  "database": "campaign",
  "table": "monster_prototypes",
  "record": "Human Hero",
  "field": "hp",
  "value": 120
}
```

`database` is `campaign` (default) or `multiplayer`; multiplayer patches are applied when the original multiplayer database opens. Record matching is case-insensitive. Values must be finite, nonnegative and at most 1,000,000; integer database fields require whole numbers. The complete applicable batch validates before any record is changed.

| Table | Allowed fields |
| --- | --- |
| `monster_prototypes` | `hp`, `mana`, `damage_min`, `damage_max`, `experience` |
| `spell_prototypes` | `mana`, `range`, `effect`, `duration`, `price` |
| `perks` | `cost` |

API 1 refuses overlapping archive entries, database fields or capability bindings, including duplicates inside one package. Load order does not silently choose a winner. It cannot add records, replace story scripts, change map geometry or introduce campaigns. A patch naming a nonexistent record prevents the affected mode from starting; disable the package or fix it as a new version.

## Storage, recovery and limits

Profiles and selections live in `user://mod_settings.json`; installed versions live under `user://mods/<id>@<version>/`. Named campaign saves and network characters add a `mods/<profile-id>/` directory beneath their original directory. Profile names are display labels; stable random IDs keep paths independent of labels. The selection is stored per campaign.

Saves and multiplayer characters store the effective configuration and package fingerprints. Missing or changed required gameplay content blocks loading and reports the required setup. The manager remains available to select a working profile. Selecting Current defaults restores the unmodded profile. Keep older installed package versions if their saves still matter. The importer never overwrites an installed version.

Config writes use a temporary file and rename; imports stage a complete package before installing its folder. An unreadable profile file is retained as a recovery copy before a later config write. Invalid dependency/conflict selections leave the previous selection unchanged. Save-copy and backup import preflight the progression boundary before writing.

Packages are limited to 128 MiB compressed and total uncompressed, 4,096 entries, and a 1 MiB manifest. Import validates the ZIP directory before decompression; encrypted, multi-disk, ZIP64, symlink, duplicate/case-colliding and unsafe paths are rejected. Undeclared files are rejected. Arbitrary scenes, GDScript, native code and executable hooks are unsupported.

The broader [design](mod-menus-and-options.md) remains a roadmap. Profile export/deletion, mod discovery/updates, automatic save migration, custom campaigns, scripting, extra sandbox authoring commands, search and translated mod schemas remain future work. Current UI strings use the existing translation helper with English fallback. The [validation record](validation/mod-menus-2026-10-11.json) covers focused Linux source tests; the new native Android picker and browser import path still need device/browser acceptance before a release.
