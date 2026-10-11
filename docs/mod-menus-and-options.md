# Mod menus and options design

11 October 2026. API 1 is included in 1.0.4 Experimental 1: profile manager, shared rule editor, generated numeric mod options, data packages, save/co-op matching and a bounded sandbox. See [the implemented API and player guide](mods.md) for the exact supported format and current limits. The broader features and illustrative schema below remain a roadmap, not a claim that every feature has shipped. See the [experimental release notes](releases/1.0.4-experimental.1.md).

Cursed Lands should offer optional game rules and a common settings menu that installed mods can extend. Players should be able to choose a campaign and a set of mods, understand what changes, configure them with mouse, controller or touch, and return to the same setup when loading a save. Start by giving the existing remake gameplay options a shared definition and a visible rules summary; add content packages after save and multiplayer compatibility are established.

Use three connected surfaces: **Mods** for installed packages and profiles, **Mod options** for their settings, and **Sandbox** for explicit cheats and authoring tools. Ordinary graphics, camera, controls and accessibility settings keep their existing homes. Built-in optional rules remain usable without installing a mod.

## Where players find the menus

| Surface | Purpose and behavior |
| --- | --- |
| Main menu → Mods | List installed mods, enable or disable them in a named profile, import a package, inspect dependencies and conflicts, and open each mod's options. Show the selected campaign, profile and active mod count. Installation and activation are separate steps. |
| Options → Remake → Mod options | List enabled mods with configurable settings. Each opens its own named pages. Reuse this screen from the manager and the in-game menu. With no configurable mods, explain that here and link to Mods. |
| Existing Gameplay and Network and co-op pages | Keep established built-in options and labels. Add a Rules summary/presets link; all views edit the same values. A mod's setting must not silently become a second switch for an existing engine option. |
| New Game and Host game → Rules and mods | Review the campaign, profile, enabled packages and effective shared rules before starting. Select defaults for this run, including whether sandbox actions are allowed. |
| Load game → Required mods | Show the save's required profile and any missing, changed or incompatible packages. Offer an installed matching setup before loading. |
| Esc → Mods and rules | Inspect the active setup, change local presentation settings and see which shared rules the host permits changing. Package changes return to the main menu. |
| Esc → Sandbox | Appear only in an explicitly enabled sandbox session. Show commands such as Heal party or Give item separately from persistent settings such as Invulnerability. |

The manager needs an Installed list and a details view containing version, description, supported campaign/mode, dependencies, status, Options and Enable/Disable. Start with local import and a desktop Open mods folder action. Online discovery, ratings and automatic updates can come later.

Keep the game's frames, fonts, sounds, Apply and Back conventions. The current Options screen has a fixed 14-row layout, so arbitrary mod lists need paging or scrolling in a dedicated panel. Show help text on selection, not just hover; support controller focus and touch-sized controls, with no drag-only load-order operation. Provide Search and Changed settings filters as the list grows. Each setting shows its default, scope and when it takes effect, using labels such as **Your device**, **Host rule**, **At camp** or **New game**.

## What players could configure

Existing examples below are present in the inspected source. Extensions are proposals and need their own implementation and campaign checks.

| Area and reason | Existing foundation | Useful extensions | Ownership and timing |
| --- | --- | --- | --- |
| Party progression and recovery, for easier or stricter campaign runs | Full experience in solo, revival, mercenaries travelling between regions | Revival duration and returned health; XP multipliers; named challenge presets | Saved host rules. Change recovery rules at camp; reward changes affect future awards only. |
| Co-op balance, for groups with different sizes or play styles | Full experience, monster scaling, shared loot, shared pause/speed | Separate scaling choices for health and damage; reward-sharing presets | Host rules visible before joining. Changes that rebuild monsters wait for a zone reload. |
| Combat and stealth, for challenge or balance mods | Combat, skills, senses and spell data | Damage, stamina and regeneration tuning; stealth detection or friendly-fire rules | Saved host rules, initially locked for the run. Preserve scripted exceptions and peaceful-zone restrictions unless a supported campaign mod changes them. |
| Equipment and economy, to reduce repetition or create scarcity | Durability, repair, shops, recipes, materials and runes | Wear/repair multipliers, crafting costs, future stock and loot tables | Saved host rules/content. Never retroactively reroll owned items, reward completed quests or refill an already visited shop on Apply. |
| Interface and access, to make information easier to read | Enemy bars, path visibility, camera modes and input options | Larger labels, outline colours, reduced flashes/shake, clearer inventory filters; mod-specific status panels | Local and usually live. General accessibility improvements belong in the base game; a mod menu may link to them. Visibility controls must respect what the player is allowed to see. |
| Visual and audio packs, for a different presentation | Renderer options and readers for game textures, models, sounds and texts | Texture/sound replacements, translation packs, portrait variants and named visual presets | Local only when they cannot alter collision, targeting, perception or simulation. Asset replacement takes effect after a menu reload in the first version. |
| Quests and campaigns, for new adventures | Campaign maps, zone files, dialogue and the story-script interpreter | New quest packs, encounters, maps and eventually separate campaigns | Required content on all peers; usually new game. Distinguish Main game, Lost in Astral and a future custom campaign explicitly. |
| Sandbox and authoring, for experimentation and reproduction | Debug tools and a host command path | Heal, invulnerability, unlimited mana, give gold/items, spawn a test enemy, teleport to a valid point, pause/step and free camera | Solo or an explicitly advertised host sandbox; separate progression. Quest-variable editing stays an advanced authoring tool. |

Higher party caps, additional mercenaries across scripted party swaps and arbitrary quest changes should come late. Story roles, camp layouts, movers and travel conditions impose real constraints; a larger slider value alone does not make those features work. The original multiplayer mode also has distinct databases, characters and respawn rules. Mark unsupported options unavailable with a reason; for example, the campaign revival option does not apply there.

Offer **Current defaults** and **Custom** first. A later **Classic rules** preset must list the exact gameplay switches it changes and make no promise of perfect original-engine parity. Graphics presets remain independent. Resetting one mod restores only that mod's defaults; applying a rules preset shows the changed values first. Preserve existing player choices during migration.

## A common menu contract for mod authors

Mods should describe their options as data; the game builds and operates the controls. A package supplies a stable mod ID, version, supported API range, supported campaigns/modes, dependencies, declared conflicts, requested capabilities and a settings schema. IDs are namespaced, for example `example.revival_rules:revive_seconds`, and are independent of translated labels or page order.

Each option defines a type, default, label/help translations, page/group, valid choices or bounds, authority, storage and application timing. Add an optional feature requirement and simple declarative visibility conditions. These conditions use a small supported vocabulary, never evaluated source code. Store enum choices by stable IDs rather than their display indexes.

Start with toggles, enum choices, bounded integer/decimal values, reset controls and read-only status rows. Add colour and action-binding controls when their supported use cases arrive. Numeric controls need both a slider and an exact value entry. Actions such as Give item use a separate command definition and result message; they are not booleans that fire again on load. Key bindings go through the existing input system and conflict UI.

An illustrative future option definition for configurable revival is:

```json
{
  "mod_id": "example.revival_rules",
  "schema_version": 1,
  "options": [
    {
      "id": "revive_seconds",
      "label": "Revive time",
      "help": "Time spent helping a fallen party member. Applies at camp.",
      "type": "number",
      "default": 5.0,
      "min": 1.0,
      "max": 15.0,
      "step": 0.5,
      "unit": "seconds",
      "authority": "host",
      "storage": "save",
      "apply": "camp",
      "modes": ["single_player", "campaign_coop"],
      "requires_capability": "revival_rules_v1"
    }
  ]
}
```

This schema is a proposed contract, not a currently loadable file. Rendering the row does not implement the feature: `Revive.SECS` is currently a constant. The engine must provide the named capability, route its effective value to the revival code, and synchronize it before this package can be enabled. Missing capabilities produce a clear unsupported status.

Validate the entire pending edit before applying it. Cancel restores any live local previews. Publish one accepted change batch, with a change list for the affected systems, rather than rebuilding resources after every slider movement. Show which values are pending until camp, reload or a new game; the active session always displays the effective value as well.

Arbitrary Godot scenes, GDScript/native libraries and unrestricted callbacks are outside the first mod API. Use validated data patches and explicit engine features first. A later scripting API needs bounded events, serializable per-mod state, execution limits and a documented set of operations. The existing story-script interpreter is a compatibility component; its existence alone does not establish a general sandbox for untrusted code.

## Separate preferences from game rules

| Kind | Stored where | Who changes it |
| --- | --- | --- |
| Device preference | Local mod preferences, per profile | Each player; for example colours or a purely visual marker size |
| Campaign rule | Save, with its effective value and schema version | Solo player or co-op host, at the allowed boundary |
| Session rule or command | Active session; persistent consequences still belong to its save/profile | Host; for example shared speed or a sandbox spawn command |
| Content configuration | Profile package lock and each save's compatibility record | Main menu, before the world and its resources load |

Introduce a settings registry plus a resolver for effective session rules. Initially, adapters can use existing `GameData` keys so old menu entries and gameplay code keep their behavior. Gradually move simulation reads to the resolver. A guest's local configuration never overrides the host's rule, and disconnecting restores their own defaults.

Keep mod preferences in a dedicated store such as `user://mod_settings.cfg`. The current `GameData.save_settings()` recreates `settings.cfg` and preserves only selected extra sections; simply appending arbitrary mod sections there would lose them. A save contains its own resolved rules, rather than depending on the next machine's global preferences.

The UI and any separate local simulation process must receive the same validated rules and package lock, including in single player. Extend the existing local-host configuration and change transport. Otherwise a menu could display a modded value while the child process simulates the default.

## Content loading and conflict handling

Use a separate mod installation directory and leave the player's source game data intact. A profile is a named selection of package versions, options and a resolved load order. Keep installed versions side by side when a save requires an older one. Exporting a profile exports the manifest and choices, without copying the player's game installation.

Resolve base data, dependencies, ordered overrides and explicit compatibility patches before starting a session. Report the winning provider for an overridden resource or database field. Independent mods that write the same target conflict unless the profile explicitly resolves the override or a compatibility patch defines it. Cyclic dependencies, missing requirements and incompatible campaign targets prevent activation.

The loader needs two integration levels: loose paths and entries inside `.res` archives. Changing `GameData.read_file()` alone would miss textures, texts and database records read directly from archive objects. Provide a common content resolver, then controlled archive-entry overrides and database patches. Patch named records and fields with validated types and references; the database reader must define a stable key for each supported table before it is patchable. Keep campaign and original-multiplayer database targets distinct.

When mounting a profile, reopen the affected archives, clear dependent resource/database/script caches, and rebuild the content signature. Package activation starts at the main menu, with a full restart fallback where a subsystem cannot safely unload. Do not promise hot reload of a running quest or replacement of live item prototypes in the first release.

Campaign detection currently recognizes two games. New campaigns need declared identity, starting map/party, base-data requirements and a separate save namespace; they must not silently fall back to the main campaign. Existing story compatibility repairs must remain guarded by the authored patterns they target when a mod replaces those scripts.

For imported packages, validate relative paths, duplicate/case-conflicting entries, allowed file kinds and size limits before atomic installation. On Android and web, use an import picker and managed storage; desktop folder access is optional. Retain the browser's bounded file reads rather than copying whole packs into runtime memory. A content hash identifies package bytes; it does not establish that an author is trustworthy.

## Saves and returning to an existing run

Give each modded profile a stable ID and separate saves, quicksaves and autosaves. Keep existing unmodded save paths working. Profile names can change, and editing an option must not change the profile's directory. Each individual save records the exact effective setup:

- Base campaign and game mode, profile ID, mod API/save schema versions.
- Required mod IDs, versions, content digests and resolved order.
- Effective gameplay values and any versioned per-mod persistent state.
- Sandbox/progression classification and the configuration signature used by multiplayer.

Loading checks that record before constructing the world. Missing gameplay content blocks normal loading with the exact missing dependency. Missing optional cosmetic content may fall back to the base presentation after a notice. Never silently remove unknown items, quest state or required mods to make a save load. A destructive recovery path, if added, works on a separately named copy.

Updates run declared, validated migrations on a copy and retain the previous save/package versions. Removing a gameplay mod is allowed only where its persistent state is known to be removable; otherwise continue with the saved setup or start another run. Turning off a cheat does not undo gold, XP or items already created, so the save remains a sandbox save.

Older saves have campaign identity but no complete historical rules snapshot. Mark their configuration as legacy and establish an explicit baseline on the next save using the effective supported settings. Do not claim to reconstruct their history or reset them to newly invented defaults.

## Multiplayer agreement and progression

The host publishes a readable mod/rules summary in the lobby and a canonical compatibility signature before character transfer or world loading. The signature covers campaign/mode, mod API, required content and its resolved order, and effective gameplay options. Normalize field ordering and numeric values so equivalent configurations compare consistently. Keep existing base-map/edition checks and host database synchronization; mod matching extends them.

Clients may retain different approved local presentation mods. The engine classifies capabilities and affected resources: a package cannot bypass matching merely by labelling itself cosmetic. Models that change collision, rules that reveal hidden actors, and scripts affecting the world are gameplay content. Local translation/speech differences should not by themselves break the existing compatible-language behavior.

On mismatch, show what differs, for example **Host requires Example Quest Pack 1.2; you have 1.1**, and offer to select an already installed compatible profile. Joining does not install packages or run code received from the host. Existing database-value synchronization is not a substitute for required map, script, model and item assets.

Only the host applies shared changes. Guests see them read-only. An accepted live change has a revision and is acknowledged before dependent commands resume; late joiners and reconnecting players receive the current effective configuration. Content, character-construction and broad balance changes remain locked during a running session. Disconnected peers restore their local configuration.

**Brought heroes require an explicit progression boundary.** The current game carries a guest's earned items, XP, purse and some story progress into a separate personal co-op save. For a modded run, import the hero into a compatible mod profile or make a separate modded copy before entering. Return progress only to that compatible profile. Sandbox rewards must not enter an ordinary campaign or ordinary original-multiplayer character through export, trade or reconnect. For the first version, require an exact gameplay profile for progression return; flexible compatibility declarations can follow later.

This is save integrity for cooperative play, not an anti-cheat guarantee against modified clients. Advertise sandbox mode in the lobby, keep authority checks on every sandbox command, and make participation explicit.

## Delivery order and acceptance

1. **Built-in rules and generated menus.** Define option metadata and adapters, keep current defaults, add the rules summary and profile storage, and prove the UI with existing revival, XP, loot and scaling controls. A development fixture can exercise mod pages without shipping a package loader. Finish save snapshots and local-host propagation before adding new simulation controls.
2. **A small public mod format.** Add local package import, manifests/dependencies, profile switching, archive-entry and narrowly supported database patches, generated per-mod pages, cache invalidation, load checks and multiplayer matching. Ship one small cosmetic example and one bounded gameplay example. Handle brought-hero progression and original-multiplayer characters before allowing those packages online.
3. **Broader content and authoring.** Add custom campaigns, more patchable data, bounded script hooks, supported migrations and a sandbox with explicit commands. Build content packs and balance presets on that API. Add discovery or automatic updates only after version retention and recovery work reliably.

The first production slice is complete when a player can review and persist existing game rules, load them accurately, and see the same values on the host, a guest and the separate local simulation process. General third-party content support is a later milestone.

Meaningful acceptance cases for implementation:

- Apply/Cancel/reset with mouse, controller and touch; long translated labels, many mods and disabled dependency rows; no hidden input still controlling the game.
- Invalid values, unknown schema versions, absent capabilities, circular dependencies, conflicting overrides and failed imports leave the previous working profile intact.
- Save/load restores exact rules and mod state; required-package removal blocks load; cosmetic fallback and legacy-save handling preserve data.
- Real host/client, late join, reconnect and local-host runs agree on rules; unauthorized guest changes fail; missing required assets are detected before spawning.
- Brought-hero progress, trade, co-op return, original-multiplayer characters and sandbox copies stay in the right profile across reload and disconnect.
- A profile switch clears changed archive/database/resource caches; menu opening performs no repeated whole-pack hashes or frame-by-frame disk reads.

## Current implementation references

Source initially inspected at `723025cd544559752bab397ff0f8b32df2c08388`. Paths are relative to this checkout. These were the starting integration points; the implemented API is now defined by `ModSchema`, `ModStore` and the [API 1 guide](mods.md).

| Existing component | Relevance |
| --- | --- |
| [GameData](../game/src/ei/game_data.gd) | Fixed option definitions, defaults, campaign roots, archive loading, settings persistence and batched changes. |
| [OptionsPanel](../game/src/ui/options_panel.gd) | Remake subpages, 14-row layout, pending edits and input conventions. |
| [CampaignProfile](../game/src/game/campaign_profile.gd) and [game library](campaign_library.md) | Two recognized campaign identities and separated save paths. |
| [GameFiles](../game/src/platform/game_files.gd), [EIResArchive](../game/src/ei/res_archive.gd) and [EIDatabase](../game/src/ei/database.gd) | Loose-file access, browser storage, archive entries and parsed record schemas. |
| [CampaignState](../game/src/game/campaign_state.gd) and [SaveInfo](../game/src/game/save_info.gd) | Serialized world state and load-screen metadata. |
| [Session](../game/src/game/session.gd), [NetStatus](../game/src/game/net_status.gd), [CoopDb](../game/src/game/coop_db.gd) and [LocalHost](../game/src/game/local_host.gd) | Authority, connection checks, base map hashing, host database values and child simulation configuration. |
| [CoopProgress](../game/src/game/coop_progress.gd) and [MpCharacter](../game/src/game/mp_character.gd) | Hero import, guest progression return and original-multiplayer character persistence. |
| [Revive](../game/src/game/revive.gd), [XpRules](../game/src/game/xp_rules.gd) and [MobScaling](../game/src/game/mob_scaling.gd) | Useful bounded starting points for optional gameplay rules. |
| [StoryCompat](../game/src/game/script/story_compat.gd) | Existing story repairs that must remain compatible with replacement campaign content. |
