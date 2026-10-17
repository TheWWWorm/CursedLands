# Autochess roster and presentation

17 October 2026; integrated into 1.11.0 on top of stable 1.10.0.

## Recruitment and balance

The pool grows from 12 to 24 families, with 65 native prototypes across 72 star
ranks. The original twelve family indices remain unchanged, preserving saved
armies. The opening samples six distinct families from twelve eligible families,
with three melee and three ranged/magic offers. Later shops use level-dependent
tier odds and uniform selection within a tier. At level three, 55/45 tier odds
spread demand across five tier-one and seven tier-two families. A 20,000-pair
sample found an 8.815% duplicate rate, compared with the former pool's 19.33%
expected rate. Opening offers themselves do not repeat a family.

Prices and evolution recipes follow native fighting strength rather than island.
Wisps receive a Trials-only 2.4× health multiplier. Evil-eye and banshee evolution
forms, and the prices of woodsfolk archers, hill ogres, red harpies and wormheads,
were adjusted after matchup and expedition runs. Original database rows are not
modified. Tribe memberships include the new families; CPU shopping preferences
use traits instead of fixed lists of the original recruits.

All 220 possible distinct three-family opening combinations beat the first
encounter in the recruitment fixture. Paired-side native duels cover the new
families at all three ranks (864 fights). The four changed banshee/evil-eye rank
cases were rerun in the final package (96 fights): banshees won 7/24 and 12/24 at
two/three stars; evil eyes won 14/24 at both ranks. These are outlier checks,
not equal-price team comparisons or a claim that every matchup is equal.

The first expanded-pool expedition sample completed only 2 of 12 Standard runs
and none on the harder settings. The final version reduces extra late-wave
reinforcements to account for less frequent upgrades. Six deterministic purchase
policies, eight seeds each and three difficulties then produced:

| Difficulty | Runs | Completed | Battles | Time-limit results | Mean final wave |
| --- | ---: | ---: | ---: | ---: | ---: |
| Standard | 48 | 24 | 1,377 | 8 | 28.69 |
| Veteran | 48 | 5 | 1,207 | 17 | 25.15 |
| Champion | 48 | 2 | 1,114 | 5 | 23.21 |

The final sample contains 144 expeditions and 3,698 native battles; 30 battles
reached the time limit (0.81%). Every policy completed Standard in at least two
of its eight seeds. Veteran and Champion remain substantially harder. Surviving
wave 30 with a life remaining completes an expedition even if that battle was a
loss. These automated purchase policies are design samples, not human win-rate
estimates. The complete final summaries and traces are in
[autochess-roster-balance.json.gz](autochess-roster-balance.json.gz).

## Readability and layout

The contrast work used the [Game Accessibility Guidelines](https://gameaccessibilityguidelines.com/provide-high-contrast-between-text-ui-and-background/)
and [WCAG contrast guidance](https://www.w3.org/WAI/WCAG21/Understanding/contrast-minimum.html)
as references for text/background contrast and small type. Four actual game
captures compared near-black regular, black bold, warm brown, and white edged
text. The selected option is near-black regular (`#141414`) with no outline.
It is used for labels facing the snow. Shop information, reserves, tribes and
player rows have no new backing panels. Active tribes and the watched-player
edge marker use dark copper. This does not assert contrast compliance against
every moving scene pixel.

The HUD scales continuously from 1440×900, with no upper cap. Actual rendered
checks cover the reported 5065×2757 display, 1024×768 Russian and 1920×1080 German
layouts. The compact player rail uses 14-pixel reference names, a fixed health
column and ellipsis for long names; expansion exposes level and gold. The viewed
player has a three-pixel edge marker without a filled row. The final ten seconds
of preparation or combat pulse the clock and change its color. Main-menu utility
buttons remain at the bottom and match the top buttons' 64-pixel reference height.

The native roster gallery renders and inspects every new form in EN/RU/DE (145
assertions per language). The translation scan checks 2,563 entries, 141 dynamic
wiki keys and 141 dynamic Trials keys with zero errors. Existing archive titles
are retained, with remake translations for all added English keys.

## Battles, audio and effects

Opponent models stage one board per frame while formation and shop changes are
briefly locked. All nine boards then start together, and the combat shop reopens.
On the packaged 5K fixture, the request took 24.4 ms, individual staging steps
3.4–12.4 ms and the final shared start 25.0 ms. These are local observations on an
RTX 3090, not a frame-time guarantee on other hardware.

Particles, lightning and their bounds use the owning board's origin. Hidden
boards hide their top-level effect renderers. Switching boards restores the
viewed world's audio. Combat resolution stops damaging projectiles, drains the
remaining visual effects for at most 1.5 seconds, then frees them without advancing
health or combat time. Rendered assertions check origin, visibility, live CPU
sound dispatch, clock warning, staging, shop access and effect cleanup. Audio
checks used the Dummy driver; no listening assessment is claimed.

The final packaged tournament fixture passes 151 assertions through 169 native
fights, including pairing, economy, progression and termination. The former
freed-model callback warning is absent. Combat still ends at two minutes or ten
seconds without positive damage, with ten health deducted from both owners on
an Autochess draw. Filtered NPC spells hit both enemy targets and preserve allies
in the dedicated regression.

## Formation stall and integrated campaign fixes

The public save attached to [#19](https://github.com/TheWWWorm/CursedLands/issues/19)
previously stayed in formation arrival for more than twelve seconds. Arrival is
now bounded to two seconds for both armies; blocked movers settle at their saved
targets before combat. The public save enters combat at 2.017 seconds and completes.
The [updated report](https://github.com/TheWWWorm/CursedLands/issues/19#issuecomment-6235432765)
suggests an enemy-formation problem after repositioning owned units stopped
helping. A second test rearranges the owned army while preserving the exact enemy
formation; it also enters combat at 2.017 seconds.

The Lost in Astral tomb-exit and pause-menu fixes from the companion work are
included. The packaged build passes 36 tomb assertions, 21 pause-clock assertions,
28 composited pause-frame assertions and 58 build-version/layout assertions per
language. The clock fixture now uses an explicit 800×600 rendering workload;
its initial unbounded 4K run was rendering at roughly five frames per second and
failed its short-clip timing window. Larger layouts are tested separately. The
composited fixture retains normal, slow-frame, paused and accelerated cases with
the production separate render thread.

[Full release qualification and platform limits](release-1.11.0-2026-10-17.json).
