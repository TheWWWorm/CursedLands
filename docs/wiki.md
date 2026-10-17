# Encyclopedia

Press **F7** while pointing at an item, spell, rune, creature, quest or map to
open its wiki page. The shortcut also works in inventory, shops, HUD slots,
quest screens and Trials, including online autochess. Without a subject under
the pointer, it opens the wiki home page. Rebind **Wiki under pointer** under
**Options → Windows**; classic and WASD layouts keep separate bindings.
Existing custom keys are preserved. Escape returns to the previous screen.
Single-player gameplay pauses while browsing; online gameplay continues.

From the home page, choose a category,
search the localized page names, and click an entry. Each item has one page;
its **Material / version** selector switches the statistics and model on that page.
Craftable items include a **Blueprint** choice in that selector.
Campaign tabs select the base game or an installed Lost in Astral campaign.
Search ranks exact names before prefixes, substrings and category/location matches.
If there are no direct matches, it tolerates short misspellings and transposed
letters. Each result separates its title from its category and useful context.
Item subcategories narrow the list by purpose, weapon type or armor slot.
Map results distinguish camp and exploration locations, including shared names.
Links connect maps, quests, materials, item variants, recipes,
spells, runes, creature equipment and related mechanics. Back/Forward retain
page history and scroll position; Alt+Left/Right also navigate history.

**Characters** contains 45 biographies for Cursed Lands and 47 for Lost in
Astral, including each protagonist, companions and minor speaking characters.
**Allods** covers the three original islands and four expansion islands. These
are campaign-specific accounts: reused script actor IDs do not identify the same
person across campaigns. Zak's article includes his revealed identity and the
German edition uses its original names Kiran and At-Kira. Search includes aliases
and article prose. Character articles connect to their original models, locations
and other characters; creature statistics retain their existing addresses.

Story articles include spoilers, numbered source references and conditional
wording for optional outcomes. Accusations, rumours and a character's own
justifications are attributed. The sources are the original dialogue, quest
journals, event scripts and world descriptions, with fingerprints for each supported edition. If an installed mod
changes a source, the corresponding prose is withheld with a localized notice.
The wiki never executes dialogue scripts to discover story events.

The 34 named briefing locations now have written introductions and original
scene illustrations. The public wiki renders these offline from original map scenery,
framed around the authored location centres; they are not north-up maps and receive no position
pins. Native readers can choose **View location** to load the scenery without a
game world, session or script VM. Allod illustrations use the original travel-map
models. Quest illustrations identify the associated location in their captions.

Drag a model to turn it, use the wheel to zoom, or use its rotation, zoom and
reset buttons. The buttons support touch and the game's controller pointer.
With a controller, LB/RB navigate page history and LT/RT scroll the article.
On narrow screens, **Browse and search** opens the list separately, while
**Show illustration** opens the map, model and construction controls. Return to
the article without losing its selection. Close or Esc returns to the game. Single player preserves the menu's usual
pause behavior; in co-op the world continues running while local gameplay
input is blocked.

Spell pages offer compatible runes using the inventory constructor's admission
rules. The selected rune stays selected after adding it, with its artwork visible.
Add a rune to see the calculated power, cost, complexity, range, area, radius,
duration and targets. Remove the last rune or reset the spell. Item pages offer
compatible enchantments, removable enchantments and rune combinations within the
item's slot and native constructor limits. These calculations do not edit the
character, inventory, save or network state.

Map pages show a north-up overview with pan, zoom and reset controls. Exits and
quest areas are shown initially; creatures are an optional layer. Nearby points
of the same kind cluster at the displayed zoom. Select a marker to open its list
of named locations or articles in an interactive popup beside the marker;
zooming separates groups. Exits use green directional arrows like the game. No point is discarded
from the underlying data. Quest pages show authored objectives, rewards and
available original hints by default, with an optional collapse control. They do
not disclose the current save's progress or invent missing walkthrough steps.

Journal quest titles, the objective/map panel, inspected creatures and selected
camp inventory items provide contextual article links. They use the existing
menu/pause flow and retain the selected item material and spell where available.

## Sources, uses and difficulty

### Maintaining lore

Edit `tools/wiki_lore_content.py` for identities and place introductions, and
`tools/wiki_lore_history.py` for the ordered campaign histories.
`tools/wiki_lore_kel.py` selects Kel's shared events and adds her focused
biography and the verified Rod of Life walkthrough. Each paragraph
carries English, Russian and German text, its heading and original source IDs.
`[[character/hero]]` and similar
references resolve to the current campaign's localized article names. An optional
label, such as `[[character/rick|Великому Магу]]`, keeps inflected prose grammatical. Do not
copy a plot from another adaptation, promote rumours to facts, or fill unknown
history with inference. Keep optional outcomes conditional.

Order histories by the events' narrative prerequisites, checking the original
dialogue, quest journals and trigger scripts; dialogue and quest numbers alone
do not define chronology. For example, Zak's opening follows the fleeing
villagers, village assembly and early errands before his meeting with Estera.
Explain parallel investigations and optional companion adventures without
claiming one mandatory order. A shared event appears only on the involved
character, location and allod pages. Use `quest:<id>` for journal evidence in
addition to dialogue IDs, `script:<mob-name>` for outcomes established by active
map triggers, and `zone:<id>` for world descriptions. A conversation present in a
text archive is not necessarily playable: verify its entry trigger before adding
it to a biography. Exclude disabled proposals and developer jokes from the
played history. Script evidence is read and fingerprinted without executing it.
The source list
labels these separately for readers. Long web articles have expandable contents.

Run `tools/export_wiki_lore_evidence.gd` through the normal `--tool` entry point
with `--lore-evidence=/private/path/<edition>-world.json` for the original EN/RU/DE
editions and the Russian expansion. Name these private exports
`base-en-world.json`, `base-ru-world.json`, `base-de-world.json` and
`astral-ru-world.json`. Then run:

```sh
python3 tools/build_wiki_lore.py --evidence /private/path
```

The compiler validates sources, translations, references, prototypes and actor
coverage, then writes `game/src/game/wiki_lore_data.gd`. Original archive text
and scripts remain private; the generated resource contains authored prose,
source fingerprints and model/location references. Object matching uses both
actor names and the engine's numeric name IDs. Explicit placement exceptions
prevent the generic shop actor `trader` from associating unrelated shopkeepers
with Karansul. The only uncovered expansion speaker labels are developer-credit
or unused joke scenes and a background soldier's battle cry; the alternate
Wormface speaker label resolves to the same biography.

Run `tools/tests/wiki_lore.gd` for each campaign. It reads the actual dialogue
speaker inventory, checks every section against the installed sources in all
three languages, validates links and images, and tests suppression after a
source edit. `tools/tests/wiki_lore_visual.gd --wiki-capture=/private/path` produces
rendered desktop and phone acceptance captures. Finish with the standard public
wiki exporter, illustration exporter and `prepare_public_wiki.py` validation.
Speaker coverage and matching source hashes do not establish that a biography
is complete or that its events are correctly ordered: review the prose against
the story separately, and record that editorial review alongside the checks.

Articles link equipment to its wearers, carried items to creatures, materials to
compatible crafts, quest items to their requirements or rewards, and creatures
to authored map placements. Trader links indicate possible stock, not a promise
of current availability. Carried equipment is not described as a guaranteed drop.

Creature articles label changing values as **Easy / Hard** pairs in the same
row. Shared health, stamina and damage appear once; natural armor keeps separate
rows for each damage type. Attack and defense follow combat's integer
truncation; bows and crossbows have zero defensive weapon rating. Multipliers
come from the loaded `ai.reg` difficulty arrays, so data mods remain authoritative.
The comparison describes ordinary non-party prototypes: named characters keep
attack and defense on Easy, and party members keep natural armor. Hard denotes
the standard setting, called Normal in some editions. Network play uses that
setting before additional co-op scaling. These exceptions are explained in the
article; the wiki does not pretend to simulate a particular live creature.

## Build planning and sharing

Use **Add to plan** on equipment and constructed-spell articles, then open
**Build planner**. Choose attributes, earned experience, skill levels and item
quantities. It calculates health, stamina, carrying capacity, total load,
training cost, base value, crafting fees, material quantities and spell
requirements. These are reference calculations; the planner does not simulate
equipment bonuses, perks, temporary effects or a complete combat encounter.
Slot choices enforce the item category; unequipped entries remain in the planned
inventory. The native portrait changes with equipped items. The website portrait
is a static character illustration and does not reflect the chosen equipment.
Crafting uses the base constructor fee, independent of the currently open trader.

The planner, item builder and spell builder use the original camp artwork and
slot positions. The workspace scales with the viewport. Select a weapon, belt,
armor or spell slot to choose equipment. Wide windows put the selector beside
the camp, keeping attributes and skills visible. The website catalogue scrolls
separately from the selected item, material and actions; filtering preserves
that selection. Narrow screens use a bounded drawer. Constructors also offer a
searchable spell selector beside the camp on wide windows.
**From this build** reuses an existing entry with its spell and runes intact.

**Craft / enchant** opens the selected item or spell in the workbench. Choose a
material, an enchantment and compatible runes. **Craft and equip** validates the
combination, adds it to the plan and equips it in the requested slot. An item
enchantment needs its applicable item rune; invalid combinations cannot be added.
Click an installed rune to remove it, or reset the rune combination.

**Copy link** stores the complete plan in `#build=` as versioned UTF-8 JSON
encoded with base64url. It includes campaign, attributes, experience, six skills,
item versions, spells, runes, quantities and equipment slots. Slot assignments
are optional in the version-1 format, so previous links still import. The native planner can import that
same link. Plans survive article navigation and language changes; campaign plans
are separate. No account or server storage is needed. Browser reload restores a
plan from the URL; native drafts are retained while that wiki panel exists.
Inputs are bounded to 32 entries, 8 runes per spell, 1–99 items per entry and a
24,000-character encoded payload. Invalid or unsupported data is rejected;
missing content is identified without mutating inventories or saves.

**Save locally** creates a named snapshot of an item, a rune-modified spell, or a
complete character. **Saved creations** opens a searchable library with filters
for the three types. Open a snapshot to continue editing it, or add an item/spell
to the current plan. Saved recipes also appear in compatible equipment selectors;
saved spells can be reused as item enchantments. Material, spell, runes, character
attributes, skills, quantities and slot assignments are retained. Editing a loaded
snapshot does not overwrite it; Save locally creates another snapshot.

The website uses browser `localStorage` under `cursed-lands.wiki.library.v1`.
The native game uses `user://wiki-creations.json`, written through a temporary
file before replacement. Libraries are separate on each device/browser and are
not synchronized with each other. Both accept up to 100 named creations, retain
campaign identity, validate the version-1 plan payload, and report storage errors.
Unreadable libraries are left untouched. Clearing browser site data removes its
library; use **Copy link** for a portable backup. Local recipes never alter game
inventory or campaign saves.

## Public website

The [public wiki](https://cursedlands.wwworm.com/wiki/) is a standalone website.
It needs no game files, game download or account. Browser storage is used when
you explicitly save creations; reading and sharing links work without it. Search results
use one continuous scrolling list. Items can be filtered by armour slot, weapon
type, quest items, wands, potions, or trophies and valuables. The spell list shows
31 named base-game spells or 35 named Lost in Astral spells. Rune-equipped
combinations and empty-rune duplicates remain available through article links
without duplicating the browsing list. Unnamed database templates are also
excluded from that list; retained spell links have translated descriptive names.

Two campaign tabs select separate catalogs. The base game has 1,229 article
addresses and 2,009 precomputed views per language; Lost in Astral has 1,706
addresses and 2,666 views per language. Both cover English, Russian and German,
including 36 base-game locations and 56 expansion locations. Authored overview
art is available for 20 base-game maps and 38 expansion maps; other location
pages retain their quest links and description. Only craftable items offer material
and blueprint choices. Fixed story items use their authored name and material;
NPC costumes without an item name use the localized wearer and garment names.
Links retain the campaign, language, page and selected version and work with browser
Back/Forward, including the position in the result list. Illustrations use the
original models and available male/female costume textures. Static thumbnails
are framed around the visible pose with space around its extremities. The
in-game wiki retains live model rotation. Both versions include spell and item
constructors, rune artwork, removable runes and calculated statistics. Website
drafts are retained when changing language or an item's material. Unnamed
internal colour/effect modifier records are excluded from the rune browsing list.

The base dataset uses the GOG Evil Islands databases and localized text archives.
The expansion tab uses the original installed Lost in Astral database and Russian
text. Shared English/German text is reused from GOG only when its Russian source
agrees; expansion additions use the reviewed translations in
`tools/wiki_lia_translations.json`. Matching an internal ID alone is unsafe:
the expansion reuses some IDs for different content. Original Russian text is
retained. Optional base-game quest descriptions also use the original English,
Russian and German `.mq` texts. Bundled translations are applied only when the
source fingerprint matches a known original; edited data-mod text stays intact.
The footer identifies the source and translation treatment for each
campaign. All statistics use the 1.7.0 calculations and original armor rule.

Creature equipment links lead to available base material articles. Obsolete
prototype combinations that the expansion's item builder no longer supports
link to the item family without suggesting a craftable version. Enchantments
and temporary effects can change equipment in play. The in-game wiki additionally
uses active data mods. No original archives, maps, saves, video, audio or
executable game files are part of the public wiki.

To rebuild, invoke `tools/export_wiki.gd` through the game tool runner once for
each installed GOG language, with `--wiki-output=/private/wiki-base`. For one
run add `--wiki-image-plan=/private/wiki-base-images.json`. Run
`tools/export_wiki_images.gd` with rendering enabled, the same image-plan argument,
and `--wiki-images=/private/wiki-base-images` to render illustrations. Use isolated
XDG directories, as for the tests below.

For LiA translations, run `tools/export_wiki_texts.gd` on each GOG language and
the original Russian expansion, passing `--wiki-text-audit=/private/<edition>.json`.
These audits contain original source text and are private build inputs; do not
commit them. Build the localized expansion overlays:

```sh
python3 tools/prepare_wiki_localization.py \
  --base-en /private/base-en.json --base-ru /private/base-ru.json \
  --base-de /private/base-de.json --astral-ru /private/astral-ru.json \
  --output /private/astral-texts
```

With the expansion installed, export Russian normally to
`--wiki-output=/private/wiki-astral`. Export English and German from that same
installation using `--wiki-language=en|de` and
`--wiki-texts=/private/astral-texts/en|de.json`. This changes only the tool
process's text cache, never the installation. Generate its image plan and images
with the expansion loaded; image IDs are campaign-specific. Export the original
camp panels, slot frames and keystones using `tools/export_wiki_ui.gd` with
`--wiki-ui-output=/path/to/repo/web/wiki` for each installed campaign. This tool
uses the same atlas cropping as the native `WikiCampArt`. Package both catalogs:

```sh
python3 tools/prepare_public_wiki.py --data /private/wiki-base \
  --images /private/wiki-base-images --astral-data /private/wiki-astral \
  --astral-images /private/wiki-astral-images --output /private/wiki-site
```

Use an empty staging directory for packaging, then copy the verified result to
`public/wiki`. The translation preparer fails if any required text lacks an
English or German translation, and does not substitute Russian text silently.

`web/wiki/` owns the website source and EN/RU/DE interface catalogue. The packager
checks every article, cross-reference, material version and translation key.
Keep `public/wiki` when rebuilding the browser export, and include it in the
standalone web archive. `worker.js` serves `/wiki` independently of the engine
and applies a restrictive content security policy to the wiki.

## In-game data sources

The active catalogue is built from the installed game data and active data mods.
Opening the other campaign's tab builds a separate catalogue from that installed
campaign. Archive, database and rendering caches are captured and restored around
that synchronous operation; changing wiki tabs does not switch the running game,
save, network session or selected mod profile. Only installed campaigns are
available in game. No original assets are downloaded.

| Content | Runtime source |
|---|---|
| Item families and their material/version selector | `Items.TABLES`, `Items.materials_for`, `items.idb` |
| Names and descriptions | The installed `texts.res` / `textslmp.res` archives |
| Damage, armor, weight, durability, charge, slots and base value | The existing `Items` gameplay calculations |
| Blueprint view within an item page | Authored craftable records and component counts |
| Spell prototypes and authored starting variants | `spells.sdb` prototypes and template tables |
| Interactive spell variants | `Spells.constr_rune_fits`, `Spells.with_mod`, `Spells.parse` |
| Interactive item enchantments | `Items` constructor limits and native enchanted-item calculations |
| Rune properties and compatibility | `spell_modifiers` and the same constructor checks |
| Creature/NPC variants, statistics, equipment and spells | `monster_prototypes` and `race_models` in `units.udb` |
| Item models and material textures | `ItemView`, `Items.look` and the existing redress composition |
| Animated creature models | `Paperdoll` / `EIUnitModel`, using the prototype's appearance |
| Maps and quest links | `CampaignMap`, map overviews, original quest text and script references |
| Localized world/reference text | Source-checked `WikiWorldText`, `WikiReferenceText`, `WikiQuestText` |
| Mechanics examples and active rule | `Items`, `Spells`, `Skills`, `Combat.aim_penalty`, `ai.reg`, current session rules |
| Easy/Hard comparison | `DifficultyLevels` arrays, combat integer/ranged rules, prototype natural armor |
| Acquisition, uses and map markers | `WikiKnowledge`: database links, read-only `.mob` records, quest/script references |
| Portable build calculations | `WikiPlan`, `Skills.base_pool`, `Skills.span_cost`, item/spell constructors |

Mechanics explanations are maintained prose checked against the combat code;
numeric examples and tuning values are calculated at runtime. Creature pages
describe database prototypes: map overrides, scripts, difficulty, buffs,
equipment changes and co-op scaling can alter a particular creature. A material
variant is a combination supported by the item builder, not a guarantee that a
shop stocks it. Base value is distinct from a trader's final price.

Rows without a localized name use a localized type or numbered creature
variant. Internal specifications are never used as display names. If an
authored row has no usable model or texture in the installed data, the page
keeps its statistics and displays a translated model-unavailable message.

## HTML and rendering

`WikiCatalog.page` returns an on-demand, escaped HTML article and its model
descriptor. Articles contain semantic headings, paragraphs, tables and local
`wiki://` links. A figure's object references the engine's live model rather
than a rendered screenshot. `WikiHtml` renders the supported HTML subset in a
native `RichTextLabel`; `WikiPreview` displays the live 3D object alongside it.
This uses the same renderer on desktop, mobile and the web, without a native
WebView dependency or local web server. It is an article reader, not a general
web browser. Scripts, styles and external navigation are not executed.

The search index loads no models. Only the selected page instantiates a live
preview, and navigating or closing releases it. Spell exploration does not
expand the search index with every possible rune permutation.

The relationship index is a typed directed graph with reciprocal links where
useful. Map points use normalized north-up coordinates and typed layers. Export
schema 2 carries result subtitles and illustrations, relationship groups, map
points, quest hints and planning inputs. The packager validates every target,
coordinate, translation and constructor payload. It reads map object records
without creating a game world or executing scripts.

## Verification

Run `python3 tools/check_translations.py` for literal and dynamically selected
English/Russian/German text coverage. With a Godot import completed, run:

```sh
godot-4 --headless --path game --render-thread safe -- \
  --ei-path=/path/to/your/game --no-local-worker \
  --tool=/absolute/path/to/repository/tools/tests/wiki.gd
```

Use private XDG data/config/cache directories to protect player settings. Omit
`--headless` to also capture the real model and text layouts. The fixture uses
the actual installed edition, checks every generated HTML article and link,
tests live data changes and new data-mod records, exercises the real widgets,
and writes `user://wiki-results.json` plus rendered screenshots.

`tools/tests/wiki_rework.gd` checks graph targets, bounded map points, search,
portable plans against gameplay calculations, every creature's difficulty
comparison against `Combat`, and native planner/map widgets. Run it against each
localized installation; rendered runs capture home, item, map, quest, planner
and difficulty pages. It also writes `user://wiki-plan-oracle.json` for the web
parity check:

```sh
node tools/tests/wiki_rework.mjs /private/wiki-plan-oracle.json /private/wiki-site
```

The JavaScript checks cover native/web plan parity, malformed payloads, typo
matching and marker clustering without losing points. Retain the existing
`wiki_features.gd`, `wiki_quest_locales.gd` and constructor parity checks too.

The encyclopedia is introduced in 1.6.0 under the [versioning policy](versioning.md).
