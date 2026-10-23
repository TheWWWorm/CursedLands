# Autochess equipment and alliance improvement plan

Implementation starts from stable 1.24.0 and the following commit
`5521491c6980669f1ed46ed18aa70a3af259cd40`. This document records the plan
presented on 23 October 2026 and the requirements for its playable implementation.

## Player experience

Choosing the carrier of an item changes a creature's role. Positioning and team
composition change what an alliance can do. Upgrades keep each recruit recognizable
while giving its three star ranks visibly different stages. Several compositions
must have useful counters, and supports must be evaluated by their contribution.

## Reference designs

- [Drodo's introduction](https://ac.dragonest.com/en/gameIntroduction) describes
  three-copy evolution and overlapping race/class synergies from distinct pieces.
- [Auto Chess equipment](https://ac.dragonest.com/en/equipment) illustrates
  on-hit effects, support ranges and power with drawbacks. Its component recipes
  add a separate learning and balance cost.
- [Underlords hands-on](https://www.oneesports.gg/dota2/dota-underlords-is-plenty-of-auto-chess-fun/)
  documents one item slot per hero. This is a contemporary secondary source.
- [Valve's Season One notes](https://store.steampowered.com/news/posts/?appgroupname=Dota+Underlords&appids=1046930&enddate=1588974336)
  document scheduled item choices and the Vigilant alliance's reaction to enemy
  casting. Knights reward proximity and protection from appropriate directions.

These are structural references and dated examples, not claims about the current
competitive meta or numeric targets for Cursed Lands.

### Item interface reference

The supplied Goonikon recording, *Let`s play Dota Underlords Top Meta Build!*,
provides the direct visual and interaction reference for the equipment UI:

- **04:40**: three centered reward cards over the dimmed board. Circular item art
  overlaps the card header; the name and readable effect description form the
  decision. Choosing a card returns to the board.
- **04:46**: owned item icons remain in a compact tray beneath the alliances.
  Hovering enlarges the item and exposes a nearby, dark description panel.
- **04:48**: an item follows the pointer onto a creature. All friendly field and
  reserve creatures show circular equipment slots while assigning the item.
  Empty and occupied slots make the available destinations visible.

Replace the initial modal inventory and recipient dropdown with this direct
board interaction. Retain the existing HUD's alliance position and place the
tray beneath it. Use distinct illustrated icons for the eight Cursed Lands
items, shared by rewards, tray, creature slots and descriptions. Equipped items
remain visible in the tray with their carrier identified. Dragging or selecting
an icon then clicking a creature assigns it; moving an item between carriers,
replacing an occupied slot and returning to the stash use the same ownership
rules. Invalid targets and cancellation preserve inventory and formation.

Provide keyboard access to the same creature targets. Combat and scouted boards
allow inspection but never change equipment. Tooltip, carry and reward states
must remain distinct, and a phase/board change cancels assignment. Check actual
press/move/release input and all three languages at both desktop resolutions.
The reference's item tiers and reward reroll are separate economy mechanics;
the existing eight-item reward rules remain the implemented design.

## Equipment requirements

Eight items: Vampiric Fang, Storm Shard, Venom Seal, Ward Stone, Guardian Knot,
Echo Rune, Thorn Shell and Berserker Charm. One slot per recruit and a shared stash.
Preparation permits free reassignment; combat freezes assignments. Selling returns
equipment, and evolution preserves the retained creature's item while returning
items from consumed copies. All inventory survives saves and undo safely.

Each surviving player gets three deterministic choices after rounds 3, 5, 10, 15
and subsequent multiples of five, independent of victory. Unchosen offers settle
to the first displayed item in the stash when preparation ends. Bots follow the
same ownership and reward rules. A separate random stream keeps item choices from
changing shop results. Existing saves start with an empty inventory and do not
receive accumulated historical awards. Equipment uses arena effects and keeps
native monster weapons, spell cadence and campaign equipment unchanged.

## Alliance requirements

Keep distinct deployed family counting and frozen start-of-battle membership.
Replace the six static alliance bonuses with bounded tactical behaviors:

| Alliance | Behavior | Counterplay |
| --- | --- | --- |
| Beasts | Different members attacking the same prey trigger a pack attack; deeper investment transfers prey marks. | Screening and separated threats. |
| Horde | A fallen member triggers limited retaliation from survivors. | Control the first casualty and disrupt retaliation. |
| Warriors | Guard nearby allies against a limited amount of incoming damage. | Separate protectors and targets; punish clustering. |
| Hunters | Prioritize reachable enemies that cast spells. | Protect casters with screens and positioning. |
| Mages | Spells from different members combine into a bounded reaction. | Interrupt casting and spread targets. |
| Spirits | Fallen members release nearby aid; deeper investment creates one temporary echo. | Control recipient position and prevent repetition. |

Show triggers, range, recipients and limits in localized help. Generated damage
cannot trigger on-hit or on-cast bonuses. Death effects on original recruits
retain their separate per-battle limits. Summons cannot multiply rewards, alliance counts,
death procs or carried equipment. All durations advance on simulation ticks.

## Roster and balance requirements

Append Orc warriors and Woodsfolk seers as distinct recruit roles, preserving
existing family IDs and saves. Native paths are orcmalef3/f5/f7 and
driadgreenm7/driadsnowm9/driaddarkm11. Verify three outfit/palette stages in field
models, previews and portraits at actual camera sizes. These retain existing rigs.
Preserve the bat palette/name correction from commit 47b7a868.

Rerun native combat before tuning. Historical supported-team fixtures flag
three-star Banshees, Cyclopes and Skeletons for possible buffs, and Dragons and
Elementals for possible nerfs. Those contextual scores are not human win rates.
Compare useful damage, healing, survival, casts, range, armor, counters and cost;
evaluate no-item baseline and intended combinations separately. Retain multiple
viable economy and composition policies. Adding recruit roles also requires
checking acquisition and promotion cost rather than combat alone.

## Delivery and validation requirements

- Item conservation, invalid input, old saves, undo, sale, both merge stages,
  full reserves, combat shopping and pending choices.
- Actual combat triggers on both teams, correct damage source types, once-per-cast
  semantics, cooldowns, recursion protection and no campaign effects.
- Playable preparation UI, inventory, reward choice, creature/scouting details,
  keyboard focus, and visible feedback explaining alliance/item outcomes.
- Bots purchase, assign, position and use the same items and alliance rules.
- Solo worker and online commands/snapshots preserve round equipment; host validates
  choices and assignments. Ghost armies copy equipment without granting ownership.
- Native matched-seed combat and complete tournaments, 1x/2x and rendered/headless
  behavior, duration/timeouts, and performance on nine boards.
- EN/RU/DE coverage includes all names, help, errors, status and dynamic strings;
  inspect layouts at 1280x720 and 1920x1080.
- Development profiles set confine_mouse=0, show_fps=1, volume_sfx=0,
  volume_stream=0, volume_voice=0 before launch. Original preferences stay intact.
- Save compatibility and immutable published artifacts remain required. Any future
  release with these compatible features uses a new minor version based on the
  latest published stable release at publication time.

## Implemented result

The equipment, six behavioral alliances, two recruit lines, targeted balance
adjustments, bot planning and localized controls are implemented on
`feature/autochess-equipment-alliances-20261023`. The item inventory uses schema 14;
online autochess uses protocol 2 and matching builds. Shields share one remaining
pool per carrier, measured in whole-creature health even for native head/limb
hits. Item and cast effects use native impact/dispatch hooks and simulation time.
Temporary spirit echoes use the same actor factory and replication as recruits.

Validation and the remaining limits of the balance sample are recorded in
[the implementation check](../validation/autochess-equipment-alliances-2026-10-23.md),
[the roster comparison](../validation/autochess-roster-2026-10-23.md) and
[the interface check](../validation/autochess-equipment-ui-2026-10-23.md).
This is an unpublished feature branch. A future release containing these
compatible features needs the next minor version, chosen from the then-current
published stable release.

The goal is complete only after these behaviors and evidence are present. A small
playable slice is an intermediate milestone, not a reduction of the requested scope.
