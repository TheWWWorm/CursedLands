# Integrated campaign, interface and co-op validation

This local preview combines the tooltip-engine and zone-speed fixes with the
campaign/interface changes and the two requested chat snapshots. Its staging
version is **1.19.0-rc.1**, based on published stable **1.18.0**. Tracked release
metadata remains 1.18.0 with an Unreleased changelog. No tag or public artifact was
replaced. Windows file/product metadata is 1.19.0.0.

## Guest controls and camera options

The multiplayer hosting page opens **Co-op settings**. Defaults for new campaigns
separately allow guest pause/speed and guest quicksave/quickload. The host can
grant each of those four permissions individually in **Players**. Defaults remain
host-only. Campaign saves contain both the defaults and individual grants, keyed
by the existing normalized reconnect identity rather than ephemeral peer IDs.
Loading restores that policy; changing an unrelated option does not reset it.

Guests use the ordinary speed dial, pause key, F5/F8, or Save/Load menu. Their
Save/Load menu actions request the **host's `quick` slot**; they cannot select or
name a file on the host. The authority validates the actual sending peer and its
current permissions, zone and load generation. These requests run outside the
guest-inventory context. A guest with speed permission alone cannot resume a
paused game. Public RPC signatures and protocol 23 are unchanged.

`coop_permissions.gd` passes 31 checks using two real ENet peers: default denial,
independent grants, forged sender rejection, slot restriction, menu requests,
reload, saved grants and reconnect under a new transport ID. The final custom
Linux export repeats that result. `local_host_permissions.gd` passes 19 checks
against an actual separate authority process, owner frontend and ENet guest,
including F5/F8, pause, revocation, saved-policy restoration and worker shutdown.
It passes on the final Linux executable and Windows executable under Wine.

Classic horizontal and vertical sensitivity are independent. Existing profiles
without a vertical value copy their existing horizontal value. Wheel zoom keeps
its previous sensitivity. Modern camera edge scrolling works over HUD controls,
while typing, modal inventory, held dragging, an unfocused window and an outside
pointer retain their input boundaries.

`camera_guest_options.gd` checks independent axes, actual viewport hover and
camera movement, legacy-setting migration, multiplayer settings access, per-player
buttons, translated choices and visible tooltip layout. Linux passes 42 checks
in each of English, Russian and German, including landscape and portrait layouts.
The migration test starts with a nondefault horizontal sensitivity of 36.
The final Windows executable also passes all 42 checks under Wine/Vulkan.

## Buff icons, wiki maps and character face

The enabled-by-default character option draws effect icons with remaining
seconds vertically at the upper right of the general character panel. Names
remain in the detailed effects view. The overlay uses simulation ticks, so pause
and speed changes affect the countdown correctly. The option label, both choices
and help are translated into EN/RU/DE.

`character_buff_icons.gd` passes 18 checks in each language on the custom Linux
export. It checks default-on, disabled and empty states, settings persistence,
visible help, three window sizes and the shared world/paperdoll face. Captures
cover 1280×800, 720×1280 and 1920×1080.

The protagonist now keeps the portrait's authored facial aspect ratio on the
world model; body training no longer applies independent axis stretch to the face.
Other characters keep their existing fitting rules.

Wiki map links from a creature enable creature markers and highlight that
creature with a contrasting ring. Mixed marker clusters keep matches separate.
The name field matches localized names without case sensitivity and leaves exit
and quest markers available. Back navigation restores the filter and highlight.
`wiki_creature_map.gd` passes 12 checks in each language on custom Linux, plus
12 checks on Windows/Wine.

## Suslanger and campaign behavior

The lion basin's two water triangles are separated from its scenery atlas and
use the modern water shader. The stone and collision stay intact. Turning off
new water restores the original surface. OpenGL and the qualified custom
Forward+ engine render the basin; the final Forward+ scene fixture passes six
checks, including shader bindings and both Baluddin camera shots.

Baluddin's `jf67` dialogue used stale rendered actor heights after an instant
logical placement. Staging now samples the destination ground height, including
on a host that does not render the actor. In the inspected shot the terrain was
at 11.968, the stale actor at 10.045, and the old camera eye at 11.795. The corrected
eye is 13.718. Both alternating shots are above the ground and show the actors.
The 18 dialogue-approach and seven obstacle-camera checks also pass.

Ordinary campaign patrols can lose distant opponents and investigate the last
seen position. Scripted aggression and arena pursuit remain persistent. New
enemy sightings alert nearby allies; a neutral friend reacts to an assault only
when it sees both victim and attacker. The patrol/witness fixture passes 14
checks, and perception equivalence passes 2,857.

The original Suslanger gate alarm repeatedly sent guards to the intruder's live
position, and its escape continuation required the guards to be dead. A narrowly
admitted compatibility change preserves the original alarm bodies, delays and
saved continuation indexes, but requires contact once the intruder leaves the
gate area and permits the living party to escape. Changed mod scripts retain
their own rules.

The actual original gate scenario passes 79 checks over two ENet peers, including
startup, save/load with an absent guest, reconnect, entry by the guest, dispatch
of all eight authored guards and completion with every guard alive after the
party is clear. Positions are controlled for the escape predicate; this is not
an end-to-end player-driven running route. Additional checks cover compatibility
(11), pending alarm state (70), captivity (35), prison progression (224), and
Lost in Astral traps (55).

Other changes associated with [issue 48](https://github.com/TheWWWorm/CursedLands/issues/48)
use the casting-specific stamina voice, preserve running in aimed combat orders,
and finish a replicated final partial stride at its approach speed. The relevant
fixtures pass 47 stamina, 14 network acknowledgement, 28 order and 33 presentation
checks. Nearby ally alerts address [issue 49](https://github.com/TheWWWorm/CursedLands/issues/49).
Guest controls and camera settings address the requested subset of
[issue 50](https://github.com/TheWWWorm/CursedLands/issues/50); this change does not
implement its separate mod-loader proposal.

## Door cost

Opening or closing a door previously discarded all prepared navigation block
paths. The native helper now invalidates only intersecting local search windows,
while global connectivity and seed caches are rebuilt. The script fallback and
older-helper fallback remain available.

On the supplied `gz18h` checkpoint, opening door 150158 took about 41 ms for the
obstacle update followed by 128 ms for the first path query. After the change the
same operations take about 46 ms and 17 ms. Closing changes from 35 + 118 ms to
39 + 10 ms. These are headless CPU measurements, **not measured frame rates**;
the obstacle-label update still has a cost. `door-costs.json` retains the samples.

The incremental graph is compared with fresh topology after seven edits across
11,102 assertions. Real Lost in Astral doors pass 140 native/scalar checks; the
existing topology fixture passes 7,072. The final Windows DLL passes the 11,102
checks under Wine. Linux, Windows and Android native helpers were rebuilt.
Android gameplay and a full APK were not qualified here.

## Supplied save archive

The 13 saves in the supplied archive decode successfully. The archive is not a
continuous history of the later screenshots:

| Checkpoint | Location/day | Relevant state |
| --- | --- | --- |
| `save7`, `save8` | `gz15h`, day 120 | Before Suslanger |
| `save9` | `gz18h`, day 128 | Before the fragment; quests 65/66 active |
| `quick` | `gz18h`, day 133 | Fragment and thief's sack present; quests 60–67 and 70 complete, 71 active |
| `autosave`, `save4`–`save6` | `gz1g`, day 1 | New starts |

There are earlier checkpoints; `save9` is the relevant pre-fragment one. None of
these saves records a visit to `gz19h`, which appears in the later guard/pool
screenshots. The quicksave's state is consistent with the original scripts.
The original dungeon chest permits taking the fragment before that quest is
active. The subsequent sequence still requires the path-plan/portal-key quests,
the Suslanger portal and the later Gipath ending. Merely taking the fragment
does not trigger an ending, and no ending state is present in this archive.
No new quest gate or modification to the player's saves was applied.

`save-audit-summary.json` contains only the relevant checkpoint/quest facts and
archive hash. Player inventories, character names and full save files are not
included.

## Long sessions and remaining uncertainty

The reproducible native tooltip-timer retention defect is fixed in the
**executable**. Its matched 100,000-hover comparisons, elevated menu-physics cost,
native object census and real short hosted run are documented in
[the tooltip validation](../tooltip-timers-20261020/README.md). The original
1.18.1-rc.1 previews mentioned there were an earlier validation stage; this
combined preview supersedes them locally. Copying only the PCK will not apply
the engine fix. A full multi-hour co-op campaign soak has not been completed.

The extreme Mines walking slowdown in
[issue 47](https://github.com/TheWWWorm/CursedLands/issues/47) was not reproduced.
The supplied `save2` was loaded into the actual separate desktop simulation
process with its NPC scripts intact. A roughly 12-metre walking route took about
8 seconds at normal speed and 4 seconds at double speed in hosted co-op, repeated
in both directions. Solo used its original 2.037× acceleration. The timing
samples are in `mines-walking.json`. This does not establish the cause of the
reported long-session slowdown.

The toad-spit animation complaint in issue 48 also remains unconfirmed and
unfixed. The original `ToadM1` attack is a 2.695-second vertex-morph clip; source
and rendered pose inspection did not establish the reported discontinuity.
Neither unresolved report is represented as fixed in the changelog.

## Integration and reproducibility

The completed, idle snapshots from **Enable HD Lands downloads on Android**
(`01a155c1-ed72-73a3-8349-feaa152999f3`) and **Fix Autochess start and camera**
(`01a155a0-d09b-7b43-9bd4-26674ecaecee`) are combined here. Source worktrees were
not modified. Their patch hashes and common base are in `merged-chats.json`.
The integrated donor checks cover creature feedback (65), retained damage (12),
elimination places (12), bounded snow (7), projectile origins (186), rendered
standings (18), snow/camera (20), post-battle presentation (22), mod downloads (76)
and download UI (43).

`checks.json` records the selected final successful runs and their renderer.
Earlier development failures were corrected or, for desktop-input interference,
repeated on an isolated X display. Renderer-specific stock-engine errors are
not counted as successful custom-engine checks. The full working logs remain in
the local scratch directory. The Windows UI fixture places its window at the
display origin to avoid Wine's desktop/client coordinate offset during automated
pointer warping; it then verifies actual pointer-based scrolling and tooltips.

All new player strings and dynamically selected option choices are covered by
`tools/check_translations.py`: 2,849 entries, 141 dynamic wiki keys and 179 dynamic
arena keys, with zero errors. EN/RU/DE layouts and help were visually inspected.
The Windows branding audit verifies all six embedded icon sizes against the
unchanged approved transparent master.

Every runtime check uses isolated development profiles configured before launch
with `confine_mouse=0`, `show_fps=1`, and all three audio volumes zero. Windows
execution here is Wine 9/Vulkan with its incompatible DirectInput backend
disabled, not native Windows hardware. Both desktop packages contain the
qualified engine, matching PCK/native libraries, license notices, validation and
a source patch. No normal player preferences were overwritten.
