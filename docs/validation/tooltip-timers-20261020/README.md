# Tooltip timer retention and campaign speed

The retained-object cause is reproduced and fixed in the desktop engine. Mouse
movement over a Control cancels the previous native tooltip callback, but Godot
4.7 leaves its SceneTreeTimer in the tree until its original deadline. The game
uses a 1,000,000-second native delay because its own TipLayer supplies localized
tooltips and a configurable delay. Cancelled timers therefore survive for almost
12 days, including after returning to the menu. SceneTree scans the timer list
in both idle and physics processing, explaining growth in both costs without
growth in scene nodes or the game's resource caches.

`cancelled-tooltip-timers.patch` sets the cancelled timer's remaining time to
zero in all three Viewport cancellation/replacement paths. Callbacks are
disconnected first, and the normal idle pass releases the timer. Active tooltip
delays, rendering, save data and network messages are unchanged. Updating the PCK
without updating the executable does **not** apply this engine fix.

## Matched runtime comparison

Each platform pair uses the same released 1.18.0 PCK and native helpers. The fixed
runtime adds only the three timer-expiry statements to the existing fifteen-patch
desktop engine. `engine-and-source.json` records the pinned source and hashes;
the command records contain the compilation, scene-library update and link steps.
Linux keeps a separate symbol-bearing build for inspection. Windows execution
uses Wine 9 with Vulkan on the Linux host, with its incompatible DirectInput
backend disabled. This is not a native-Windows hardware qualification.

| Check after 100,000 mouse movements | Released engine | Fixed engine |
| --- | ---: | ---: |
| Linux live objects | 102,082 | 2,083 |
| Linux objects after returning to menu | 105,064 | 5,068 |
| Windows/Wine live objects | 102,133 | 2,134 |
| Windows/Wine objects after returning to menu | 105,286 | 5,286 |

In a separate sequential Linux test of the same warmed menu, the released engine's
median frame time grows from 1.684 to 4.104 ms. The fixed engine stays at 1.699 to
1.672 ms. The physics monitor's median grows from 0.012 to 2.467 ms before the fix
and measures 0.013 to 0.130 ms after it. These are local synthetic stress results,
not predicted frame rates for another machine. The fixed run's initial interval
includes a large startup hitch, so its mean FPS is not used as a comparison.
Raw measurements are retained in `checks.json`; the repeatable fixture is
`engine_patches/godot-4.7/tests/tooltip_menu_cost.gd`.

## Real hosting

A separate four-minute rendered Trials hosting run starts the actual private
simulation worker and a second ENet player, recruits both teams through the
network, runs battles at 2× and switches scouted boards. A native ObjectDB census
identifies the retained classes and reads SceneTreeTimer deadlines.

The released build retains 388 tooltip timers after closing both connections and
returning to the menu. The fixed build keeps one active tooltip timer during play
and returns with zero. Other retained objects are warmed meshes/animation resources;
round progression and their cache sizes are not identical between runs. Debugger
pauses invalidate timing comparisons, so `hosted-object-counts.json` deliberately
omits those runs' timing measurements.

## Campaign speed

The session remembers the selected field speed separately from the effective
village/map rate. Field arrivals and cancelled travel restore that selection;
villages and route maps run normally. Saves carry an optional `field_speed` only
when the effective rate masks the preference. Older saves fall back to their
existing speed field. The private solo worker carries this preference with its
clock/save messages, while public co-op messages and protocol 23 remain unchanged.

The source checks pass 133 assertions: 65 zone/safe-zone/map/save/shared-clock
checks, 22 worker save/pause-clock checks, 35 campaign-feedback checks and 11
real-worker village-save checks. The final Linux preview repeats the 65 zone
checks and 11 worker checks successfully. Routes include gz15h → gz16h → bz14h
→ gz15h; the shared-clock fixture uses two ENet peers. Fixtures are in
`tools/tests/zone_speed_retention.gd` and `tools/tests/local_host_zone_speed.gd`.

## Tooltip behavior and previews

The unpatched runtime fails all 11 lifetime assertions in the regression fixture
while its six ordinary-tooltip controls pass. The fixed engine fixture passes
all 17 assertions on Linux and Windows/Wine, covering
100,000 hover events, paused play, zero/double time scale, viewport teardown and
ordinary native tooltip delay/content/show/hide behavior. The game's tooltip UI
fixture passes 24 assertions on both Linux and Windows/Wine, exercising EN/RU/DE, Off, paused simulation
and dynamic localized content. The three attached captures are visually inspected:
the text is readable, fits its panel and has no duplicate native popup. The
translation checker reports 2,809 entries and zero errors.

Local Windows/Linux previews are staged as `1.18.1-rc.1`; Windows file/product
metadata is `1.18.1.0`. The tracked release metadata remains 1.18.0 with an
Unreleased changelog entry. No published tag, asset or installed template is
replaced. Both preview packs contain the same 375 compiled scripts. The Windows
icon audit verifies all six embedded sizes against the approved transparent logo.
The previews include the rebuilt executable and the speed changes. Other platform
templates still require rebuilding with the timer patch.

All launches use isolated profiles with free cursor, FPS enabled and SFX/music/
voice volumes set to zero before launch. Normal player defaults and saved
preferences are unchanged.
