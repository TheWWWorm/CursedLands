# Dialogue-trigger comparison family

This extension family adds dialogue checks to the
[original-engine comparison suite](original-parity.md). It compares
conversations started by campaign (GS) variables, for example
`b.<npc>.<id> = 1`, with the remake's production `Briefings` and `ScriptVM`
code. It runs the original executable's instructions in Unicorn. No dialogue
rule is reimplemented in Python. The files are:

- `tools/parity/cases_ext_dialogue.py`: contracts, inputs and validator
- `tools/parity/native_ext_dialogue.py`: native captures
- `tools/parity/remake_ext_dialogue.gd`: remake captures
- `tools/parity/test_ext_dialogue.py`: harness tests (no game data required)

Every input is an **ordered list of GSSetVar writes** plus the clicked unit,
zone, party or briefing row. Each side applies those writes through its own
store. The native side constructs the player's GS hash with its constructor
(`581790`, 193 buckets) and fills it through its GSSetVar store (`460bc0`).
Zero values delete entries, and table growth to 389 buckets happens as it
would in play. Hash and collision-chain order is never built by hand. The
remake uses `CampaignState.set_var`, which maintains its `GSTable` mirror.

```sh
V=/path/to/venv/bin/python
$V tools/parity/run.py --list --case dialogue_
$V tools/parity/run.py --game-dir /path/to/original --godot /path/to/godot \
  --out /new/results/dir --case dialogue_
$V -m unittest discover -s tools/parity -p 'test_*.py'
```

## Kinds

| Kind | Native routines executed | Remake entry | Observation |
|---|---|---|---|
| `dialogue_topics` | `608b20` → `607320` (`578c40`/`460ee0` filtered copy of `b.*`, `4dbe40` split, `461360` name id, `60b2f0`/`60b400` online sort), `607880` row title | `Briefings.interact` (`topics` event) | Dialog open flag, ordered topic ids, row titles |
| `dialogue_zone` | `602c90` leader check up to `6064a0` (zone record `45e850`, `b.%s` filtered copy, first `== 1` three-part key) | `Briefings.tick` → `play_named` | Started flag and briefing id |
| `dialogue_merc` | `591800` RecalcMercBriefings (`66edd0` GSSetVar, `460af0` GSGetVar, party count, home-zone table `7907ac`) | `ScriptVM.recalc_merc_briefings` | All non-zero `b.merc*` / `amerc_*` variables |
| `dialogue_complete` | `592090` (`591de0` mercenary topics → `591800`, money, `66ee40` GSSetVarMax(.,1) / `66edd0` GSSetVar(.,2) reward lists, `WorldScript( GSSetVar(..,2) #OnBriefingComplete(..) )` text) | `Briefings.complete` | GSSetVar/#OnBriefingComplete arguments, money, experience grants, hire/remove events, all other GS variables |

The native topic list ends with a `goodbye` row appended by `608b20`. The
capture verifies that the row is present and then removes it. The remake's
`DialogPanel.show_topics` appends its own farewell row outside
`Briefings`.

## Supplied boundaries (stubs)

These are listed per kind in `cases_ext_dialogue.contracts()`.

- The fixture heap handles `operator new`/`delete` (`70056f`/`700598`),
  `malloc`/`free` (`6eab91`/`6ea86d`) and the MFC `CFixedAlloc` CString
  pools (`6e6bf1`/`6e6c80`). Their static constructors never run in this
  bounded replay.
- Each KERNEL32 IAT slot is a trap. Only `lstrlenA`,
  `Interlocked{Increment,Decrement}` and the critical-section calls are
  supplied; critical sections are single-threaded no-ops. Any other import
  stops the capture with its name.
- The CRT tables `_mbctype`/`_mbcasemap` (`7cc160`/`7cc060`) are supplied
  for ASCII letters, as `_setmbcp` fills them at start-up. Without them,
  `_mbslwr` in `607880` does not lowercase.
- Player-zero lookup (`594180`), current player (`5699f0`) and the
  single-player or multiplayer flag (`57f440`).
- Topic texts form a one-member archive behind the `texts.res` lookup
  (`4defc0` vtable `+0x14`), matched exactly against supplied lowercase
  keys. The native line reader `4df8d0` still runs. The remake receives
  the same texts through `GameData._text_cache`, restored afterwards.
- Presentation is stubbed: topic-list drawing and scrolling (`5ff830`,
  `5fc9e0`, `65afa0`, vtable `+0x64`, `6071a0`), camera and selection
  marks (`566030`, `40d3b0`), and conversation staging (`6064a0`, recorded
  as the start event).
- For mercenaries, the fixture supplies the world player list, network peer
  and stream, party vector, unit lookup (`55fb00`), unit dead getter (vtable
  `+0xdc`) and prototype name (`530930`). On the remake side, a hired
  mercenary is `st.mercs[i]` in the current party. A dead one also has
  `adeadn<i> = 1`, as `GameWorld` records a mercenary death.
- For completion, the `briefings` database row (`4297a0`) supplies
  experience `+0xc` and money `+0x10`. Its four variable lists
  (`+0x2c/+0x38/+0x44/+0x50`) are mapped in database column order to
  `give_quests`, `give_quests2`, `open_zones` and `unknown2`. That mapping
  is an assumption; the max-1/set-2 pattern agrees with it. Item lists are
  empty. Experience distribution (`5911c0`) and party hire/remove
  (`662890`/`6620b0`/`5935c0`) are recorded, not performed. The remake's
  `give_experience`/`merc_changed`/`sync_state` are recorded the same way.
  The emitted WorldScript text (`4d23a0`) is recorded; its arguments are
  read from the executable's fixed format, and it is not executed.

## Limits

- Player zero and single-player GS stores only, except that
  `dialogue_topics` covers the multiplayer sort. ASCII keys only.
- No village command gate (covered by `village_gate`), Astral paid offers,
  smith assortments or co-op mercenary overlays.
- No topic selection or playback, movie deferral, 0.5 s poll cadence, side
  quests (`sq.`), multiplayer quest givers, items, smile faces or script
  handler bodies.
- Zone names are lowercase, like remake zone ids.
- Lost in Astral addresses are not qualified for this family. Every
  contract returns `{}` for `lost_in_astral`.

## Proof that the family can fail

`--game-source` was pointed at a scratch copy of `game/` with four mutants:

1. `pending_for` keeps the first `constr*` instead of the last.
2. `Briefings.tick` accepts values `>= 1`.
3. `recalc_merc_briefings` uses `hired < 3`.
4. `_rewards` adds one extra coin.

Run `dialogue-03-mutant` reported **44 differences instead of 19**. The 25
new mismatches covered all four kinds: 5 topics, 6 zone, 2 merc and 13
complete. Unit tests also reject malformed observations for every kind.

## Latest results

`results/dialogue-04`: **158 scenarios, 139 match, 19 differ**
(seed 20261020, fuzz 12). Both sides were repeatable over two captures.

| Scenario | First difference | Original | Remake | Interpretation |
|---|---|---|---|---|
| `dialogue_topics/spaces_in_key` | `topics` | `t4, t1, t2, t3` | `t4, " t3"` | Native `4dbe40` trims each dot-separated part, so `b. smith.t1` belongs to Smith. The remake splits without trimming. |
| `dialogue_topics/name_differs_from_id` | `topics` | `t1` | `t1, t2` | Native matches the owner only by name-hash id. The remake also accepts the unit's lowercase `info.name`, so `b.shaivar.t2` appears on the unit whose id is `OrcC`. |
| `dialogue_topics/titles` | `titles[2]` | `"  Padded title  "` | `"Padded title"` | Native `607880` keeps the first line verbatim. The remake strips edges. Cosmetic. |
| `dialogue_zone/prefix_collision`, `seeded_010` | `briefing` | `far` / `constr2` | none | Native filters with `b.%s`, with no trailing dot, so in `zone1` it starts a pending `b.zone10.*` briefing. The remake requires `b.zone1.`. Campaign zone ids end in a letter, so no shipped pair is known to collide. Latent native quirk. |
| `dialogue_zone/four_parts` | `briefing` | none | `a.b` | Native requires exactly three parts. The remake starts `b.zone1.a.b` as id `a.b`. |
| `dialogue_zone/spaces_in_key` | `briefing` | `x` | `" x"` | Same part trimming as for topics. |
| `dialogue_zone/many_b_keys`, `many_b_keys_alt`, `seeded_007` | `briefing` | `first` / `mid` / `quest` | `second` / `alpha` / `n11_1` | With two or more pending zone briefings and more than 193 `b.*` keys, the order differs. Native copies only `b.<zone>*` keys into its 193-bucket temporary table. The remake copies every `b.*` key, so its temporary table grows to 389 buckets and traversal order changes. |
| `dialogue_merc/two_guests`, `seeded_008` | `b.merc5.n9_5` / `n9_*` | party full (`n9`) | hire offered (`n1`/`n3`) | Native counts every living party member except one, including non-mercenary companions. The remake counts only living hired mercenaries. |
| `dialogue_merc/dead_hero` | `b.merc5.n1_5` | hire offered | party full | Same rule: a dead hero is not counted natively, so the original offers hiring with two living mercenaries. |
| `dialogue_complete/two_part_key`, `four_part_key` | `money` | 100 | 105 | Native applies `briefings` rewards only for a three-part key. The remake looks up the last component and pays rewards for `b.smith` and `b.smith.t1.x`. |
| `dialogue_complete/merc_dismiss_not_in_party`, `merc_farewell_not_in_party`, `seeded_000`, `seeded_005` | `merc_events` | `[[n, "remove"]]` | `[]` | Native `591de0` always asks the party to remove mercenary `n` for `n2_n`/`n10_n`. The remake does so only when the mercenary is in that player's party. This is probably benign when the mercenary is absent; the variables match. |

All other observations match. These include the topic order in hash
order, owner case-insensitivity, last-found `constr*`, the multiplayer
`_stricmp` sort, dialog open/closed state, missing texts as blank rows,
growth/rehash and delete/reinsert order, zone values other than 1,
mercenary home-village dismissal, `n8`/`n10`/`amerc` transitions,
reward-list max/set semantics, money truncation toward zero, and the
mercenary hire events.
