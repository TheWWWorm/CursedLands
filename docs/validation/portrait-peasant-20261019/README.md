# Portrait timing and authored peasant encounters

Local validation on 19 October 2026. The starting source is `b7a04778`;
the production change is limited to `game/src/ui/portrait.gd`. Binary and
pack hashes, render comparisons and encounter results are in `summary.json`.
These are targeted UI/AI checks, **not performance or extended gameplay tests**.
The earlier [full Trials and traversal evidence](../campaign-controls-presence-20261019/README.md)
and [restart/allocation comparisons](../session-retention-isolation-20261019/README.md)
remain separate. The larger reported restart-sensitive FPS decline remains
unreproduced.

## Portrait finding and fix

The root window has physics interpolation disabled for UI. However, native
portrait heads and their pivots reported `is_physics_interpolated() == true`
inside their own-world SubViewports. Updating their poses on the UI frame clock
therefore left rendering dependent on the world physics clock.

The rendered regression uses the actual `PartyFaces` layout, two identical
native Zak models and the prototype's complexion `(0.2, 0.35, 0.9)`. It drives
selection/idle updates, settles to exact head rotations and captures the native
viewport textures. It visits 1920×1080, 1280×1024, 720×1280 and 2560×1440, then
returns to 1920×1080. Gameplay and networking are not running in this fixture.

Before the fix, the two unselected captures at 1920×1080 had the same final
identity head quaternion and uniform model scale, but the visible head bounds
differed: 75×109 pixels initially versus 75×106 after returning. The smaller
remote portrait was stable. The raw log also records the head and pivot's
enabled interpolation despite the disabled root.

The fix explicitly disables physics interpolation on the portrait pivot and
camera, and on the fallback creature model/camera. UI animation still advances
through the existing selection, nod, shake and idle-look code. Model assets,
facial textures, expression timing, sizes and lighting are unchanged.

After the fix, all 20 head captures passed the viewport-size, uniform-transform
and interpolation checks. The selected/unselected own and remote portraits were
each **pixel-identical** when returning to the initial resolution. The wolf
fallback model/camera check and script-loading check passed too. Native captures
and logs are included. No new player-visible text was added.

This reproduces a portrait rendering-timing defect. It does not establish that
it accounts for the full apparent elongation in the supplied screenshot. Own
and remote cells intentionally differ in size; selection changes the native
head's pitch, not the cell's dimensions.

Run `tools/tests/portrait_viewports.gd` with a rendered export and isolated user
data. `--validate-only` checks script loading without rendering. The test
deliberately refuses a full headless run.

## Peasant help in both campaigns

The original base-game help routine at `0x5d5990` and expansion routine at
`0x51bb30` query nearby units, use the caller's friendship mask and enqueue a
26-tick delayed warning. The Fear noticed-threat branch calls that routine;
the hit path can call it as well. Expansion REA evidence and decompiled
pseudocode are included in `expansion-help-native.json` and
`expansion-fear-native.json`. Base addresses were checked against the existing
historical decompilation of the original executable. This is static native
evidence, not an original-executable gameplay recording.

The new diagnostic loads a full authored map with its scripts and NPCs live.
Only the hero's initial position and equipment are prepared. Normal movement,
spell and attack commands run through `Game`; no fear, perception, damage or
help state is forced. An observing `UnitAI` subclass preserves the previous
AI instance's fields, forwards the ordinary help/suspicion methods unchanged
and records their calls. It matches the peasant's warning point and timestamp
to the guard's receipt. The runs use Ultra and 2×, but their frame rate is not
measured or used as performance evidence.

| Campaign / authored pair | First peasant call | Matched guard receipt | Observation |
| --- | ---: | ---: | --- |
| Base `gz18h`: peasant 150115 → overseer 47536 | 14.740 s | 16.170 s | Help was delivered; the overseer already knew the hero. |
| Expansion `gz1h`: peasant 153729 → overseer 21322 | 2.145 s | 3.575 s | Help arrived with an empty noticed-enemy list; the guard investigated and subsequently fought. |

Both delays are 1.430 simulated seconds: 26 original 55 ms ticks. The expansion
run observed 106 matching deliveries, the base run 136. Repeated warnings are
expected while the peasant notices a hostile. No peasant production change was
needed for these paths.

The base fixture also issued a Weakness cast and then an ordinary melee attack;
the recorded help delivery above followed the later combat. The hero died
after the observed delivery and the game paused. The wall-time cutoff ended
the diagnostic normally. This run does **not** prove sustained combat survival
or an independently alerted base guard: that guard already saw the hero.

Earlier attempts showed why an authored guard's initial map position is an
insufficient precondition: patrol movement put the guard beyond the peasant's
10-metre radius before contact, so calls had no recipients. One exploratory
run was interrupted while its menu was paused. The final base run selects a
currently nearby authored pair and reports the actual pair and distance.
The diagnostic is observational and is not a deterministic CI gate for an
unmodified patrol schedule.

`tools/benchmarks/peasant_encounter.gd` is the reusable diagnostic. Run it with
the appropriate base or expansion asset directory and isolated user data.
It saves samples, call/delivery records and a screenshot; `--validate-only`
checks parsing. A false result must be read together with range, line of sight,
patrol and survival observations, rather than treated by itself as an AI defect.
