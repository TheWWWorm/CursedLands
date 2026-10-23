# Lost in Astral official 1.01 / 1.02 investigation

The two supplied installers must be treated as **CD → 1.01 → 1.02**. Version
1.02 is not cumulative: it supplies three replacement files and omits fourteen
files needed from 1.01. Its bundled notes repeat the 1.01 changes, but its
payload does not contain them all. This conclusion concerns the resulting
content; the Windows installer's version checks were not executed.

The remake now includes the verified official 1.02 corrections. Players supply
the supported LiA main data from CD, 1.01 or sequentially patched 1.02; the
loader produces the same corrected behavior automatically. The Windows patch
installers are not needed at runtime. The source files remain unchanged.

The implementation normalizes 12 map scripts, three database entries, the
zone25 blocker and 16 text entry identities. It also migrates old VM
continuations and recovers missing quest watchers. The existing remake
implementation already supports the final executable's ground-spell behavior.

## Inputs and method

Investigation date: 2026-10-23. Remake source baseline: `e01d9fbd`.
The isolated working directory is
`/home/llm2x/Documents/EI/local/scratchpad/lia-official-patches-20261023`.

| Input | SHA-256 |
| --- | --- |
| `Lost In Astral/eia101r.exe` | `ef30af2b8e57384d0e542ba173cc6934665c095f9b924b25b6df788eeca8e495` |
| `Lost In Astral/eia102r.exe` | `25daa2fafc28e23a00a79318de69ff99146cd01aef0482da2e85ca0c1b2d6b51` |
| CD `game.exe` | `f04a305b77c84ea29c18ad2996d23072ccef1c0c46876c9b93bae4ce9351d1ff` |
| 1.01 `game.exe` | `3f84fb45a8911f5c0071286232f58d40daeb24546e90ee6daa47f853f31f1f52` |
| 1.02 `game.exe` | `9ecd475f5776681b8ffe1a8bb05cf67fe7adcceb62d0949135261ed7d3616c12` |

The baseline was `inspection/lost-in-astral/game`. The existing
`LostInAstral-ru.eipack` was also inspected: its executable, database, texts,
zone13 and zone16 entries all match the CD baseline byte for byte. This was a
five-entry check, not a comparison of every entry in that pack.

Both installers were extracted offline: libarchive read their embedded CAB,
then unshield read the inner InstallShield 6 cabinets. No Windows executable
was run. The comparison covers all game payload files, RES entry identities,
typed database fields, decrypted MOB scripts and non-script MOB fields.
REA provided static native function analysis. Remake checks used Godot 4.7.

`patched-game` in the investigation directory contains a separate merged view
of the CD plus 1.01 plus 1.02. It uses symlinks to the owned input files; it is
a test fixture, not a new installed player profile. Do not write through those
links. No original installation, data pack, player save or player preference
was replaced.

## What the patches change

### Payload and map scripts

1.01 replaces 17 game files: `game.exe`, `starter.exe`, `res/database.res`,
`res/texts.res` and 13 MOBs. Twelve MOBs change scripts only. The thirteenth,
zone25, adds an object without changing its script.

1.02 replaces `game.exe`, `res/texts.res` and `maps/zone16.mob`. Within the text
archive, its only difference from 1.01 is the version label, v1.01 → v1.02.

The table describes observed script changes; English quest titles below are
translations of the Russian source names, not newly supplied localization.

| Map(s) / quest | Observed change |
| --- | --- |
| `zone11dun2` / Babur's Mine exit | Guards the startup reset of `z.gz9g` so an already-open route is not reset in the same way. |
| `zone13` / Path to the Healer | Moves initial lever disabling into a first-visit block. Registers the later quest watchers together and adds explicit stage conditions, instead of relying on an uninterrupted chain of watcher launches. |
| `zone14` / Road under the Mountain | Registers the final watcher from WorldScript and requires the final quest stage before the exit-area check. |
| `zone16` / Magic Sphere | Enables lever 4948 during quest setup and starts the later watcher there, rather than after the preceding delayed sequence. |
| `zone16` / A Taste of Freedom | Uses lever 4955's actual state instead of the one-time `zone16_fq10` flag to admit setup. |
| `zone21` / Barrier | Uses lever 2016001's state instead of `zone21_fq16`. |
| `zone23` / The Pack | Uses lever 4216's state instead of `zone23_fq15` and removes that flag's setup write. |
| `zone1dun2` / Secret Dungeon gate | Adds a watcher that disables lever 1032949 after activation and `Sleep(10)`. |
| `bz31j`, `bz32j`, `zone32` / Quiet Cemeteries and Duel | Gates the next offer on the completed cemetery quest, offers the duel briefing from the next hub, and moves Jigran1 party creation/copy/redeployment into a guarded zone32 watcher. |
| `zone31` / New Alloy | Registers the final watcher during initial setup, before the preceding interaction has completed. This change is not separately named in the patch notes. |
| `zone7` / Courier | Replaces two small circular triggers with a protagonist-position test, Y < 163. This change is not separately named in the patch notes. |
| `zone16`, **1.02 only** / Double Portion | Removes the `zone16_fq12 == 0` prerequisite from the setup watcher. After the paid briefing is completed, the two quest levers can be enabled again. |

The zone25 addition is object 33398729, template `stst151` / `FakeBox00`, at
approximately (99.022, 168.831, -0.1), with complexion (0.01, 0.4, 0.2).
Object count rises from 797 to 798. The remake already treats this template
as an invisible map blocker while retaining collision geometry in
`game/src/ei/figure.gd`. The patch does not identify the purpose of this
particular blocker; connecting it to a named crash would be speculation.

### Database and text changes

Only `items.idb`, `units.udb` and `acks.db` change inside `database.res`.
Quest, spell, perk, lever and other database entries remain byte-identical.

* **26 material records:** absorption coefficients change. Snow tiger hide
  changes from approximately [4.63, 4.63, 3.70, 4.63, 4.63, 4.63, 4.63] to
  [2.7, 2.7, 2.7, 2.7, 2.7, 2.7, 2.7]. Many other materials also receive
  uniform coefficients across damage types.
* **43 Hadagan armor records:** main and/or secondary absorption arrays
  change. Examples include secondary base absorption on the low shirt and
  pants, 4 → 2, and boots/gloves, 2 → 1. The remake already multiplies the
  appropriate armor-layer factors by material resistances in `Items.armor_layer`.
  These are actual input-data changes, not just a tooltip wording correction.
* **82 acknowledgement/reaction records:** seven hero/companion records
  change bored-line context masks and selection chances; 75 NPC reaction
  records change chances and some sound paths. The exact comparison contains
  262 context-mask changes, 1,109 chance changes and 30 sound-path changes.
  `EIAcks` already reads and uses these fields.
* The other **289 changed database rows** contain opaque fields in hit
  locations, race models, quest items and loot items. Several shift by a
  common address-like offset. Their meaning is unresolved. The fingerprinted entry deltas retain the exact
  official bytes, but these must not be described as 289 gameplay fixes.
* The 1.01 text archive changes 16 entry identities: two additions, seven
  modifications and seven removals. Changes include the Mushroom Stew
  directions, several typos, a weapon-damage typo (31–24 → 31–34), a cheetah
  item name, two citizen names and removal of seven development-related
  entries. 1.02 then changes only the version label.

The input patches contain Russian text. The corrected quest documents, citizen
names and cheetah description also have English and German entries in
`RemakeText.t`. The version and numeric damage correction are language-neutral.
The four quest translations and the cheetah wiki reference use the corrected
source text. No new player option is required.

### Original executable

All three `game.exe` files are 2,617,344 bytes. The 1.01 executable changes
666 bytes relative to CD, including the PE timestamp. Its changed function
at VA `0x4c7110` gains an early return when the pointer at `this + 0x198` is
null. Static analysis identifies that pointer as the spell/order target.

1.02 restores that function to the CD bytes and changes a call at
`0x4c8b98`: `E8 73 E5 FF FF` → `E8 23 E8 FF FF`, redirecting the call from
`0x4c7110` to the existing validation wrapper `0x4c73c0`. Relative to CD,
the final executable differs in just **six bytes**: four timestamp bytes and
two call-displacement bytes. This statement applies to `game.exe`, not the
launcher or data files.

The wrapper validates the order, conditionally validates an actual target,
dispatches to the original function when valid, and handles invalid orders
through failure acknowledgements/order cleanup. The interpretation that this
fixes 1.01's rejection of point-targeted magic agrees with the bundled 1.02
notes. It is a static inference, not an observed original-engine execution.
Do not port 1.01's blanket null-target rejection into the remake.

The remake already distinguishes a lost unit target from an intentionally
targetless point spell in `GameUnit._do_cast`, and passes ground coordinates
through `Spells.cast_unit` and `Spells.apply`. Runtime checks confirmed fire
wall, lightning wall and acid fog consume stamina, finish the cast order and
create their effects at the selected ground point without a target unit.

The official notes also claim a General Game Error fix in Foothills/Ruins.
No original Windows crash was reproduced here, so its precise cause and the
relationship to individual payload changes remain unverified. The substantially
changed `starter.exe` was inventoried, not exhaustively reverse engineered;
the remake does not execute it.

## Built-in implementation

`AstralPatches` contains the admission checks and applies generated deltas from
`astral_patch_data.gd`. The generated payload is 139,438 bytes and contains
changed values/statements and save-position mappings, rather than whole game
archives, maps or executables.

* The 12 known map-script ASTs normalize to the exact final official AST before
  the existing remake/co-op adapters run. CD and 1.01 inputs have separate
  fingerprints where necessary. Already-patched input is idempotent. A modified
  AST does not match and is left to its author.
* The LiA campaign database reader applies sparse, input/output-checked byte
  corrections to `items.idb`, `units.udb` and `acks.db`. The resulting entries
  match the official bytes, including all acknowledgement masks, chances and
  paths. The alternate-campaign wiki reader uses the same corrections. Remake database mods apply afterwards; explicit archive replacements
  retain priority. The original campaign and LMP database are excluded.
* `GameData.read_file` applies the exact zone25 object delta in memory. It
  produces a byte-identical official MOB and preserves any modified MOB.
* Text corrections likewise require a known input hash. Added citizen names
  work even though the CD archive has no entries for them. Removed development
  entries resolve to empty text. Corrected localized prose uses `RemakeText.t`.
* Both known zone13 editions remain admitted by the guarded co-op trap adapter.

### Saves and zone revisits

New saved VMs carry a LiA patch revision and canonical script fingerprint.
They resume with the same block/instruction positions across all three owned
asset editions. Legacy VMs have no content stamp, so the loader maps their
positions from the recognized source edition to the canonical AST, retaining
locals, remaining sleeps and other saved state. Removed event blocks are
retired; relocated blocks resume their corresponding original work.

Restored zones also need watchers that their saved WorldScript never started.
The migration adds these selectively, checking live threads and pending calls
first. It repairs purchased, unfinished quest levers, continues healer stages,
and installs the newly added final-stage and dungeon watchers. It does not
restart the whole world or replay quest rewards. The pre-quest healer lever
state is corrected while an active quest keeps its progress.

A completed CD Jigran party transfer is recognized before the corrected
zone32 watcher can run, including the destination's first load. It advances
the guard without copying the player's loot/stats again. An old premature
cemetery offer is withdrawn only if it has not been consumed.

Legacy saves do not identify their original asset edition. Migration assumes
those old saves still use the assets with which they were created. A user who
manually changed editions before upgrading may already have ambiguous saved
instruction indices; the code cannot reliably reconstruct missing provenance.
New stamped saves remove that ambiguity for subsequent changes of edition.

### Rebuilding the generated corrections

Create separate CD, CD+1.01 and CD+1.01+1.02 fixtures from owned files. Run
`tools/tests/astral_patch_sources.gd` through the normal `--tool` entry point,
passing `--lia-cd-root`, `--lia-101-root`, `--lia-102-root` and
`--lia-ast-output`. Then run:

```sh
python3 tools/build_astral_patch_data.py \
  --ast /path/to/ast-sources.json \
  --cd /path/to/cd --patch101 /path/to/101 --patched /path/to/102 \
  --output game/src/ei/astral_patch_data.gd
```

A fresh export and regeneration matched the checked-in payload byte for byte.
The tests compare the generated output to the independently extracted official
files, rather than using the delta generator itself as the expected result.

## Validation and evidence

The machine-readable receipt is `lia-official-patches-2026-10-23.json` beside
this report. All runs use isolated profiles with a free cursor, FPS enabled and
music, voice and SFX muted. Headless runs use the Dummy audio driver. The journal
layout run uses the real OpenGL renderer.

Final implementation checks:

* `astral_official_patches.gd`: **329/329** on each of CD, 1.01 and 1.02, and the imported CD data pack.
  Each run independently compares every changed script, complete database
  entry and blocker against official 1.02, checks source preservation and
  custom-data rejection, and exercises legacy/canonical save continuations,
  suspended setups, new watchers, paid lever recovery and party-transfer guards.
* The existing CD `.eipack` was imported through the game's normal importer
  before those packed-data checks. A direct `.eipack` path is not a valid
  `--ei-path`; that switch accepts the imported folder.
* `astral_paid_topics.gd`: **825/825** on each of CD, 1.01 and 1.02. Raw-source
  checks respect each edition; runtime checks require normalized 1.02 behavior.
* `astral_official_patch_guards.gd`: **63/63**, including changed caller/body
  rejection and co-op adaptation after normalization.
* `lia_trap_registration.gd`: **27/27** on both CD and 1.02, using actual ENet
  host/guest sessions, late arrival, death/revive, save/load, reconnect,
  completion and deliberate reactivation.
* `astral_patch_journal_ui.gd`: **128/128**, rendering all four corrected quest
  documents in EN/RU/DE at 800×600 and 1280×800. Screenshots were inspected for
  readable wrapping, preserved objectives and scrolling where needed.
  Retained captures: [English](lia-official-patches-2026-10-23/journal-en-800.png),
  [Russian](lia-official-patches-2026-10-23/journal-ru-1280.png),
  [German](lia-official-patches-2026-10-23/journal-de-800.png).
* Translation coverage and `git diff --check` pass. The generated corrections
  reproduce exactly from a fresh parser export.

The earlier native-ground-spell check passed 18/18 without an engine change.
Original Windows crashes and full campaign playthroughs were not reproduced.
The final suites total **4,036 passing assertions**. These counts establish the stated content and prepared-scenario
coverage, not universal campaign correctness. Existing Cyrillic diagnostic
warnings remain in ENet runs; final test logs are scanned for script/runtime
errors as well as failed assertions.

Reusable local evidence in the investigation directory:

| File | Scope |
| --- | --- |
| `compare_patches.py`, `comparison.json` | Complete sequential payload comparison and typed field differences |
| `diff-101/`, `diff-102/` | Decrypted before/after scripts and unified diffs |
| `patched-game-manifest.json`, `existing-pack-comparison.json` | Staged data provenance and bounded existing-pack check |
| `acks-changes.json`, `native-delta.json` | Exact acknowledgement fields and executable byte offsets |
| `rea-installer-evidence.json`, `rea-native-evidence.json` | Retained static-analysis evidence |
| `run_check.py`, `probe.gd`, `ground_cast_probe.gd`, `runs/` | Isolated test runner, integration probes and raw logs |

REA evidence IDs:

* Installer identity: `ev_0e28b29c606b5c35f2e5c8b5b802389d4adf4b564395ffcf4b011251ae01f69e`.
* Validation wrapper `0x4c73c0`: `ev_2af8d1127efbdf025fae3c77733059fbd274c1a47dcec3e7cf9241b5a3aa6b9b`.
* Changed-call containing function resolution: `ev_ce83fe34a11bd9f543704e8e1208efeb01d917cc8ba97776a771308417c88a9f`.
* Caller `0x4c8890`: `ev_89548b6bb5621fe5b1abbd35061418d39365fe1f18a187ca702892415686617d`.

The original patch dependency and complete data changes are established by
static comparison. The built-in normalization, representative old-save
migration, ENet trap behavior and corrected journal layout are runtime-tested.
Launcher behavior and every possible historic save state are outside the
verified scope.
