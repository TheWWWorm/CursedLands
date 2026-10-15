# Encyclopedia

Open **Game wiki** from the main menu or the **Esc** menu. Choose a category,
search the localized page names, and click an entry. Each item has one page;
its **Material / version** buttons switch the statistics and model on that page.
Craftable items include a **Blueprint** button alongside the material buttons.
Search matches every word;
the result list is paginated. Links connect materials, item variants, recipes,
spells, runes, creature equipment and related mechanics. Back/Forward retain
page history and scroll position; Alt+Left/Right also navigate history.

Drag a model to turn it, use the wheel to zoom, or use its rotation, zoom and
reset buttons. The buttons support touch and the game's controller pointer.
With a controller, LB/RB navigate page history and LT/RT scroll the article.
Close or Esc returns to the game. Single player preserves the menu's usual
pause behavior; in co-op the world continues running while local gameplay
input is blocked.

Spell pages offer compatible runes using the inventory constructor's admission
rules. Add a rune to see the calculated power, cost, complexity, range, area,
radius, duration and targets; **Reset spell** returns to the base prototype.
These calculations do not edit the character, inventory, save or network state.

## Public website

The [public wiki](https://cursedlands.wwworm.com/wiki/) is a standalone website.
It needs no game files, game download, account or local storage. Search results
use one continuous scrolling list. Items can be filtered by armour slot, weapon
type, quest items, wands, potions, or trophies and valuables. The spell list shows
31 named base-game spells or 35 named Lost in Astral spells. Rune-equipped
combinations and empty-rune duplicates remain available through article links
without duplicating the browsing list. Unnamed database templates are also
excluded from that list; retained spell links have translated descriptive names.

Two campaign tabs select separate catalogs. The base game retains 1,071 article
addresses and 1,851 precomputed views per language; Lost in Astral has 1,529
addresses and 2,489 views per language. Both cover English, Russian and German. Only craftable items offer material
and blueprint choices. Fixed story items use their authored name and material;
NPC costumes without an item name use the localized wearer and garment names.
Links retain the campaign, language, page and selected version and work with browser
Back/Forward, including the position in the result list. Illustrations use the
original models and available male/female costume textures. Static thumbnails
are framed around the visible pose with space around its extremities. The
in-game wiki retains live model rotation and custom rune construction.

The base dataset uses the GOG Evil Islands databases and localized text archives.
The expansion tab uses the original installed Lost in Astral database and Russian
text. Shared English/German text is reused from GOG only when its Russian source
agrees; expansion additions use the reviewed translations in
`tools/wiki_lia_translations.json`. Matching an internal ID alone is unsafe:
the expansion reuses some IDs for different content. Original Russian text is
retained. The footer identifies the source and translation treatment for each
campaign. All statistics use the 1.6.0 calculations and original armor rule.

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
with the expansion loaded; image IDs are campaign-specific. Package both catalogs:

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

The catalogue is rebuilt when opened from the currently loaded `GameData.db`.
Opening a different campaign, language, multiplayer database or data-mod profile
therefore uses that data. There is no bundled item, spell or creature list and
no download of original assets.

| Content | Runtime source |
|---|---|
| Item families and their material/version buttons | `Items.TABLES`, `Items.materials_for`, `items.idb` |
| Names and descriptions | The installed `texts.res` / `textslmp.res` archives |
| Damage, armor, weight, durability, charge, slots and base value | The existing `Items` gameplay calculations |
| Blueprint view within an item page | Authored craftable records and component counts |
| Spell prototypes and authored starting variants | `spells.sdb` prototypes and template tables |
| Interactive spell variants | `Spells.constr_rune_fits`, `Spells.with_mod`, `Spells.parse` |
| Rune properties and compatibility | `spell_modifiers` and the same constructor checks |
| Creature/NPC variants, statistics, equipment and spells | `monster_prototypes` and `race_models` in `units.udb` |
| Item models and material textures | `ItemView`, `Items.look` and the existing redress composition |
| Animated creature models | `Paperdoll` / `EIUnitModel`, using the prototype's appearance |
| Mechanics examples and active rule | `Items`, `Spells`, `Skills`, `Combat.aim_penalty`, `ai.reg`, current session rules |

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

The encyclopedia is introduced in 1.6.0 under the [versioning policy](versioning.md).
