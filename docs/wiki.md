# In-game encyclopedia

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

## Data sources

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

No release version is changed by this source feature. A release containing it
requires a minor version under [the versioning policy](versioning.md).
