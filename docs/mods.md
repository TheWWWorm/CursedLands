# Mods, profiles and game rules

Profiles and game rules were introduced in **1.0.4 Experimental 5**. The saved-session mod API remains 1; all co-op peers must use the same game build. Stable 1.0.3 does not include this feature.

Open **Mods and rules** directly from the main menu. During play it is also available through **Options → Remake → Game setup**. The multiplayer screen also opens **Game setup**. **New Game** opens a fresh setup with standard difficulty and rules; use its **Mods and rules** button for optional changes before starting. Cancelling discards that new-game draft.

## Playing with a profile

1. On **Mods**, download a listed mod or import a `.eimod`/`.zip` package. Installation does not enable it.
2. Turn its switch **On**, then choose **Apply & restart**. Starting from **Original saves** creates a separate **Modded game** profile in the same transaction. Compatible original campaign saves are copied into the new profile.
3. Use **Profiles** to create additional named profiles, copy an original save, or switch back to **Original saves** with **Switch & restart**. Choose **Create sandbox profile** only for sandbox commands.
4. Configure **Game rules** and any available **Mod options**, then select **Apply changes**. **Back** discards pending edits. In a running game, edits affect that run; from the main menu, they set the next run's defaults.

Named profiles have separate campaign saves and original-multiplayer character folders. Original saves keeps the existing save locations and reads legacy saves. Creating a profile copies compatible original saves for the active campaign, including their names, timestamps and thumbnails. Source saves remain unchanged, and switching profiles does not copy again or replace later progress. The manager can also explicitly copy an ordinary save into a named profile. A sandbox save or character cannot be loaded or imported into an ordinary profile through the game's save, backup or network paths.

Rules say when they can change: **New game**, **At camp**, or **Live**. Guests can inspect shared rules; the host controls them. Running changes are stored in the save, so changing next-run defaults does not change an existing campaign. Package activation and profile switching require the main menu and a restart.

In a sandbox profile, **Sandbox** offers invulnerable party, unlimited party mana, heal living party and give 1,000 gold. Actions run on the authority, including when the local game uses a separate simulation process. They are unavailable during loading or movies. Sandbox supports single player and campaign co-op; original multiplayer is excluded. Disabling a cheat does not remove rewards already earned.

Mouse, keyboard focus and controller navigation use the same controls. D-pad up/down moves focus, left/right changes a choice or number, A activates, Y applies, and B goes back. Controls are at least 44 pixels high and pages scroll on narrow screens. Desktop/Android use the native package picker; the browser uses a local file chooser.

## Formula mods in 1.20.0

The desktop release adds **package API 3 / formula API 1** for optional Lua
formulas. It supports experience rewards, revival time and revival health in
single player and campaign co-op on Windows/Linux x86-64. API 1 data mods and
API 2 texture packs keep their existing contracts. Formula mods cannot be
activated on other platforms in this version.

The release includes three source examples and installable `.eimod` packages:

- **Expedition experience** adjusts all experience rewards (default ×1.5).
- **Quest focus** adds a configurable bonus to non-combat rewards (default +25%).
  It runs after Expedition experience when both are enabled.
- **Field medicine** scales revival time by the helper's intelligence and
  restores a configurable percentage of maximum health (default 25%).

Import the files from the release's `mods/` directory through **Mods and rules**,
turn the desired mods on and **Apply & restart**. Tune them under **Mod options**.
Changing options during play requires camp and affects the current run. The
examples include English, Russian and German text. Disable them or choose the
original profile and restart to return to ordinary rules.

Gameplay packages and option values must match between co-op peers; the host
runs formulas and sends their results. Save fingerprints include all declared
Lua sources. Publish an updated mod under a new version; a different source
bundle cannot silently replace one required by a save. Lua globals and captured
locals are discarded after each call, so scripts cannot persist hidden state.

A failed formula stops simulation, saving and returned co-op progress for that
run. The previous save is retained. Return to the main menu, inspect the game
log, and load a valid save with its matching packages. No formula library or VM
is loaded on a fresh unmodded launch.

See the [formula authoring guide](mod-formulas.md) for the contract, packaging,
limits and reuse of the earlier Jamais Vu groundwork. Original-game DLL loading
and DLL conversion are outside this version.

## HD Lands texture download

From the main menu, open **Mods and rules → Mods → HD Lands textures →
Download & install**. The Windows, Linux and Android apps fetch the pinned HD Lands
1.5.0 archive from its original publisher, verify its size and SHA-256, then
install the texture package. Progress and cancellation remain available.
Downloading does not enable the package: turn its switch **On**, then choose
**Apply & restart**. A separate profile is created automatically when needed.

The preferred source is [Gipat's 1.5.0 archive](https://allods.gipat.ru/files/ei/mods/hdlands/hdlands-1-5-0.7z),
described on [the HD Lands page](https://allods.gipat.ru/index.php?p=eimodshdlands).
If the transfer fails, stalls, or fails size/checksum verification, installation
tries [the author's Yandex Disk](https://disk.yandex.ru/d/c8hPzBwUtYr50w) once,
resolving a fresh link to `HD_Lands_1.5.7z`. Both sources must match the same
pinned archive before extraction. Cancelling does not start the backup.

This entry supports the base campaign, not Lost in Astral. It imports 390
textures from the reorganized 1.5.0 resources, along with the original readme,
changelog, development notes and map completion notes. HD Lands textures take
precedence over the included HD Pack where they overlap, following the original
configuration. Launcher settings, models, branding and ending text are omitted.

The immutable package ID `community.hd-lands-textures@1.5.0` preserves installed
1.4.0 packages and their profiles/saves; enable the new version in a named profile
to use it. Original game files and saves are retained. Selecting **Original saves**
and restarting restores the original textures. Texture choices do not need to
match between co-op peers. This texture package cannot be enabled alongside the
full converter package `legacy.hd-lands`.

To update an existing HD Lands 1.4.0 profile, keep that profile selected, download
and install 1.5.0, switch **1.4.0 Off** and **1.5.0 On**, then choose
**Apply & restart**. Continue the same save afterward. The update is manual;
1.4.0 remains installed so you can switch back using the same controls.

The archive is 272.7 MiB and installation requires 2 GiB free storage. Its
solid 7z decoder temporarily uses approximately 0.8 GiB additional memory.
On Android, keep the app in the foreground until installation finishes. The
download card shows the temporary memory requirement; HD textures also use
more memory while playing. Installation uses the app's private storage and
does not require access to the shared Downloads folder. The browser and macOS
builds do not include the archive installer. This catalogue entry
does not provide general legacy-mod or Jamais Vu support.

The larger textures retain the map's logical tile layout, including detail
gutters and mixed-resolution atlas layers. Authored HD atlases are not doubled
again by the built-in HD texture option. Interface sprites use the original
logical atlas coordinates at the replacement texture’s resolution; borders,
bars, tutorial buttons and camp controls retain their layout.

Package API 2 accepts texture packs: `textures.res`, `redress.res` and
`menus.res` MMP overrides and optional `.txt`, `.md` or `.rst` documentation in
`attachments`. Its total package limit is 1 GiB, with 128 MiB per asset and
1 MiB for `mod.json`. Members are staged individually. Other resource types,
gameplay options/patches and legacy scripts/maps are rejected for API 2.
API 1 packages retain their existing capabilities and limits; the saved-session
mod API remains 1. The existing command-line packaging/conversion tools still
target API 1; the in-game downloader creates its own texture package.

Implementation validation is recorded separately in
[the HD Lands 1.5.0 update report](validation/hd-lands-1.5.0-2026-10-13.json),
[the 1.0.5 release checks](validation/stable-1.0.5-2026-10-13.json) and
[the Android download checks](validation/android-hd-lands-2026-10-19.json).

## Co-op compatibility

Everyone needs the same network protocol, as listed in the build's release notes. The host checks the mod API, campaign, sandbox classification, ordered gameplay package IDs/versions/content hashes and effective mod option values before admitting a player. Existing original-map checks and database synchronization remain in place. No package is downloaded automatically.

Built-in host rules, such as full XP or shared loot, are published to guests without changing their local defaults. Gameplay mod values must match when joining. Choose the same package versions and values in the menu before connecting. A continued host save supplies its saved configuration before the lobby opens; stop hosting to choose a different save.

Experimental 4 adds **Free running outside combat**, disabled by default. It removes running stamina drain while the authority considers the party out of combat; injuries, carrying limits and spell costs still apply. Existing saves without this rule keep it disabled.

Experimental 5 adds **Always regenerate stamina** under **Game rules → Party**, disabled by default. Living party members recover stamina while moving or fighting, with each recovery pulse at least as large as their HP regeneration amount, including at full health. A higher normal stamina recovery rate is retained. Running and spell costs still apply. This live setting is saved with the campaign and synchronized by the host; older saves default to Off.


Experimental 2 checks saved mod compatibility before pausing a running group for loading. Refusing a save preserves the current game, pause state and speed. When a host without guests restores different saved mod values, new players can join after loading finishes with the matching values.

Texture/audio-only packages are local presentation choices and do not have to match. Any package with scripts, options or database patches is classified as shared gameplay by the engine. Authors cannot bypass matching with a cosmetic flag. Dependencies and load order are part of the resolved configuration. Imported heroes and returned co-op progress must remain within a compatible gameplay profile. Existing built-in co-op XP/loot options retain their prior progression behavior.

## Building a data mod (API 1)

See the complete, asset-free [Quick recovery example](../examples/mods/quick-recovery/mod.json). From the repository root:

```sh
python3 tools/package_mod.py examples/mods/quick-recovery quick-recovery.eimod
```

The result is an ordinary ZIP with `mod.json` at its root. The packaging tool includes only the manifest and declared replacement, documentation and script files, with stable timestamps/order. The game performs authoritative schema validation on import and activation.

For an existing legacy mod, the source-tree [legacy converter](legacy-mod-converter.md) can translate supported resource and numeric database changes into this format. DLL dependencies and unsupported content produce a compatibility report and block package creation.

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

Supported API 1 archives are `textures.res`, `redress.res` and `menus.res` (MMP or PNG), `sfx.res` (game-supported WAV), and `speech.res` (MP3). Use forward slashes in archive entry names. Textures must use an entry ending in `.mmp`; the replacement file can be an MMP or a PNG image (recognised by its contents, up to 16384 pixels per side). Supply other files in the formats the existing readers accept. The overlay is consulted by those readers and leaves the player's source archives intact. It is not a filesystem-wide replacement mechanism. New entries can be read by name and are included in archive suffix listings. API 2 accepts only texture overrides and documentation, as described above. API 3 also accepts these archive overrides alongside its formula contract.

`redress.res` holds character skin, clothing and equipment layers. For example:

```json
{
  "archive": "redress.res",
  "entry": "unhufeax_01.gr.0.mmp",
  "file": "assets/redress.res/unhufeax_01.gr.0.mmp"
}
```

Replacement textures can be larger than the originals. Character skins,
clothing and equipment layers share one layout, and the game composes a
character at the size of its largest layer, so a high-resolution armour layer
keeps its detail over an original-size skin.

`menus.res` holds the main-menu and Esc-menu signpost textures, such as
`mainmenu00.mmp` and `escmenu00labels.mmp`; its `numbers.mmp` also supplies the
floating hit-point digits. Each game edition ships its own
`menus.res` with signpost labels in its language. A replacement applies to
whichever edition is installed, so a pack that changes labelled boards should
state its language.

PNG replacements are decoded as full 8-bit RGBA and uploaded without DXT
compression, so they keep gradients, fine detail and smooth alpha that the
original 16-bit and DXT formats cannot represent. Mipmaps are generated by the
game; a PNG needs only its full-size image.

#### Editing textures without MMP or DXT tools

`tools/export_textures.py` (Python 3.10+, no extra packages) exports the
original MMP textures as PNG images that open in any image editor:

```sh
python3 tools/export_textures.py /path/to/EvilIslands textures-png
python3 tools/export_textures.py /path/to/EvilIslands textures-png --archive menus.res
python3 tools/export_textures.py /path/to/EvilIslands textures-png --match 'unhufe*'
```

The game folder is the one containing `res/`. Without `--archive` the tool
exports `textures.res`, `redress.res` and `menus.res` (about 140 MB of PNGs for
the base game, in roughly a minute). `--match` selects entries by name and can
be repeated. A single legacy-mod archive can be exported with
`python3 tools/export_textures.py t_nature.res out --name textures.res`.
The PNGs contain exactly the pixels the game decodes from the original MMP, so
an unedited export looks identical in game. Running the tool again keeps PNGs
you have changed unless `--overwrite` is given.

The output already uses the texture-pack folder layout. Copy only the images you
changed into the mod folder, keeping their `<archive>/<entry>.png` paths, and
package them as described below. No MMP conversion or DXT compression step is
needed. Its decoder is covered by
`python3 -m unittest discover -s tools/tests -p test_export_textures.py`.

To avoid writing the `overrides` table by hand, place images in folders named
after the archive and let the packaging tool generate it:

```text
my-texture-pack/
  mod.json                          (no overrides needed)
  redress.res/unhufeax_01.gr.0.png  -> replaces unhufeax_01.gr.0.mmp
  textures.res/sub/grass00.png      -> replaces sub/grass00.mmp
  menus.res/mainmenu00.png          -> replaces mainmenu00.mmp
```

`python3 tools/package_mod.py my-texture-pack my-texture-pack.eimod` adds an
override for every `.png` or `.mmp` file in those folders to the packaged
`mod.json`. Entries already listed in `mod.json` are kept; a file that
replaces the same entry twice is an error. The tool's behaviour is covered by
`python3 -m unittest discover -s tools/tests -p test_package_mod.py`.

Enable the package in a named profile and use **Apply & restart**. Disabling it
and restarting restores the original textures. Clothing and equipment textures
remain local cosmetic choices in co-op. Two enabled packages that replace the
same archive entry are reported as a conflict. The legacy converter also accepts
changed MMP entries from `redress.res` and `menus.res`.

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

API 1 packages are limited to 128 MiB compressed and total uncompressed; texture-only API 2 packages allow 1 GiB total with a 128 MiB per-member limit. Both allow 4,096 entries and a 1 MiB manifest. Import validates the ZIP directory before decompression; encrypted, multi-disk, ZIP64, symlink, duplicate/case-colliding and unsafe paths are rejected. Undeclared files are rejected. Arbitrary scenes, GDScript, native code and executable hooks are unsupported.

The broader [design](mod-menus-and-options.md) remains a roadmap. Profile export/deletion, mod discovery/updates, automatic save migration, custom campaigns, scripting, extra sandbox authoring commands, search and translated mod schemas remain future work. Current UI strings use the existing translation helper with English fallback. The [Experimental 2 validation record](validation/experimental-1.0.4-2-2026-10-11.json) covers Linux and Retroid package, input and simulation checks. Interactive acceptance of the native Android file picker and browser import remains outstanding.
