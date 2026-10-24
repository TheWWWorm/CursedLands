# Changelog

## 1.28.0-experimental.6 (local preview)

- Prepare streamed biome-cover vertex layouts and Mirror-water shader variants during zone loading.
- Upload replacement ray-tracing texture arrays in bounded batches while retaining the previous scene and its lighting.
- Record separate resource-creation and texture-upload timings for traversal diagnostics.

## 1.28.0-experimental.5 (local preview)

- Warm projected ground-mark materials during loading and reuse immutable ray pipelines across region replacements. Prepare replacement acceleration structures in bounded steps.
- Transfer NRD history between compatible regions and reject changed or deformed surfaces independently.
- Add an optional rendered-frame target for responsive PT with gradual, bounded resolution changes and EN/RU/DE controls.
- Apply nearby grass shadow-map occlusion to traced direct sunlight while retaining indirect illumination.
- Supply DLSS-G with actual HUD opacity and presentation-sized inputs; retain normal rendering for unsupported cropped mappings.

## 1.28.0-experimental.4 (local preview)

- Add an optional dlssg_for_sm86 0.4.0 package for native NVIDIA frame
  generation on Ampere, with pinned files and complete upstream notices.
- Restrict Reflex presentation markers to real presents and sample NVIDIA
  frame-generation presentation telemetry once per present.
- Describe GPU capability requirements consistently in EN/RU/DE.

## 1.28.0-experimental.3 (local preview)

- Restore NVIDIA DLSS/DLAA and the hardware-gated 2× frame-generation path in
  the normal Screen controls, with exclusive SDK presentation ownership.
- Preserve NRD, traversal/blood-mark performance fixes and current DXR barriers.
- Restore NVIDIA/AMD SDK splash and credits; add missing NRD credits on both
  desktop platforms, with EN/RU/DE text and pinned production-file notices.
- Keep NVIDIA mark-placement approval explicitly pending for local review.
- Retain DLSS through forced shader warm-up draws and the local simulation
  connection through long Windows loads.


## 1.28.0-experimental.2 — unreleased

- Reuse projected blood-mark geometry while animating its growth and rotation, reducing CPU work after combat. Preserve surface placement, fading and lifetime.

## 1.28.0-experimental.1 — unreleased

- Integrate NVIDIA NRD 4.18.0 REBLUR for responsive path-traced lighting on Windows DX12 and Linux Vulkan. Preserve sharp direct highlights and retain custom reconstruction as a fallback.
- Reuse CPU mesh and texture sources and lifted terrain sectors across nearby ray-traced scene snapshots, reducing GPU readbacks during travel.
- Apply traced ground lighting and shadows to procedural grass and ground cover.
- Move ray tracing and path tracing options into a direct Remake submenu, with English, Russian and German labels and help.
- Reduce overbright rainy daylight and improve path-traced surface reconstruction.
## Unreleased

- Keep magic traps from striking units, as in the original 1.06, whose trap object never selects a unit. Traps such as the gz3g idol's lightning no longer kill the party or creatures walking past. ([#106](https://github.com/TheWWWorm/CursedLands/issues/106))
- Give creatures and NPCs the original combat flag: becoming aggressive, suspicious or afraid sets it, and returning to guard, patrol, sentry or follow clears it. While it is set they run instead of walking, so a wolf runs to a pack mate's corpse, looks round there for the original time, and crouches into its combat stance again when it next becomes alert. ([#103](https://github.com/TheWWWorm/CursedLands/issues/103))
- Have a hero say the out-of-stamina line when running uses up the last stamina; the run request is still kept for when stamina returns. ([#104](https://github.com/TheWWWorm/CursedLands/issues/104))
- Keep the Load, Save and Options boards from flashing their previous opening's picture when opened from the Esc menu. ([#105](https://github.com/TheWWWorm/CursedLands/issues/105))
- Keep the cursor, portraits, dialogue, quest list, message log, minimap and menu panels at real-time speed on the Fast game speed, as in the original, which speeds up only the game itself. ([#107](https://github.com/TheWWWorm/CursedLands/issues/107))
- Let the party escape Suslanger's gate guards again: the pursuit now ends once no guard can see the party, rather than following the guards' memory of enemies they have already met, which never fades.
- Let zone scripts tell the party's heroes apart again. Script values hold 32-bit floating-point numbers, which rounded consecutive hero IDs to one value, so a script comparing two heroes took them for the same unit. In the prison, this broke guard roles and which hero the guards were sent after. Runtime IDs are now distinct script values.
- Keep zone scripts unchanged while the game runs. The check that skips repeated script conditions no longer writes into the loaded scripts, so saves and joining co-op players see the authored scripts.
- Fast-forward dialogue phrases while Space is held, as in the original. The repeat stops at the last phrase so its rewards stay readable. ([#108](https://github.com/TheWWWorm/CursedLands/issues/108))

## 1.27.0 — 2026-10-24

- Expand Autochess to 40 items across five tiers, mixing raw statistics with special effects. Higher tiers unlock after rounds 3, 5, 10, 15 and 20; borders progress from none to green, blue, purple and gold.
- Simplify four Autochess alliances to direct bonuses while keeping the Hunters and Spirits tactical effects. Offer one recruitable лесовик line; existing saved seers remain valid.
- Add original visual effects for Autochess lifesteal, shields, lightning and other item triggers, and play the original victory music once after a tournament win.
- Hide the item tray and creature item badges during Autochess combat, including paused battles, and restore them during preparation.
- Keep path-traced lighting active while the camera moves and scene geometry refreshes. Filter responsive path-traced lighting to reduce noise, and align the traced snow and sand surface with the visible terrain deformation.
- Scale simulation catch-up work with the selected speed so Fast retains its speed advantage during slower frames. ([#98](https://github.com/TheWWWorm/CursedLands/issues/98))
- Preserve blood-pool appearance, lifetime and the matching corpse pose through saves and reloads. ([#96](https://github.com/TheWWWorm/CursedLands/issues/96))
- Queue allied-corpse investigations behind stronger alerts, share identified threats with nearby allies and renew warnings as packmates arrive. Unseen lethal attacks do not let the victim warn its own pack. ([#95](https://github.com/TheWWWorm/CursedLands/issues/95), [#94](https://github.com/TheWWWorm/CursedLands/issues/94))
- Project footprints, blood and scorch marks onto the actual terrain and floor surfaces, including slopes and deforming snow. ([#29](https://github.com/TheWWWorm/CursedLands/issues/29))
- Keep the pause-menu texture hidden until its opening pose has rendered. ([#89](https://github.com/TheWWWorm/CursedLands/issues/89))

## 1.26.0 — 2026-10-24

- Preserve each scripted party's live and stored quest inventory through travel, redeployment, saves and co-op progress. Shaina retains the meteorite samples until her hand-in, and Kel's rescue restores the stored Rod fragments as in the original game.
- Show creatures in the public web wiki with their original colour variants, as the in-game wiki does since 1.25.0: black boars, black unicorns, white wolves and horses, coloured dryads, succubi and banshees, spotted leopards and the map-authored looks of Lost in Astral creatures.
- Add a **Cut content** section to the in-game and web wiki for each campaign. It lists original creature models, colours, creature variants and weapons and armour that the data contains but no map, trader, script or quest uses, such as the black and dark blue lizards and the unfinished beast and early ogre figures in Cursed Lands. Creatures that maps place in several colours now show each one as a version of their article with its locations, Lost in Astral creatures show the figure their maps give them, and the messenger bird has its own article.
- Restore the Lost in Astral wiki histories for Dar-Ulgorn, Jigran, the baron, Uncle Rad and the hero, which stopped appearing after the official 1.02 journal corrections were included.

- Restore saved side-quest control values when continuing a base campaign.
- Keep shop filters and separate item/spell scroll positions when changing pages; add Shift-click transfers of complete stacks and restore transfer sounds. ([#100](https://github.com/TheWWWorm/CursedLands/issues/100), [#101](https://github.com/TheWWWorm/CursedLands/issues/101), [#102](https://github.com/TheWWWorm/CursedLands/issues/102))
- Suppress world sounds and companion speech in shops, stop replaced acknowledgement voices, and use the original localized White Wolf quest-item names. ([#93](https://github.com/TheWWWorm/CursedLands/issues/93), [#97](https://github.com/TheWWWorm/CursedLands/issues/97), [#99](https://github.com/TheWWWorm/CursedLands/issues/99))
- Apply single-player difficulty changes immediately and preserve them in saves. Start dialogue at normal speed with tactical pause released. Freeze weather and world audio with the simulation while order indicators expire independently. ([#90](https://github.com/TheWWWorm/CursedLands/issues/90), [#92](https://github.com/TheWWWorm/CursedLands/issues/92), [#62](https://github.com/TheWWWorm/CursedLands/issues/62))
- Let middle-button dragging turn and tilt the camera, with Shift-middle panning. Centre the village camera on entry and shop exit while respecting follow and angle-reset choices. ([#91](https://github.com/TheWWWorm/CursedLands/issues/91), [#61](https://github.com/TheWWWorm/CursedLands/issues/61))
- Delay shader progress overlays for work shorter than 500 ms, retain the campaign image while returning to the menu, and preserve FSR preparation across menu and tutorial transitions.
- Fix Autochess reward focus when switching between mouse, keyboard and controller; start battles with daytime lighting and remove floating item-effect names while retaining their effects.
- Correct Windows Direct3D 12 path-tracing barriers during save/load and preserve lighting history across ordinary daylight changes.

## 1.25.0 — 2026-10-23

- Fit multiplayer character-creation kit items inside their cells when **Items inside cells** is on, turn the item under the pointer, and frame the picked weapon, belt item and spell as the shop does. ([#78](https://github.com/TheWWWorm/CursedLands/issues/78))
- Let multiplayer character creation pick any kit spell, as the original does. A spell the hero cannot use yet stays dimmed, its help lists the missing school knowledge or stamina, and the character keeps it. In the game it remains dimmed until the hero qualifies, and trying to cast it logs what is missing. ([#79](https://github.com/TheWWWorm/CursedLands/issues/79))
- Show the camp's hero arrows only when there is another hero to switch to. ([#81](https://github.com/TheWWWorm/CursedLands/issues/81))
- Centre the body-part labels over their health bars in the unit panel, as in the original. ([#82](https://github.com/TheWWWorm/CursedLands/issues/82))
- Show the full item information for kit items in multiplayer character creation. ([#83](https://github.com/TheWWWorm/CursedLands/issues/83))
- Open the camp's Equipment and Skills/Spells screens from **View** in the multiplayer character list. Changes are saved to the character. ([#84](https://github.com/TheWWWorm/CursedLands/issues/84))
- Fix units closing in on a moving target too fast when it runs away and too slowly when it approaches. ([#85](https://github.com/TheWWWorm/CursedLands/issues/85))
- Use the original arrow buttons on the character-creation face rows, and the original scroll-bar arrows in the touch spell column. ([#86](https://github.com/TheWWWorm/CursedLands/issues/86))
- Add **Skill reset button** (Options → Remake → Interface and controls, on by default). On, the camp's Skills/Spells screen shows **Reset skills…** and applies each change immediately. Off restores the original screen: choices stay pending until **Accept**, and **Cancel** or leaving the screen discards them. ([#87](https://github.com/TheWWWorm/CursedLands/issues/87))
- List each learnable ability once. Three inactive ability rows in the original data, one of them a second "Sense Magic", were offered alongside the active ones.
- Include the official Lost in Astral 1.01 and 1.02 corrections. Unpatched CD data, 1.01 data and patched 1.02 data all play with the corrected behaviour, without installing the Windows patches or rebuilding a data pack. The corrected quest texts are translated into Russian and German.
- Fix Lost in Astral progression: Kel no longer returns alive to Jigran after his death scene, the cellar under the Portal no longer traps the party after the Portal's map region opens, the western route and third entrance of gz33j are kept, and older saves of the zone 35 battle reunite the enemy groups an earlier loader separated. Using an object no longer cancels an order the interaction itself gives.
- Show a shared progress screen while graphics settings apply and shaders compile, with the current step, elapsed time and completed material batches where known, in English, Russian and German.
- Improve **Path tracing (test)**: it follows **Render scale** and FSR resolution, replaces its scene after the camera recentres without dropping lighting, retries failed pipelines, keeps animated units in the traced scene, uses equipment and world-prop surface maps, steadies torchlight, and gives fire a calibrated display profile and finite light size. Four-bounce mode ends faint paths early to save time.
- Keep item assignment targets beneath their creature’s health bar when nearby creatures have health labels.
- Restore the shop's buy/sell background quadrants and the dark patterned backing in occupied inventory slots. ([#69](https://github.com/TheWWWorm/CursedLands/issues/69))
- Fit spell, template and rune pictures inside their slot frames, and tint constructor pieces red when the party cannot use them in the current recipe. ([#70](https://github.com/TheWWWorm/CursedLands/issues/70))
- Keep the spell constructor's Ready spells filter limited to completed spells. ([#71](https://github.com/TheWWWorm/CursedLands/issues/71))
- Preserve the proportions of character creation, pause/options menus, dialogue and objectives on wide and tall windows, with pointer and gamepad targets following the fitted interface. Ability lists and character-selection buttons no longer overlap their text. ([#72](https://github.com/TheWWWorm/CursedLands/issues/72), [#80](https://github.com/TheWWWorm/CursedLands/issues/80))
- Preserve the character preview's animation and playback position when appearance or equipment changes. ([#73](https://github.com/TheWWWorm/CursedLands/issues/73))
- Read multiplayer objective text, rewards and map-marker coordinates from the original quest archives. ([#74](https://github.com/TheWWWorm/CursedLands/issues/74))
- Rotate selection triangles with the displayed character's facing and keep them flat above the ground beneath the character as the camera moves. ([#75](https://github.com/TheWWWorm/CursedLands/issues/75))
- Animate dialogue speakers' mouths using the original race/skin mouth atlases, including portrait heads, and stop the animation when the line ends. ([#76](https://github.com/TheWWWorm/CursedLands/issues/76))
- Preserve item-icon texture coordinates when replacement textures have a higher resolution, including replacements inside repacked archives. ([#77](https://github.com/TheWWWorm/CursedLands/issues/77))
- Add eight equippable Autochess items with one slot per creature and a shared inventory. Choose one of three items after rounds 3, 5, 10 and subsequent multiples of five. Reassign equipment during preparation; selling and merging return spare items to the inventory. Saves, undo, bots, scouting and online play preserve ownership and the equipment used by each battle.
- Show items in a compact persistent tray beneath alliances, using pictures of original game items and hover details. Small creature targets and a pointer-offset drag preview keep assignment clear; the return control sits below complete icon rows. Choose rewards from three stone-and-metal framed cards with large item artwork, effect roles, highlighted values and clear selection actions. Assign equipment directly to field or reserve creatures by dragging or selecting targets, or return it to the stash. Keyboard controls support the same assignments.
- Give the six Autochess alliances tactical effects: coordinated Beast strikes, Horde retaliation, nearby Warrior guards, Hunter focus on enemy casters, combined Mage spells and aid from fallen Spirits. Localized help explains their range and limits, and short combat notices identify triggered effects.
- Add Orc warriors and Woodsfolk seers, each with three original visual stages and portraits. Improve three-star Skeleton health and Cyclops damage, reduce three-star Elemental health and Dragon damage, and correct the light/dark bat portraits. Equipment and alliance controls support English, Russian and German at 720p and 1080p.
- Advance the internal Autochess save schema to 14 and its online protocol to 2. Existing saves retain their recruits and start with an empty equipment inventory; online participants need matching builds.
- Ship the DirectX Agility runtime (`x86_64/D3D12Core.dll`, 1.618.5) with the Windows package again. 1.24.0 omitted it, so Direct3D 12 fell back to the system runtime, which on Windows 10 and older Windows 11 builds lacks enhanced barriers and can lower frame rates. The Windows package check now rejects a build without the verified runtime.
- Remove large CPU hitches in Lost in Astral. Completing a quest in the open world no longer stalls for 1.5 seconds before the messenger bird arrives, and its first frame stays under 16 ms: the bird and the party's smiling faces are prepared during zone loading. The Terror's arrival frame drops from about 75 ms to under 20 ms, and briefings and conversations open without 40–50 ms frames. The voice archive opens during zone loading, which removes about 4 ms from the first frame of the first conversation. Unit outlines and labels reuse the meshes' CPU copies instead of reading them back from the GPU. Conversation cameras check only the scenery near the shot. Blocking jobs no longer queue behind grass streaming. Trampled snow and sand publish a sector's trail and its shadow on separate frames, halving the 5–8 ms frames of busy snowfields. The canvas and far-grass shaders compile during zone warm-up. Rivendell's mansion runs about 8 % faster and its worst frames are shorter, because idle characters standing beside water are not re-tested every frame and water reflections no longer rescan the nearby water eight times a second while the camera stands still.
- Stop calling every Black Market trader "Karansul". They share the record name "Trader", whose title belongs only to Karansul. The original texts give them no names of their own, so they now show as "Trader", while the Black Market smith keeps his own name.
- Limit Autochess creatures to a shared pool, as in Dota Underlords: 45, 30, 25, 20 and 10 copies of each creature for tiers 1–5. All nine companies' shops and armies draw from the same pool. Merged creatures keep all their copies, and selling a creature or eliminating a company returns them. The shop odds list each tier's pool size, and the creature inspector shows how many copies are left. Expeditions keep unlimited offers.
- After a company is eliminated online, follow a company that is still playing, and don't place the eliminated company's old formation on its board.
- Give Autochess elementals and ogres original looks as they gain stars. Elementals go from earth to lava to ice, and ogres gain a vest at two stars and become Hadagan sand ogres at three. These rigs share every animation, clip length, speed and reach, so combat is unchanged. Names, portraits and previews follow, and the earth and lava elemental names come from the original Russian and German texts.
- Give two-star Autochess bats the pale palette and three-star bats the dark one, matching their light bat and dark bat names. Previously the colours were the other way round.
- Show wiki creatures in the colours they wear on the campaign maps, for example the black boar and the black unicorn, instead of their base models.
- Reuse the unit under a still pointer for up to 40 ms when choosing the cursor and the hover labels, instead of measuring every unit part under it each frame. With the party under the pointer this cuts that work from about 2 ms to 0.3 ms per frame on average. Clicks and orders still pick exactly.
- Show water contact rings, foam and propagating waves around creatures again. Since 1.7.0 the water shader no longer contained the comments these effects were inserted at, so they were left out. They now attach to shader statements.

## 1.24.0 — 2026-10-22

- Support **Ray traced (test)** water reflections with **Forward+ (Direct3D 12)** on Windows as well as Vulkan. The Windows executable includes the DXR engine patch, and FSR frame generation can run together with RT water in DX12. Add **RT reflection quality** (Low 50 %, Medium 75 %, High 100 % of the viewport, default High) and apply the existing **Texture filtering** setting to RT reflections for sharper reflected textures.
- Add optional experimental ray-traced lighting under **Options → Graphics → Lighting and shadows → Ray-traced lighting** for Forward+ Direct3D 12 and Vulkan on RT-capable GPUs: **RT shadows (test)**, **RT indirect light (test)**, a multi-bounce **Path tracing (test)** prototype with 2 or 4 bounces, **RT lighting quality** and **Path accumulation**. All start off; presets and automatic detection keep the choices. Labels, choices and help are available in English, Russian and German.
- Give sixteen Autochess creature families their original alternate palettes as they gain stars, for example trolls from green to blue to black. Field models, reserves, previews, portraits and online boards share the rank appearance; palettes do not change combat. Creatures in preparation route around each other and reach their places faster, and large figures keep their fitted size when their models change.
- Group identical items in pickup and shared-loot messages, so eight thin leathers read as one "x8" entry for both the finder and the other players.
- Add the console `cursor` command: print the cursor position once, or log it continuously with `cursor on [interval]` until `cursor off`.
- Make Evil Islands side quests work on their campaign maps. Load the multiplayer creature prototypes they use, and bind the orc camp and bridge names that only the multiplayer zone script declared, so objectives such as "kill the orcs" no longer complete on arrival. ([#67](https://github.com/TheWWWorm/CursedLands/issues/67))
- Start the z19q3 side quest with the teleport panels switched on, as on its multiplayer map, so objectives 5–7 are met by switching them off instead of being complete on arrival. The campaign's own teleport quest still counts only panels the player switches on.
- Open a village NPC's topic list at once, as the original does, instead of walking the hero to the NPC first. The hero walks over after a topic is picked; Space, the gamepad's pause button or a tap on touch screens skips that walk and starts the conversation.
- Share one condition evaluation between identical script trigger copies until one of them runs, removing the slowdown in long Lost in Astral mine sessions. Conditions that draw random numbers are still evaluated separately. ([#47](https://github.com/TheWWWorm/CursedLands/issues/47))
- Train script-granted skills at their experience price as the original does, so the Lost in Astral clerk leaves Kel at 22 HP instead of 11. Existing saves are repaired once on load. In co-op, Kel always stays with the host as Kir's story companion.
- Choose dropdown entries by tapping on touch screens, scroll long lists with a one-finger drag, and close a list with a tap outside it. This fixes the Resolution and Render scale dropdowns on phones and handhelds.
- Use the compiled installer decoder on Android ARM64 as on Windows and Linux. Importing from the original installer is about 44 times faster on a Retroid Pocket 5.
- Use the separate render thread only in Linux exports built with the patched engine templates. Runs from source on stock Godot use Safe threading, which avoids a FATAL "Index p_index = 0 is out of bounds" abort when text is drawn at new sizes.
- Update only the units and magic traps near the party in campaign zones, as the original does. Far creatures wait where they are until the party comes near, instead of patrolling into traps or fights the player never sees, and a zone's state on arrival now matches the original's. Units in combat, always-active units and units that know of a living enemy keep moving. An attack, fireworks or clairvoyance wakes the units it reaches. A zone you return to first catches up on the hours you were away near its entrance, as the original does.
- Show the original help for the Attack, Defense and Damage rows of the camp hero panel, as for the armor rows.
- Hide the previous opening's settled Options, Load and Save board until the slide's first pose has rendered, so the board no longer flashes before sliding in from the Esc menu. ([#20](https://github.com/TheWWWorm/CursedLands/issues/20))

## 1.23.0 — 2026-10-21

- Add optional **Ray traced (test)** water reflections on Windows/Linux with Forward+ Vulkan. Include nearby terrain, animated creatures, complete first-person figures, cutout foliage, material tint and emission, and traced sun/local-light shadows. Refresh changed scene membership and supported material properties; retain Mirror while preparing or when RT is unavailable. Keep existing presets and defaults. Labels and help are available in English, Russian and German.
- Correct Fresnel shading on reverse-facing river triangles so overlapping water surfaces do not turn into full sky reflections.

## 1.22.0 — 2026-10-21

- Accept the parameterless `GetLeader()` in authored quest triggers, so the Open Police squares, Junophile follow and totem placement conditions can complete.
- Run script triggers in the original scheduler order. Every true block of a trigger fires in the same pass, a block can fire again while its earlier body sleeps, and new scripts, briefing handlers and side-quest objectives are checked on the original tick. The Zone 19 run point now shows its portal effect instead of recreating its light every tick.
- Keep first-person player shadows in step with running legs during attacks and spellcasting.
- Keep extra self-cast key taps from reselecting the spell during the first half of its cast. Allow a fresh double-tap after the midpoint to queue another cast. Update shortcut help in English, Russian and German.
- Base script sight checks on what each character has actually noticed, as the original does. Guards keep seeing a hero they noticed until they lose track of them, the list of a fallen watcher stays readable, and corpses count only for unit visibility and sighting objectives.
- Show the complete player figure, including the face, in first-person water reflections. Use walking leg animations when stamina prevents running.
- Keep Windows borderless fullscreen presentation and viewport sizes equal so FSR frame generation can activate.
- Add Resolution and Render scale dropdowns. Increase dropdown popup height while keeping lists within the screen.
- Preserve anti-aliasing and FSR choices when changing graphics presets, and keep AA changes independent of the selected preset.

## 1.21.0 — 2026-10-21

- Add a developer console with syntax colours, matching brackets, command and argument completion, searchable help and output, persistent history, adjustable text size, clipboard copying and local diagnostic exports. Add host testing commands for party inspection, healing, basic GodMode, teleporting, direct map travel and scene time. Retain supported original script expressions and authenticated host execution. Help and controls are available in English, Russian and German. ([#65](https://github.com/TheWWWorm/CursedLands/issues/65))
- Support `redress.res` texture overrides in API 1/2/3 mod packages and the legacy converter, covering character skins, clothing and equipment. ([#66](https://github.com/TheWWWorm/CursedLands/issues/66))
- Keep the campaign paused while returning to the main menu and shutting down its connection. ([#63](https://github.com/TheWWWorm/CursedLands/issues/63))
- Prepare Windows FSR resources asynchronously, expose frame generation independently of upscaling, and distinguish presented from rendered frame rates. Keep capability guidance in Screen settings.
- Share foliage height materials to reduce shader parameter-buffer exhaustion.
- Preserve attackers after ranged hits, restore context-sensitive self-casting and Alt target selection, retain curse placement and presentation, and handle ending audio transitions. ([#48](https://github.com/TheWWWorm/CursedLands/issues/48))
- Correct LiA merchant purchases and party ownership, stage co-op dialogue actors consistently, recover the eavesdrop objective when speakers die, and complete the paid-rumour torch handoff through the original mechanism script. ([#47](https://github.com/TheWWWorm/CursedLands/issues/47))
- Align objective-chain completion, mechanism permission consumption, movement rounding, future-position queries, scene/campaign clocks and town-save continuation with the supported original behavior. Preserve Enlarge/Shrink duration and notify nearby allies about non-damaging hostile spells. ([#62](https://github.com/TheWWWorm/CursedLands/issues/62), [#64](https://github.com/TheWWWorm/CursedLands/issues/64))
- Add LiA challenge rewards, use finished-item names in the wiki, and allow held right-click to reduce camp stats and skills.

## 1.20.0 — 2026-10-20

- Add optional AMD FSR 3.1 and FSR 4 upscaling and frame generation to the Windows executable. Configure them under **Options → Screen → AMD FSR** with the **Forward+ (Direct3D 12)** renderer. Both features start off; no separate installation, profile or launcher is required. Include the AMD splash artwork, credits and runtime notices.
- Add bounded Lua formulas for campaign experience rewards, revival duration and revival health on Windows/Linux x86-64. Package API 3 includes localized numeric settings, ordered composition, save/co-op fingerprints and containment of formula errors. Include **Expedition experience**, **Quest focus** and **Field medicine** as source examples and installable mods. ([#50](https://github.com/TheWWWorm/CursedLands/issues/50))
- Preserve animation playback, dialogue gestures and village idle state when equipment or character dimensions refresh a figure. ([#51](https://github.com/TheWWWorm/CursedLands/issues/51), [#56](https://github.com/TheWWWorm/CursedLands/issues/56))
- Include active and completed multiplayer side quests in the journal and resolve base-exit status using the correct campaign variable. ([#52](https://github.com/TheWWWorm/CursedLands/issues/52), [#54](https://github.com/TheWWWorm/CursedLands/issues/54))
- Add automatic or fixed 32/48/64-pixel cursor sizes and an option to hide the player-status overlay. ([#55](https://github.com/TheWWWorm/CursedLands/issues/55), [#59](https://github.com/TheWWWorm/CursedLands/issues/59))
- Remove duplicate item-price text, shrink oversized item previews without enlarging small items, and keep character-creation portraits inside their cells while turning. ([#58](https://github.com/TheWWWorm/CursedLands/issues/58), [#53](https://github.com/TheWWWorm/CursedLands/issues/53), [#60](https://github.com/TheWWWorm/CursedLands/issues/60))
- Add wheel scrolling, Shift-to-edge actions and accelerating held-button scrolling to camp and character lists. Fade the camp selection outline using interface time. ([#57](https://github.com/TheWWWorm/CursedLands/issues/57), [#60](https://github.com/TheWWWorm/CursedLands/issues/60))
- Render Arena text with dedicated distance-field font resources. ([#43](https://github.com/TheWWWorm/CursedLands/issues/43))
- Remove self-shadow bands from Arena snow in OpenGL and at Low shadow quality in DX12/Vulkan while retaining scenery and creature shadows.
- Correct attack-roll distance, action modifiers, rounding and random-number consumption against bounded original-executable comparisons.
- Disconnect loading-screen callbacks before releasing drawing resources, reject malformed campaign-origin metadata, and retain Arena presentation events received while paused.
- Add creature filtering and creature-to-map highlights to the public web wiki, retaining filters and layers through Back, reload and shared links.

## 1.19.0 — 2026-10-20

- Add host-assigned guest permissions for shared pause, speed, quicksave and quickload. Configure defaults from the multiplayer menu and individual permissions from Players; save them with the campaign. ([#50](https://github.com/TheWWWorm/CursedLands/issues/50))
- Separate horizontal and vertical sensitivity for the classic camera, preserving existing sensitivity when upgrading. Let the modern camera scroll at screen edges while hovering interactive HUD controls. ([#50](https://github.com/TheWWWorm/CursedLands/issues/50))

- Add an enabled-by-default option for vertically stacked effect icons and remaining seconds in the top-right corner of the character's general view.
- Add creature-name filtering to wiki maps. Following a creature's map link enables creature markers and highlights matching positions, retaining the selection when navigating back.
- Apply the new water rendering to rectangular lion basins while retaining the original appearance when new water is disabled.
- Preserve the protagonist's portrait face proportions on the world figure as body attributes change.
- Stage dialogue cameras from the actors' destination ground height after scripted placement.
- Retain unaffected navigation blocks when doors change, reducing path reconstruction after opening or closing a door.
- Allow ordinary campaign patrols to lose escaped opponents and investigate their last known location. Stop the Suslanger gate alarm from tracking escaped intruders and complete its escape objective once the living party is clear.
- Alert nearby allies when an enemy is first spotted. ([#49](https://github.com/TheWWWorm/CursedLands/issues/49))
- Make visible witnesses of an assault react before their friend dies, retain running in aimed combat orders, use casting-specific stamina acknowledgements, and finish a replicated character's final partial stride at its approach speed. ([#48](https://github.com/TheWWWorm/CursedLands/issues/48))

- Enable the optional HD Lands texture download on Android and show its installation memory requirements in English, Russian and German.
- Disable unaffordable shop rerolls and mute the level upgrade's XP ring and caption while the button is disabled.
- Extend the arena's textured snow beyond the courtyard and rotate the default camera while retaining its starting height.
- Retain battle damage totals and winner/loser standings colors through preparation. Reset them when the next battle starts.
- Start result fire bolts at animated casting sockets, align them with player names and follow standings reordering. Add elimination notices and show a pending status before finishing places are assigned.
- Attach elemental casting particles to the same animated mouth or hand as the released spell, and attach Horror lightning to its fingertips. Lower defeated Horrors onto the arena snow and hold their final death pose.
- Retain footprints across the arena clearing within a bounded allocation.

- Expire cancelled native tooltip timers on Windows and Linux so mouse movement does not accumulate background work during long sessions or after returning to the menu. Requires the updated engine executable.
- Remember the selected campaign speed between zones, use normal speed in villages and on the route map, and restore the selection when returning to the field. Preserve the choice in saves and shared co-op clocks.

## 1.18.0 — 2026-10-19

- Show the smaller dragon logo with the Cursed Lands name beneath it during startup; apply the game title before the desktop window first appears.

- Show camera-mode and wiki shortcut hints in isometric view, following remapped keys. Add a localized option to hide remake control hints in every camera mode; hints remain enabled by default.
- Default enemy health bars to Always while preserving saved choices and existing visibility rules.
- Keep village quest offers scrollable and centered within the available screen area, including after accepting a quest and resizing a touch browser window. ([#46](https://github.com/TheWWWorm/CursedLands/issues/46))
- Place the scouted company heading below the shop and show compact owned counts by star rank.

- Apply scouting and overview board offsets on the presentation frame so creature meshes return with their health markers.
- Preserve the independent campaign protagonist's authored identity when merging partial co-op updates.
- Recognize unchanged, acknowledged co-op checkpoints when a returning guest's final save is newer than the host's selected save. Retain the guest's personal advancement and inventory while following the shared story checkpoint; keep independent solo progress protected.
- Keep portrait head poses on the UI frame clock, preventing physics interpolation from blending selection and idle animations inside portrait viewports.
- Keep the chosen main hero's portrait face stable when training changes body proportions, including in existing saves.
- Allow the captive lizard's follow-up conversation after the small position change produced by the preceding original dialogue, retaining quest and staging checks.
- Select creature attack animations using their natural weapon type as well as equipped weapons. ([#36](https://github.com/TheWWWorm/CursedLands/issues/36))
- Accept known spells while stamina recovers, stop movement for a waiting self-cast, and give one stamina voice acknowledgement per order. Allow a new movement or attack order to cancel the wait in direct control. ([#37](https://github.com/TheWWWorm/CursedLands/issues/37), [#40](https://github.com/TheWWWorm/CursedLands/issues/40))
- Alert witnesses of a fatal hit without sending an additional help call from the dead creature. Preserve help calls from survivors. ([#38](https://github.com/TheWWWorm/CursedLands/issues/38))
- Replicate individual hostility so attacked neutral animals and witnesses of a kill show their current allegiance on the client. ([#39](https://github.com/TheWWWorm/CursedLands/issues/39))
- Offer original experience distribution, full experience for everyone, or full experience for each main hero with normal companion shares, in solo and co-op settings. ([#41](https://github.com/TheWWWorm/CursedLands/issues/41))
- Replicate the selected action clip, start time and attack rate; discard deferred time from the preceding clip when starting an attack, cast, hit or death animation. ([#42](https://github.com/TheWWWorm/CursedLands/issues/42), [#45](https://github.com/TheWWWorm/CursedLands/issues/45))
- Match replicated walking and running animation rates to displayed movement and finish the final stride before switching to idle. Update the character preview after direct-control leg composition. ([#44](https://github.com/TheWWWorm/CursedLands/issues/44))

- Attach creature spell effects to their animated mouths, eyes, horns, hands or staffs, and physical shots to their weapon or throwing hand. Preserve low launch heights and captured fireball origins when replaying effects.
- Light each will-o'-the-wisp crystal's original faceted surface with a gentle, staggered pulse across the creature family. Preserve crystal silhouettes, colors, motion, invisibility and death animation while improving visibility against grass and in darkness, including without bloom.
- Restore the original ambient wisp stars across the whole creature, including their flicker, running cadence and finite lifetime.
- Restore hit particles and magic attachment positions on creatures with numbered body parts, including wisps, using the original game's part-prefix lookup.

- Use 28 creature species in Trials, each with one 1–5-gold shop price and three ranks of the same creature. Remove human recruits, rebalance health, damage and typed armor, and migrate previous saves while retaining investment and placement. Add the Spirits alliance and revise the other five alliance bonuses.
- Account for native attack cadence, flat armor, extra spell targets and regeneration in Trials budgets. Budget persistent spells by total lifetime damage and let Trials AI estimate partial contact. Preserve bow-caster health, add unicorn healing, and tune shaman Strength and wormhead Haste. Show localized role and recovery descriptions.
- Increase the final Trials star rank to five times base health and four times base damage. Adjust fifteen species' health or damage budgets and reduce unicorn healing to half the offensive spell budget. Give final-rank melee creatures a larger armor increase.
- Refine Trials army valuation to consider sustained damage and survival. Keep healers attacking through light wounds, cast elemental protection when a matching threat is present, and skip night-vision and footstep-concealment buffs in the revealed arena.
- Reduce cumulative XP for Trials levels 7–9 to 55, 80 and 110. Stop training purchases and XP rewards at level nine while retaining compatibility with saves holding up to 126 purchased XP.
- Reconsider available spells when an AI unit has one enemy left, and evaluate spell damage using its actual elemental type.
- Use localized spell names in Trials details when the original text archive has no title.
- Show the watched company's friendly damage with native pixel portraits, names, tier-colored stars and bars above an unframed alliance grid. Keep alliance emblems centered in both active and inactive states.
- Use bold, outlined, unframed round and income notices above the battlefield. Omit zero bonuses, dismiss results after two seconds, and keep the opening title readable during very short battles. Play a sound on company level-up.
- Brighten the Trials clearing, use snow-colored edge fog and a closer 34-degree default camera view, and fold the shop away during combat. Mark the forward deployment limit during planning with a low line of native orange fire with reduced brightness and warm ground reflection. Keep procedural mounds and pebble scatter out of the arena at every graphics quality.
- Animate surviving winners casting native fire bolts toward the losing player’s name. Flash the name and use original combat-number sprites and colors for health loss; apply health immediately and release the visual effects afterward.
- Simplify shop offers to one creature with owned-rank counts; retain the compact rank preview in the inspector. Pair health with armor, remove the repeated recruit heading, and size the inspector to the space above the reserves. Highlight all visible copies that together complete an upgrade with pulsing cyan and a separate arrow, distinct from steady rarity glows. Match inspector accents to the price tier.
- Use native clan palettes in Trials figures and pixel portraits. Keep each species recognizable across its star ranks.
- Preserve individual reserve slots, withdraw into the clicked slot, and swap occupied field/reserve positions in either selection order. Keep reserve controls within the viewport after resizing.
- Preserve the Trials camera between rounds and board views. Add WASD panning and right-drag tilt, using modern-camera speed and inversion preferences. Fit camera clipping to the orbit distance so tall windows and steep angles retain the battlefield and creatures. Limit battles to 90 simulated seconds.
- Apply tournament health loss as each board finishes, settle income and places once all participants finish, and preserve original round health when replaying interrupted combat.
- Use host-supplied online sale quotes and reject changed prices. Display evolution notices on the acknowledged roster update and retain spectator hover details after elimination.
- Advertise online autochess lobbies automatically on the LAN; keep private solo combat workers unlisted.
- Switch replicated survivors from movement to idle clips when combat ends. Isolate Trials animation randomness and native pose clocks from frame timing and unrelated activity.

- Give confirmed first/third-person spells priority over repeated weapon attacks. Let the interaction key cancel spell targeting and act on the pointed object. Preserve running approaches when double-clicking loot or village interactions.
- Place the isometric keyboard aim menu at the cursor, clamped to leave room for its labels and help.
- Right-click a skill or learned ability's price button to refund one level in camp; left-click continues to buy the next level. Preserve dependencies, refund accounting and co-op ownership checks, including maximum ranks.
- Keep a paused save paused while its load menu closes, and apply saved position and facing before the first displayed frame. ([#30](https://github.com/TheWWWorm/CursedLands/issues/30))
- Add Ctrl-click and Shift-click save selection, with counted bulk-delete confirmation and single-selection load/save actions. ([#31](https://github.com/TheWWWorm/CursedLands/issues/31))
- Transition prone humanoids to kneeling before tactical spellcasting. ([#32](https://github.com/TheWWWorm/CursedLands/issues/32))
- Start replicated posture transitions from the authoritative update so older packets cannot briefly show the destination pose first. ([#33](https://github.com/TheWWWorm/CursedLands/issues/33))
- Retain the chosen body part when an aimed ground command finds a target during its approach. ([#34](https://github.com/TheWWWorm/CursedLands/issues/34))
- Clear discarded field messages on loading and rebuild the collected-items listing from the loaded party inventory on both co-op peers. ([#35](https://github.com/TheWWWorm/CursedLands/issues/35))
- Add optional Discord activity on Windows and Linux, showing game mode, campaign location or Trials round and phase. Bundle the public application ID so players only need the Discord desktop client and the translated in-game setting.
- Calculate terrain visibility rays in the Windows and Linux native helper, retaining the original wall, tree, floor and rounding rules and the script fallback on other platforms.
- Release delayed spell-ending effects with their world, pause them with combat and cancel them when a Trials battle settles.
- Reuse Weakness, Strength and Lichdom ending timers when their effects refresh, and discard those timers when their carriers die or leave the world. Preserve one start burst for an unchanged effect and use the latest power for its ending.
- Include periodic frame, graphics, world, effect and cache counters in local diagnostic logs and the existing log export.
- Use the transparent copper-and-gold dragon CL icon for the application, Windows executable, macOS bundle, startup splash, website, wiki and repository branding.

## 1.17.0 — 2026-10-18

- Apply saved idle and movement postures before displaying loaded or joining characters, including paused solo saves. ([#28](https://github.com/TheWWWorm/CursedLands/issues/28))
- Run solo autochess combat in a private local worker, retain courtyards between rounds, and stage models, animations and shader preparation to reduce battle and round-transition stalls.
- Extend native fire and spell particle kernels and snow footprint rasterization without changing their random streams or combat rules.
- Reuse arrow meshes and human animation bindings, and color equipment material layers in the native texture kernel to reduce recurring setup stalls.
- Cache overview markers, stagger distant presentation and private board snapshots, and build lightning geometry in native code.
- Retain moving health-label drawing commands, reuse event-based pointer coordinates, deform and classify exact selection meshes in native code, stop redundant checks behind resolved targets, and spread snow mesh uploads across frames.
- Preserve distant animation and lightning update spacing after slow frames, reuse spell attachment samples within an update, and apply exact arena health without temporary rounded-health damage or healing.
- Read current figure bounds and calculate lightning branches and glow geometry in native code, reuse compatible lightning buffers, retain board labels, and avoid repeated clock-theme and shared-atmosphere updates.
- Give CPU opponents savings, army evaluation, replacement purchases and four spending strategies: economy, expansion, evolution and tempo. Preserve progress toward final evolutions and value native creature spellcasting.
- Expand recruitment from 24 to 40 families with human fighters and casters, zombies, guards, elementals, hounds, woodsfolk mystics, ghouls, evil eyes, dragons, cyclopes, shadows, imperial archers and storm banshees. Add a woodsfolk-to-unicorn evolution, adjust recruit prices and evolved spells, and bring two final forms' boss armor into the recruit range.
- Render menu and autochess text at its displayed scale, show tribe emblems beside creature traits, and use the original game cursor in autochess menus.
- Make held Q/E camera rotation continuous and add right-button dragging, independent of the 1×/2× battle speed.
- Add a persistent player name in remake network settings and reuse it in multiplayer and autochess. Translate the new interface and recruit names into English, Russian and German.

## 1.16.0 — 2026-10-18

- Restore gameplay pause and speed when loading campaign saves, including the separate solo simulation process. ([#27](https://github.com/TheWWWorm/CursedLands/issues/27))
- Open the load-game prompt when the last controlled solo party member dies. ([#25](https://github.com/TheWWWorm/CursedLands/issues/25))
- Stabilize Low-quality sun shadows while the daylight direction changes. ([#23](https://github.com/TheWWWorm/CursedLands/issues/23))
- Add a Selection glow setting with Automatic, Off and On choices; Automatic hides the selection glow in direct camera modes. ([#22](https://github.com/TheWWWorm/CursedLands/issues/22))
- Emit toad acid from the animated mouth and preserve its low launch height. ([#21](https://github.com/TheWWWorm/CursedLands/issues/21))
- Allow revisiting the Canyon of Death and Wormfaces' Cave after reaching the Necromancers' Desert, retaining their quest state and a route back.
- Discover local autochess lobbies automatically and let the online host switch shared combat between normal and double speed.
- Keep hovered online creature details stable, render player names at the HUD's display scale, show the local player's name and mark ongoing battles with a sword icon.
- Show the watched player's battle timer, opponent and result when scouting. Keep all nine boards positioned correctly while the overview receives updates.
- Animate online formation placement and movement, stop locomotion when a battle ends, and keep decorative obstacles clear of both halves of the playing field.
- Fit banshee previews to their current animated pose. Add Q/E camera rotation and Home reset to Trials, alongside middle-button dragging.
- Raise the savings-interest cap to five gold per round, reached at fifty saved gold. Translate the updated help and new controls into English, Russian and German.
- Avoid particle draw setup and uploads on hidden boards, and skip depth sampling and blending for fully transparent particle fragments.
- Reduce ground-contact blending cost in Forward+ by skipping terrain cells that cannot reach the shaded point, retaining the exact surface and footprint tests.
- Render solid scenery in the opaque pass and reject cutout texels before calculating foliage, relief and ground blending.
- Skip scenery relief sampling after its distance or minification fade reaches zero.
- Keep online autochess authority boards hidden and skip visual ground-contact setup for their navigation-only terrain.
- Run desktop online autochess simulation in a separate process while preserving seat-zero ownership, host controls, guest slots and LAN discovery. Allow ENet peers time to finish cold scene loading.
- Handle simultaneous online departures without sending roster updates to closed connections.
- Spread independent online battles across render frames and limit catch-up work between complete ticks, retaining combat time, player order and shared speed.
- Skip NPC acknowledgement lookup when no controlled party member can receive it, avoiding voice-database loading during autochess combat.
- Apply the shared SSAO, fog and glow quality settings when initializing viewports, so autochess rendering does not depend on first opening a campaign.
- Share cached arena tile colours between Forward+ boards while retaining live lighting, terrain relief, footprints and effects. Preserve the original sampler for other renderers and larger replacement textures.
- Cache nearby terrain colours in eligible Forward+ campaign maps within a fixed memory budget. Retain live footprint materials during page loading, eviction and graphics changes.
- Skip unused secondary sun-shadow lookups outside cascade transitions in the custom Forward+ engine template, preserving shadow filtering and transition blending.

## 1.15.0 — 2026-10-18

- Add online autochess for up to nine human players, with computers filling empty seats and taking over departing guests.
- Use the campaign co-op host/join window for autochess connections, including address copy/paste, recent addresses, passwords, readiness and a nine-seat roster.
- Synchronize shops, armies, native battles, scouting and standings through the host over ENet or WebSocket. Keep eliminated players as spectators.
- Add English, Russian and German connection text, errors and online rules. Keep solo saves separate from online matches.
- Replace standalone wiki buttons with a rebindable F7 shortcut for the hovered item, spell, creature, quest or map. Open the wiki home page when no subject is under the pointer.
- Add a Cave echo setting under Sound, with immediate preview and saved On/Off choices in English, Russian and German.
- Tile extra menu button borders at their native texture density instead of stretching their narrow source strips.

## 1.14.0 — 2026-10-17

- Detect Windows graphics APIs with separate rendered tests, preferring Direct3D 12 and Vulkan before OpenGL. Cache successful detection and advance after an interrupted test or failed first menu presentation.
- Add Automatic and Vulkan to the Windows renderer setting, with English, Russian and German labels and help.
- Place recruitment prices, copy counts and trait icons on compact translucent panels with light borders and cost-based accents. Add matching alliance labels and outlined Trials text and icons. Matching tribe icons glow in their tribe color when that tribe is represented in the deployed army. ([#15](https://github.com/TheWWWorm/CursedLands/issues/15))
- Include Safe Windows rendering and persistent manual renderer choices from the unpublished 1.13.0 candidate.
- Improve one- and two-star banshee health and attack cadence in Trials, and strengthen upgraded red harpy fire spells. Keep campaign creatures and the final dark banshee unchanged. ([#15](https://github.com/TheWWWorm/CursedLands/issues/15))

## 1.13.0 — unpublished candidate

- Add persistent Compatibility (OpenGL) and Forward+ (Direct3D 12) selection on Windows, with startup recovery and a compatibility launcher.
- Use the Safe rendering thread by default on Windows and include the actual thread mode in diagnostic reports.
- Require a presented 3D menu before confirming a renderer trial; keep the Compatibility fallback armed while startup notices are open.

## 1.12.0 — 2026-10-17

- Add First-person actions under the First / third person settings. It keeps first person during action animations by default; Off restores automatic third-person framing. Scripted cameras retain control.

- Keep embedded shaders compatible with Windows checkout line endings.
- Allow graphics detection to finish applying a preset when terrain updates replace scene nodes.
- Document the safe rendering-thread configuration for running from source with official Godot builds.

## 1.11.0 — 2026-10-17

- Add Autochess alongside Expedition: nine players on a 3×3 map, eight named CPU rivals, announced random matchups, creep rounds, live board spectating and elimination.
- Expand recruitment from twelve to twenty-four families, with twelve starting families from across the islands. Reprice new recruits, use stronger native evolution forms where needed, and retune later expedition reinforcements for the larger shop pool.
- Scale the Trials HUD and main-menu buttons with display resolution. Use near-black regular text on snow, keep the shop, reserve, tribes and player list transparent, and mark the board being watched.
- Enable battle audio when spectating, isolate spells to their own board, drain effects after combat, and spread opponent-model preparation over frames before the shared start.
- Add a pulsing warning during the last ten seconds. End fights after two minutes or ten seconds without damage; Autochess draws damage both players.
- Deploy new recruits into free field positions, remember combat speed across runs, use a 1×/2× toggle, and place evolution notices below the tribes. Center menu icons and keep every reserve slot visible.
- Bound formation arrival before combat so blocked preparation movement cannot hold an encounter indefinitely. ([#19](https://github.com/TheWWWorm/CursedLands/issues/19))
- Correct NPC target lookup for filtered multi-target spells and avoid callbacks retaining destroyed death-animation models.

- Prevent a stale pause-menu frame from flashing when reopening the menu, and show the build version in the main and pause menus. ([#17](https://github.com/TheWWWorm/CursedLands/issues/17))

- Restore the lizard tomb's return exit when revisiting after The Magic Needle, including affected saved games, while preserving quest rewards and the unfinished quest's exit restriction. ([#16](https://github.com/TheWWWorm/CursedLands/issues/16))

## 1.10.0 — 2026-10-17

- Expand Kel’s encyclopedia biography and add the original Rod of Life resurrection requirements, fragment quests and dialogue deadline in English, Russian and German.

- Put Mods and rules, Encyclopedia and Trials in a bottom menu row. Use the localized Trials of the Allods name, compact menu hints, and show Trials only for the original campaign.
- Move company level, XP and recruitment odds into compact shop controls. Allow combat recruitment, XP purchases, rerolls, multiple offer locks and reserve sales; deployed upgrades take effect next round.
- Fit creature/alliance details to their content, center utility icons, highlight upgrade-completing offers, and make camp rewards clickable cards with original item illustrations.
- Keep the HUD and creature animation visible after a round, with results/countdown in the top badge. Add original sounds for transactions, evolution and round outcomes.
- Give every recruit family a three-star evolution. Pay base income and interest after defeats and advance each completed wave; strengthen later enemy formations. Use the remake's 80% armor absorption cap for both sides in Trials and resolve unfinished battles as defeats after two minutes.
- Cache unchanged encyclopedia indexes, decode only required map records once, and render visible search rows. Space navigation buttons and remove redundant difficulty explanations.

- Offer starting-skill restoration or a full refund from a camp dialog, with original window styling and content-sized English, Russian and German layouts. ([#5](https://github.com/TheWWWorm/CursedLands/issues/5))
- Adjust Trials recruit prices, make spiders available at company level five, and strengthen Veteran and Champion reinforcements. Set preparation to 60/45/30 seconds by difficulty and prevent damaging spells from hitting allies in Trials. ([#15](https://github.com/TheWWWorm/CursedLands/issues/15))
- Show movement and attack routes during tactical pause, honor explicit attack-move in defensive stance, and show routes when attack-move acquires a target. ([#12](https://github.com/TheWWWorm/CursedLands/issues/12), [#13](https://github.com/TheWWWorm/CursedLands/issues/13), [#14](https://github.com/TheWWWorm/CursedLands/issues/14))
- Render the pause signpost's opening pose before revealing it and keep pointer motion from interrupting the opening animation. ([#11](https://github.com/TheWWWorm/CursedLands/issues/11))
- Suppress incidental acknowledgements and creature voices during quest dialogue while preserving scripted lines. ([#10](https://github.com/TheWWWorm/CursedLands/issues/10))

Movement clarification ([#9](https://github.com/TheWWWorm/CursedLands/issues/9)):
the player character's base crouching and walking speeds are equal, and crawling
uses 80% of walking speed, matching the original game. This release makes no
movement-speed adjustment.

## 1.9.2 — pause menu and companion controls, 17 October 2026

- Keep pause-menu opening and board animations at the same real-time speed when gameplay is paused, normal or accelerated, including reopening after an interrupted slide. ([#6](https://github.com/TheWWWorm/CursedLands/issues/6))
- Restore normal stamina recovery for companions standing still with a follow order, retaining movement and combat recovery rules. ([#7](https://github.com/TheWWWorm/CursedLands/issues/7))
- Allow party portraits to select follow targets while preserving the acting party selection, with matching target cursors and invalid-target handling. ([#8](https://github.com/TheWWWorm/CursedLands/issues/8))
- Prevent a typed-array error when resolving world tooltips in direct control.

See [release notes](docs/releases/1.9.2.md) for compatibility and platform limits.

## 1.9.1 — pause menu and companion controls, 17 October 2026

- Keep pause-menu opening and board animations at the same real-time speed when gameplay is paused, normal or accelerated. ([#6](https://github.com/TheWWWorm/CursedLands/issues/6))
- Restore normal stamina recovery for companions standing still with a follow order, retaining movement and combat recovery rules. ([#7](https://github.com/TheWWWorm/CursedLands/issues/7))
- Allow party portraits to select follow targets while preserving the acting party selection, with matching target cursors and invalid-target handling. ([#8](https://github.com/TheWWWorm/CursedLands/issues/8))
- Prevent a typed-array error when resolving world tooltips in direct control.

See [release notes](docs/releases/1.9.1.md) for compatibility and platform limits.

## 1.9.0 — Trials, illustrated lore and Android rendering, 17 October 2026

- Draw native battlefield marks on the snowy surface on Mobile and Compatibility renderers.

- Add **Trials of the Allods**, a solo PvE expedition across 30 encounters on a snowy battlefield. Buy a company from original Gipath, Ingos and Suslanger creatures, arrange the formation, and let both teams fight under AI control.
- Add automatic creature evolution, overlapping Beast, Horde, Warrior, Hunter and Mage alliances, level-based recruitment, paid training, interest, win streaks and camp rewards. Each preparation lasts up to 45 seconds; ordinary results advance automatically.
- Add native run-in and repositioning animations, visible snow trails and blood, numeric health, damage feedback, creature details and a HUD that scales through 4K. Keep the opening, menus and feedback localized in English, Russian and German.
- Expand both encyclopedias with 92 character biographies, seven allod articles, revised location histories and original scenery illustrations. Link the accounts to dialogue, journals, event scripts and related characters and places.
- Reduce repeated terrain sampling and colour-cache work. On Android Vulkan, skip unused baked-light, sky-radiance, clear-fog, water-reflection and screen-mipmap work while preserving the selected graphics settings.
- Correct terrain contact on authored bridge decks and use consistent sectors in radial menus.
- Add the YouTube trailer, five new README screenshots and the reusable native 4K60 capture/editing project.


See [release notes](docs/releases/1.9.0.md) for compatibility and platform limits.

## 1.8.0 — encyclopedia, planning and local creations, 16 October 2026

- Rework the website and in-game encyclopedia with clearer search results, category artwork and readable article layouts in English, Russian and German.
- Connect items to their acquisition sources and uses, and open related encyclopedia articles from gameplay panels.
- Add practical mechanics guides, quest guidance and interactive maps with nearby detail popups, optional creature markers and directional exits.
- Compare Easy and Hard creature statistics alongside the game rules that produce them.
- Add character planning and camp-style item and spell construction, including materials, enchantments, compatible runes and equipment slots. Preserve complete builds in shareable links.
- Save named items, spells and characters locally, reopen them from Saved creations, and reuse saved recipes in compatible selectors.
- Place searchable item and spell selectors beside the camp on wide screens. Keep both panels the same height and their selected-item actions visible while results scroll.

See [release notes](docs/releases/1.8.0.md) for compatibility and platform limits.

## 1.7.0 — wiki constructors and gameplay fixes, 16 October 2026

- Add maps, quests, campaign tabs and item subcategories to both encyclopedias. Bring reviewed expansion translations, item artwork and continuous browsing into the in-game wiki.
- Add spell and item constructors to the website and an item constructor in game. Retain the selected rune after adding it, show rune artwork, and allow removing runes and enchantments. Exclude internal colour/effect records from rune browsing.
- Keep rain rings visible at isometric distances and strengthen ordinary, bloody and green footprint opacity while retaining their authored artwork and lifetime.
- Select nearby visible water levels consistently for Mirror scenery reflections when changing the camera angle.
- Blend verified natural terrain textures from side projections on steep slopes. Enable the translated Steep terrain textures option in enhanced graphics profiles, with Original look retaining the original projection.
- Animate the movement of the lava surface's larger crust patterns alongside its existing glow.
- Select walking clips that match the character's injury state and preserve their animation phase during gait changes.
- Keep first-person spell selection independent of stale modifier/button state. Add an enabled-by-default option to cast compatible spells on the caster by double-tapping their shortcut.
- Group identical items collected together into one pickup notification with a quantity.
- Hide protagonists' helmets and held weapons in safe hubs while retaining their equipped items, companion appearances and inventory previews.
- Keep opening Suslanger conversation actors on the accessible side of the locked cage and honor the authored deployment facing.
- Keep prone first-person viewpoints and their near-plane corners outside terrain and solid scenery.
- Mute game effects, voices and music during movies, retaining movie audio and restoring the current volume settings afterward.
- Localize the invisibility status name and icon and retain its figure fade across outfit changes, loaded state and renderer choices.
- Remove the use interaction from exhausted one-way mechanisms while preserving cyclic switches and gates.
- Prevent completed west-path bridge checks from removing the active Revenge quest areas on return to the mansion. Recover those areas in affected saves without restarting the quest. ([#4](https://github.com/TheWWWorm/CursedLands/issues/4))

See [release notes](docs/releases/1.7.0.md) for compatibility and platform limits.

## 1.6.0 — encyclopedia and rendering updates, 15 October 2026

- Publish a standalone [public wiki](https://cursedlands.wwworm.com/wiki/) with GOG edition data, searchable articles, material variants and illustrations in English, Russian and German. No imported game files or account are needed.
- Add an in-game encyclopedia with searchable HTML pages for items, material variants, blueprints, spells, runes and creatures, generated from the installed game databases.
- Keep each item on one page, with buttons to switch its material versions and blueprint view while updating the statistics and model.
- Show rotatable, zoomable item and creature models, and let readers calculate spell variants with compatible runes.
- Explain combat, armor, magic, crafting and character formulas with values and examples from the loaded game data. Provide the interface and explanations in English, Russian and German.

- Vary rain puddle size and spacing with a broader depression field, retaining sparse coverage and receding edges. Keep their muted sheen visible from isometric views in Forward+ and Compatibility.
- Refresh carried weight when adding, removing or consuming belt items, including wands. Deliver guest belt changes and their weight together while paused.

This stable release also includes the cloud, reflection, movement, traversal and persistence fixes from the 1.5.1 previews below.

See [release notes](docs/releases/1.6.0.md) for compatibility and platform limits.


## 1.5.1-preview.3 — cloud rendering preview, 15 October 2026

- Keep water's normal-incidence reflection visible from steep camera angles while retaining the swamp colour treatment.
- Bind immutable cloud noise textures when they are created instead of scheduling material texture updates every frame.
- Give the cloud reflection view an independent sky and minimize its unused radiance-cubemap work without changing visible cloud samples or resolution.
- Make rain puddles smaller and sparser, with receding edges and angle-dependent sheen that preserves the ground colour. Bind their depression texture with either terrain-detail setting.
- Bound particle-update worker groups to the number of emitters and at most four tasks, avoiding full-pool synchronization for small effects.

See [preview notes](docs/releases/1.5.1-preview.3.md) for compatibility and platform limits.

## 1.5.1-preview.2 — movement and traversal preview, 15 October 2026

- Smooth the local player's movement with continuous path samples and a single update stream, retaining ordinary co-op updates for remote players. ([#4](https://github.com/TheWWWorm/CursedLands/issues/4))
- Reuse far-grass bounds and precompute sorting priorities during camera movement.
- Copy terrain shader values without enumerating renderer properties when creating snow-track sectors.
- Prepare footprint textures and map-specific foot shapes during loading.
- Refresh both actor roots and model transforms when figures reappear after moving out of sight.

See [preview notes](docs/releases/1.5.1-preview.2.md) for compatibility and platform limits.

## 1.5.1-preview.1 — performance preview, 15 October 2026

- Retain grass instance data on the CPU before bulk upload, avoiding GPU readbacks when camera movement changes grass detail.
- Reuse authored water geometry for mist, ambient life and water-contact queries as the camera enters new sectors.
- Reuse retained scenery triangles for camera occlusion tests before fading objects in front of the party.
- Reuse regional particle habitat results for overlapping camera cells, with bounded storage and invalidation when scenery or water levels change.
- Prepare regional wildlife shaders during map loading, including tinted snow mice and frogs that first appear away from the starting view.

See [preview notes](docs/releases/1.5.1-preview.1.md) for compatibility and platform limits.

## 1.5.0 — stable release, 15 October 2026

- Retain scenery geometry on the CPU for rain-shelter maps and footprint setup, avoiding renderer readbacks during gameplay.
- Give detached limbs mesh-based ground contacts, outward launch, repeated bounces, friction and gradual settling on slopes.
- Bound destination relocation for small disconnected navigation regions and reuse prepared connectivity to reject unreachable routes and unrelated endpoint searches, preserving endpoint order.
- Skip footprint animation-position queries until an animation is active.
- Show the required Use/Steal value when hovering a locked object that the selected character cannot open, accounting for effective skill and quest keys.
- Use localized fallback names for unnamed creatures and remains instead of map identifiers.
- Let archers replace a patrol or investigation with a retreat immediately after noticing a nearby threat.
- Keep compact spell-rune clusters and full-size artwork by default, with an optional original layout around the icon. Move a shop price above the lower rune row only when that row contains runes in the original layout. Show runes in shops, inventory and the spell bar.
- Scale the full health-bar texture into overhead bars, preserving texture-pack gradients at full and partial health.
- Restore the Great Mage’s staff from his original animated figure.
- Identify natural terrain transitions and cliff surfaces from the original atlases while rendering installed texture-pack artwork.
- Soften portrait and inventory figure lighting with a weaker directional light and more ambient fill.
- Render enhanced swamps as murky green water with depth-dependent colour, slow sediment variation, gentle ripples, reflections and soft shores, independent of swamp textures. Reduce the blue sky cast while retaining neutral cloud highlights.
- Reuse a bounded sky view for Forward+ cloud reflections and skip cloud samples hidden by scenery reflections.
- Reduce the Forward+ cloud-shadow field cost and reuse completed fields while weather and sunlight are unchanged.
- Stop the completed Portal escape's companion-death check from killing Kir after Kel stays at the shelter. Preserve the check during the escape and support existing pre-departure saves. ([#4](https://github.com/TheWWWorm/CursedLands/issues/4))
- Make the existing Mobile (Vulkan) renderer choice available from Android's startup recovery dialog before loading the main menu. ([#3](https://github.com/TheWWWorm/CursedLands/issues/3))
- Track Android engine launches before renderer initialization, recover interrupted Vulkan starts to Compatibility, and retain their diagnostics until a report is saved. ([#3](https://github.com/TheWWWorm/CursedLands/issues/3))

See [release notes](docs/releases/1.5.0.md) for compatibility and platform limits.

## 1.4.0 — stable release, 15 October 2026

- Preserve looted actor references when quests replace a location’s population, preventing co-op progress saving and full saves from crashing the server.
- Keep dialogue participants hidden consistently during camera transitions and stop skipped dialogue audio on co-op partners.
- Keep movement active while the Alt body-part menu is open. Place left and right limbs on their respective sides and add a central option to clear the preferred body part.
- Restore cursor state after menus and zone transfers, and use appropriate names for first-person interactions.
- Filter quest items from shops and crafting activities, and exclude special items from blueprint generation.
- Restore the Gipat elder’s authored departure and allow separate travel to the healer’s outdoor area and cave.
- Restore original large-creature preview framing and reject vanished spell targets instead of falling back to the caster.
- Restore terrain sun shadows and prevent reflection-camera state from clipping character and scenery shadows.
- Include matching Android process-exit records and available native crash stacks in the existing startup report, and report the graphics settings active at the failure. ([#3](https://github.com/TheWWWorm/CursedLands/issues/3))

See [release notes](docs/releases/1.4.0.md) for compatibility and platform limits.

## 1.3.1 — stable release, 14 October 2026

- Keep Mirror water reflections aligned with the main camera during rapid movement.
- Correct fog colours in distant Mirror reflections during daylight and at night.

See [release notes](docs/releases/1.3.1.md) for compatibility and platform limits.

## 1.3.0 — stable release, 14 October 2026

- Allow movement while casting spells in first- and third-person controls, with the same movement reduction used during attacks. Preserve casting timing, costs and effects, and keep the walking animation continuous when a cast ends.
- Remove the repeating painted line pattern from enhanced liquids. Keep each surface's authored colour palette, with animated water ripples, mottled swamp cover and glowing lava.
- Reuse retained terrain arrays when starting snow and sand deformation, and compute camera frustum planes once per water-reflection scan.
- Show campaign resource and money pickup notices only to players receiving the grant. Add scripted quest items once when corpse loot and pockets share the same inventory array.
- Compile Android GLES scene shaders on demand and omit disabled figure effects from their generated shader source. ([#3](https://github.com/TheWWWorm/CursedLands/issues/3))

See [release notes](docs/releases/1.3.0.md) for compatibility and platform limits.

## 1.2.0 — stable release, 14 October 2026

- Ask before running graphics checks on handheld devices, with a choice to skip and an explanation of recovery in case of a crash. Interrupted checks restore Original graphics and disable automatic retries. ([#3](https://github.com/TheWWWorm/CursedLands/issues/3))
- Start the first handheld menu with Original graphics and a 30 FPS limit, and wait for startup screens to close before offering automatic graphics detection.
- Add **Use basic graphics** and **Test startup graphics** to the startup recovery screen. The optional test records separate rendering stages in the crash report.
- Stop rendering hidden interface previews and resizing their inactive viewports.

See [release notes](docs/releases/1.2.0.md) for compatibility and platform limits.

## 1.1.1 — stable release, 14 October 2026

- Offer the previous session's crash report before intro movies and 3D menu loading, keeping report export accessible during repeated menu-load failures. Add startup and menu-construction checkpoints to diagnostic logs. ([#3](https://github.com/TheWWWorm/CursedLands/issues/3))

See [release notes](docs/releases/1.1.1.md) for compatibility and platform limits.

## 1.1.0 — stable release, 14 October 2026

- Keep the protagonist and supporting actors in their original dialogue camera slots, including topics offered by a third participant and co-op conversations started by a guest.
- Recognize fresh co-op characters with compatible mod-profile metadata and preserve shared campaign continuity through objective updates and resets after a quest completes, so eligible location and day updates continue together.
- Restore a returning guest's saved position after the host reloads their shared checkpoint, without moving players already present.
- Keep footprint deformation joined at diagonal tile junctions and shifted sector edges, using the same world-space track samples for terrain, scenery contact and snow piles.
- Add travel-map buttons for previously visited islands. Island excursions preserve the departure area, party positions and facing across saves, while retaining current character and quest progress. Captive and temporary-party sequences keep their travel restrictions.
- Restore first-person and third-person control after a revived co-op player finishes inspecting another character.
- Apply the ordinary Attack/Defence roll to direct-view melee and projectile contacts, retaining authored backstab rules.
- Reconcile completed, state-dependent visibility decisions on zone restoration, including Fleyn, Lovkach, the Gipat sheriff and mercenary, and the Dragon's skeleton.
- Restore authored dialogue walking, participant facing and return movement for clicked topics, with prompt fallback when a staging route cannot reach its mark.

See [release notes](docs/releases/1.1.0.md) for compatibility and platform limits.

## 1.0.7 — stable release, 14 October 2026

- Render dropdown text at its actual display scale, including high-resolution screens.
- Complete Russian and German remake labels and require translations for all player-visible strings, with a translation coverage check.
- Aim moving first- and third-person bow shots from the current launch position toward the latest received camera ray at release.
- Keep the first-person eye position continuous during turns and refine third-person camera collision distances.
- Keep detailed snow tile edges joined to adjacent terrain and fade footprints at coarse tile boundaries.
- Constrain distant terrain atlas sampling to each tile's padded border and increase Mirror reflection resolution, capped at 2048 pixels on the longest side.
- Restore Brissen's enchanted armor, inventory models and localized descriptions while preserving saved wear, charge and enchantments.
- Restore lesoviki's authored blowpipes and dart boxes in world models and character previews.
- Use authored weapon ranges for item-equipped NPCs and party characters, including melee weapons, bows and crossbows, and refresh range after weapon changes. Preserve natural creature and spell attack ranges.
- Recheck Lovkach's authored visibility condition on Ingos revisits and older saves after his quest completes, without repeating rewards or recreating removed actors.
- Restore mouse-wheel scrolling in inventory and shop item rows.
- Keep long location descriptions inside the objectives screen frame, with mouse-wheel scrolling and the original scrollbar controls.
- Reset filters and scrolling when switching shop activities; show relevant spell, construction and repair categories by default.
- Exclude quest items from shop stock and reject attempts to purchase them.
- Publish spell-constructor inventory changes before confirmation, including paused co-op, so assembled spells and returned runes appear immediately.
- Keep sold unique equipment available for exact buyback without generating unsupported variants or blueprints; restore authored skins and localized descriptions for existing variants without changing their stats or enchantments.

See [release notes](docs/releases/1.0.7.md) for compatibility and platform limits.

## 1.0.6 — stable release, 13 October 2026

- Preserve safe-area NPC poses between scripted animation repeats and loop
  animations marked as continuous.
- Show conversation attention highlights only outside dialogue when a character
  has a relevant, available topic. Clear completed topics with the final dialogue state.
- Return co-op stat-allocation feedback promptly, including while paused, and avoid
  rebuilding hidden inventory previews.
- Repair selected items and equipped items as complete batches, with one result
  and inventory update per confirmation.
- Group identical items into co-op trade stacks, using eight distinct-item slots
  and preserving quantities and item variants.
- Reduce the Alt body-part selector to half its previous width and height, with
  pie-shaped sections, full-section highlighting and matching mouse-selection geometry.

See [release notes](docs/releases/1.0.6.md) for compatibility and platform limits.

## 1.0.5 — stable release, 13 October 2026

- Update the optional HD Lands texture package to 1.5.0 with 390 textures.
- Prefer Gipat for the download and use Yandex Disk as a verified-source backup.
  Keep cancellation responsive when a server stops responding.
- Keep shop and spell-constructor rune icons inside the upper-left border,
  leaving space for quantities and prices.
- Adopt [Semantic Versioning](docs/versioning.md) for new releases.

See [release notes](docs/releases/1.0.5.md) for compatibility and platform limits.

## 1.0.4 — stable release, 13 October 2026

- Highlight characters with available conversations using the same material effect as character selection.
- Keep the Lost in Astral smith's completed Assortment introduction separate from his purchase catalogue. Add a Back entry and retain all authored offers.
- Display localized rune reward and wand blueprint names in dialogue, tooltips and item details.
- Use **Q** to open and close quests in first- and third-person views; **Tab** toggles the pointer. The quest key is configurable, and existing custom bindings are retained.
- Choose co-op host saves and client heroes from scrollable dropdowns with save names and dates.
- Copy compatible original campaign saves, metadata and thumbnails when creating a mod profile, including automatic profiles created when enabling mods. Later profile switches retain the copied campaign's progress.
- Keep camera-centred rain and snow out of mirror-water reflections.


Includes the 1.0.4 preview changes below. See [release notes](docs/releases/1.0.4.md) for compatibility and platform limits.

## 1.0.4-experimental.7 — experimental release, 12 October 2026

- Keep long dropdowns within the display, with mouse-wheel and keyboard scrolling and the selected entry visible on reopening.
- Preserve the original character shape in direct control and rebuilt HUD/inventory previews. Retain movement during melee and bow attacks.
- Keep one visible first-person body and weapon, hide the collar while running and looking down, and retain the complete head shadow.
- Cycle top-down, third-person and first-person views with F6. Tap Ctrl to crouch or stand; hold Ctrl to lie down. Keep the camera-control guide above the follow icon.
- Show Talk only for characters with available topics. Retain the Ingos workers' kneeling poses between scripted cycles.
- Retain snow contact and footprints after model rebuilds and moving attacks, including strafing.
- Cast selected direct-view spells from the current position. Out-of-range targets retain spell selection and show a range hint without an approach command or stamina cost. Tactical approach casting is unchanged.
- Restore minimap marker colours with HD atlases and match mirror draw distance to the main camera.

See [release notes](docs/releases/1.0.4-experimental.7.md) for compatibility and platform limits.

## 1.0.4-experimental.6 — experimental release, 12 October 2026

- Compress co-op campaign progress and movement snapshots, keep snapshots flowing
  during delayed acknowledgements, and retry small ordered input independently of
  reliable-packet backoff. Party snapshots update at up to 20 Hz. Reduce repeated
  visibility work during non-combat movement and audio catch-up.
- Synchronize scripted mechanism locks for active players and late joiners; select
  gates and cages using their visible parts. [Issue #2](https://github.com/TheWWWorm/CursedLands/issues/2).
- Add an optional HD Lands 1.4.0 texture download for the base campaign on Windows
  and Linux. Installation preserves the original textures and uses a separate mod
  profile. Larger terrain and interface atlases retain their original coordinates.
- Open Mods and rules directly from the main menu. Combine installed mods and
  downloads, add labelled On/Off switches and Apply & restart, and use compact
  profile controls with correctly scaled dropdowns.
- Correct HD HUD frames, bars, tutorial buttons, shops, stats, camp controls,
  maps and dialog borders. Preserve stone grain and border thickness on settings
  buttons. Complete Russian and German settings and mod-menu text.
- Restore ordinary character previews to their authored framing, retain bounds
  for oversized creatures, shrink long names to fit, and fit camp descriptions
  and rune text above the lower controls. Keep item size constant during hover
  rotation, including leather and metal materials.
- Allow movement during first- and third-person attacks while retaining impacts
  and cooldowns. Blend locomotion through the lower body, including strafing and
  backpedaling; keep the head, hair and equipment attached to the final pose.
- Keep the first-person camera steady, show the torso with a closed collar, and
  centre the rendered body beneath the camera. Restore the original figure when
  leaving first person. Use an external view for scripted lying animations.
- Resume direct controls after zone transitions, update the minimap from the
  controlled character, improve nearby chest/mechanism selection, and follow
  narrow passages while sliding around other characters. Turn the body with the
  view, including while strafing.
- Hold Alt to select an attack body part. Add view shortcuts, separate FOV and
  mouse-speed settings, configurable direct-control bindings, controller aim
  options, and crosshair feedback for readiness, contacts, obstructions and reach.
- Give focus to a revived character when it is the only living character under
  the player's control. Downed companions continue earning XP while revival is
  available. Keep newly recruited companions' equipment linked to inventory.
- Recharge enchanted equipment at the original rate and retain enchantments in
  corpse loot. Periodic equipment spells follow simulation pause/speed and village
  casting restrictions. Recognize equipment material names with surrounding spaces.
- Set assembly and disassembly fees to **5%** of the completed item's value,
  including spells. Missing components retain their normal purchase prices.
  Include runes and signed base-price adjustments in enchanted-item prices.
- Restore the activated tunnel golem's Guard motivations and preserve the two
  Ingos gate guards' scripted poses between animation cycles.
- Continuous stamina recovery uses the HP regeneration rate during activity;
  the faster native stamina rate remains available when standing idle.
- Add a saved, host-controlled armour formula choice: original absorption or a
  minimum of 20% damage passing through natural and worn armour.
- Add optional rain puddles on exposed, nearly flat ground, with drying after
  rain. Correct water tile sampling and reflected-edge blending; graphics presets
  retain Mirror when reflections are enabled.
- Stabilize environmental particles, reduce desert dust size, prepare regional
  effects beneath the loading screen, and restore waterfall spray after loading.
- Play the transaction sound after confirmed sales and the clock sound on shared
  pause/speed changes. Keep sound-channel routing changes under the audio lock.
- Animate loading-screen lettering at launch and during map loading in both
  campaigns. Recover the previous graphics settings after interrupted automatic
  calibration and avoid repeating that failed automatic attempt.


See [release notes](docs/releases/1.0.4-experimental.6.md) for compatibility and platform limits.

## 1.0.3-experimental.6 — experimental release, 8 October 2026

- Extend separated simulation to ordinary single-player and include the
  previously validated Retroid presentation improvements. Performance work
  is deferred for this release; stable 60 FPS and the reported Windows 4K
  slowdown remain unresolved.
- Improve co-op loading/input boundaries, movement interpolation, atomic
  trading, character names, personal campaign progress and temporary roles.
  All peers must use this build together (protocol 11).
- Repair partial-figure/corpse visibility, cross-floor melee, Catacombs lift
  recall, village movement/actions, dialogue cameras, long path previews,
  scripted Terror persistence, Shelter travel and guest death presentation.
- Refund all trainable skills and abilities, including starting gifts; make
  escalating ability prices independent of purchase order. Add Gipath shop
  infusion runes and recover identifiable legacy rune records.
- Fill spell/template/rune slots with their correct artwork, retain spell
  colours, merge shop offer stacks and settle sales in one transaction.
- Add experimental shoulder camera, WASD/stick movement and aimed combat;
  gamepads default to this mode, with classic controls still selectable.
- Preserve story roles while including guests in inspected spells, traps,
  guard checks and dragon follow cycles. Preserve scripted NPC behavior and
  target ownership across saves. Compare whole-number script IDs exactly so
  nearby generated actor IDs cannot select the wrong player.
- Publish Linux/Windows x86-64, Android ARM64 and universal macOS packages.
  Validation is focused; Windows/macOS runtime checks, full campaign
  playthroughs and the known remaining co-op/camera cases are still open.
  See [release notes](docs/experimental6-release-notes.md).

## 1.0.3-experimental.5 — experimental release, 7 October 2026

- Provide Linux and Windows x86-64, Android ARM64 and universal macOS packages.
  Android now includes the six common engine patches, native helpers and the
  headless co-op service; its public package retains the previous signing key
  and advances the version code to 15. macOS retains the stock engine and script
  fallbacks. Windows and macOS have not been runtime-tested on their target OS.

- Separate co-op simulation from the local view, with independent desktop
  processes and an optional Android headless service. Retain owner commands,
  pause, saves, movie completion and startup/shutdown lifecycle.
- Extend native processing to AI/perception inputs, route construction,
  animation presentation, particles and bulk buffers, grass/terrain work,
  audio and texture decoding. Cache animation eligibility in the engine.
- Add bounded Android Compatibility terrain caching and smaller terrain draw
  pieces; retain authored geometry, weather, water and soft-ground switching.
- Keep the separated host’s view synchronized during original multiplayer
  base/quest travel, handle liveness checks after shutdown cleanly, and prevent
  delayed automatic thumbnails from overwriting newer manual save images.
- Fix repeated Terror wing animations, creature spell damage and delayed
  callbacks referencing removed casters. Retain all prior gameplay fixes.
- Record desktop and Retroid results with actual simulation progress. Portal
  reaches 20.5 FPS in the final Retroid run; stable 60 FPS at actual 2× is not achieved.
  See the [handoff](docs/performance-handoff-2026-10-07.md) and
  [validation record](docs/experimental5-validation.json).

## Previous local Experimental 4 checkpoint

- Rebuild static navigation and movement sampling around persistent native
  records, reuse unit registry order, cache body-derived health by revision,
  and share co-op combat inputs. Distant AI stays off and normal simulation,
  command and combat timing are retained.
- Prepare character animation bindings during loading to reduce first-use
  gameplay stalls. Portal loading takes about two seconds longer in the test.
- Three interleaved Linux co-op comparisons against the repaired baseline
  average 60% higher Portal FPS and 24% higher Dead City 2× FPS, with lower
  stalls and memory use. These demanding hosts remain CPU-bound; full 2×
  throughput is not yet sustained through the initial load into gameplay.
  See the [systems report and individual measurements](docs/performance-systems-2026-10-07.md).

- Repair the Lost in Astral co-op recruiter exit, Kel's tunnel escape and camp
  stat grants. Scripted walks/turns/clips survive saves; known stuck legacy
  exits and untouched heroes missing a proven camp grant can recover.
- Wait for movie completion on every connected peer before resuming story
  scripts and dialogue. Frame staged conversations from actual actor positions.
  Co-op protocol is now 5; every participant needs the same build.
- Require unobstructed sight for ordinary peripheral and retained party vision,
  while preserving explicit life sense and shared vision through another hero.
- Make quest items clickable for their authored description, retain finished
  shop spells across construction attempts, and correct inventory hover axes.
  See [repairs and validation limits](docs/bugs-2026-10-07.md).

- Restore calm AI scheduling for healthy co-op monsters after player-count
  scaling. Eligibility now reads body-derived health; real wounds keep the
  actor active. Two controlled Dead City co-op runs at 2× average 18% higher
  FPS than Experimental 3, but remain severely CPU-bound. See the
  [follow-up measurements](docs/performance-dead-city-2026-10-07.md).
- Cache validated save choices when opening the co-op host page, avoiding full
  campaign deserialization during every redraw. Reopening refreshes the list.
- Walk the player's village hero to a clicked NPC before opening topics, then
  turn conversation actors in place. This avoids NPCs getting stuck while
  walking to dialogue camera marks. Replacement commands and failed approaches
  clear pending interactions; the first-village story lock remains supported.
- Preserve automatic and side-quest briefing placement. Validate clicked
  conversations on the host and joining player, including completion credit.

- Avoid full route construction for attack/spell choices when a bounded local
  reachability check proves the actor cannot get into range. Open or uncertain
  cases retain the existing planner; all units keep their current simulation rate.
- Feed footsteps and ground deformation from animation advances instead of
  scanning every unit on every rendered frame. Preserve contact geometry,
  footprint events, camera shakes, death cleanup and the Experimental 3 fixes.
- Rebuild the Linux and Windows native modules with the reachability helper.
- Retain character animation track bindings when a movement-start, posture
  transition or one-shot clip finishes. This avoids repeatedly rebuilding a
  model's animation lookup. Playback timing and pose evaluation are unchanged;
  unmodified Godot retains its existing behavior through capability checks.
- Materialize a hidden character's current pose before rebuilding its figure
  for strength/size effects, so the replacement does not inherit stale keys.
- See the [Portal host investigation](docs/performance-portal-2026-10-07.md):
  the supplied co-op scene improved from 2.94 to 5.50 average FPS on the Linux
  test machine. The host remains CPU-bound; the later co-op repairs are described above.


## 1.0.3 Experimental 3

- Include the completed Lost in Astral, fog and soft-ground fixes from the private `lia-test6` build alongside Experimental 2's default CPU improvements.
- Direct named locations now load immediately, including the Lost in Astral recruiter round trip, without opening an empty map chooser.
- Restore Lost in Astral movie narration, pause menu music during the intro and rebuild previously silent movie caches automatically.
- Correct expansion NPC faces in the world and character preview, and use the runtime prototype outfits and weapons when map equipment is not an active override. Equipment changes survive saves and network records.
- Hide the invisible map blockers' stray editor triangles while retaining their collision and script objects.
- Conceal the outer map rim with an opaque 4-metre strip and a softer falloff that clears by 17 metres. Border fog and the lower sky share the horizon colour; volumetric mist no longer attenuates diffuse light twice. Applies to both campaigns.
- Show carried quest items in the upper belt row, separately from consumable quick items, in both campaigns.
- Snow and sand deformation produces continuous trails following rendered soles, paws and leg tips, including legged enemies. Snow banks have softer uneven edges and local geometry shadows; sand impressions are much shallower. Tracks fade within four minutes, use bounded caches and clear on map changes or loads.
- Retain the faster footprint bookkeeping and authoritative corpse effects from Experimental 2. Co-op protocol remains 4; all participants should use the same experimental build.
- See the [combined-build measurements and validation](docs/experimental-3.md): 869 packaged Linux checks passed; the tested scene averaged 3–5% lower FPS than Experimental 2, with overlapping run ranges.

## 1.0.3 Experimental 2

- Add shared AI activity scheduling: calm NPCs keep their patrol deadlines and movement while avoiding redundant decisions. Combat, player orders, scripts and wake-up events retain their ordinary updates. The default scheduler does not use camera visibility.
- Reduce repeated AI/party/quest-light reads and footprint bookkeeping during gameplay.
- In repeated River and Islands starting-scene tests on a Ryzen 9 5950X/RTX 3090, average FPS increased by about 13% at normal speed and 32% at double speed versus Experimental 1, with Distant AI off. See [measurements and limits](docs/performance-experimental-2.md).
- Build navigation grids in bulk on Windows/Linux and cache derived foliage masks locally to shorten subsequent map loads.
- Retain all Experimental 1 fixes and its existing desktop animation runtime. The optional Distant AI approximation remains off by default; it is separate from the new scheduler.
- Derived activity state is rebuilt after loading; the save format and co-op protocol remain unchanged. All co-op participants should use this same experimental build.
- Internal ambient random-number consumption can differ from the old scheduler. Full campaign playthroughs and Windows/macOS/Android device testing remain outstanding.

## 1.0.3

- Windows retains its unsigned native acceleration module. If it cannot load, startup stops with a localized explanation and an Open Windows Security button instead of silently continuing through the script path. Windows can still show its own policy dialog first.
- Integrated the completed desktop performance work: native ordered perception queries, fewer repeated animation and preview updates, and a larger global shader buffer. Windows and Linux ship the normal patched Godot templates; Android, macOS and Web retain the stock engine.
- Corrected repeated move orders, ground-height raster rounding and the movement corridor used for approaching melee strikes.
- Dialogue staging restores its saved camera lifecycle consistently across host and client conversations. Extreme Modern-camera occlusion remains under investigation.
- Character details retain overflow effects and the height ruler. Buff counters now use simulation ticks, survive saves and update correctly on clients through pause and shared speed changes.
- Corpse blood pools use the death timeline once, retain their saved history and synchronize across co-op zone and load changes.
- Co-op protocol is now 4. All players must use the same compatible release.
- Remaining limits from 1.0.2 still apply; focused synthetic and co-op fixtures do not establish a full campaign playthrough or Retroid frame rates.

## 1.0.2

- Lost in Astral:
  - Added expansion data import, including the supported two-disc ISO edition, without running its installer. Keep both games installed and switch between them from the original-style menu controls.
  - Each campaign keeps separate saves and imported files. Browser storage retains both game libraries; browser ISO import is unavailable.
  - Installed folders accept original, lowercase and mixed-case game-data names for both campaigns. Source names stay unchanged; ambiguous case aliases are refused. Data-pack preparation and browser imports normalize their own stored paths.
  - Added a visible expansion co-op entry, campaign-specific hero choices and synchronization of scripted party replacements and waiting-party bags. Waiting-party mercenary records no longer overwrite an active companion’s identity and equipment on clients.
  - Support the expansion's chapter rosters, escorts and moving floors. Network explanations wrap within their panels, and damage, experience and hit labels scale together for readable displays.
- Appearance:
  - Strength and Weakness temporarily broaden or slim the body in the world and character previews. The saved and trained base physique remains separate and returns when the effect expires.
  - Bare dead trees stay still in the wind; leafy versions of the same model, bushes and grass retain their movement.
  - Map-border fog now uses a narrower 4-metre band by default, keeping playable ground clearer on the first Lost in Astral mission. Boundary fog stays active with Original look; the menu retains its softer 6-metre band.
  - Quest targets now use the softer purple glow shown in the original-game reference, preventing washed-out ground and neon grass around quest lights.
  - Spear goblins use their authored pike in the world and character preview; ranged goblins keep their sling.
- Movement:
  - Drawbridges in River and Islands lower quickly by default and become walkable only when fully lowered. Raising closes them immediately. The host controls the timing in co-op; an Original timing choice preserves the original motion and access timing.
  - Zone transitions require a deliberate click inside the open exit by default. An optional setting keeps automatic transitions, and scripted story transfers still work.
  - Double-clicking the ground stands up from crouching or lying down and runs, with the normal transition and space check. Single clicks keep the current stance.
  - Restored the original ground-picking solver so oblique clicks on narrow elevated bridges select the deck instead of the water beneath it.
  - Village movement and F1 selection keep the party leader after hiring a companion.
- Visibility:
  - Wandering wisps are visible again in the world and character preview, using their translucent texture instead of the opaque-unit alpha cutoff.
  - Fixed distant enemies appearing in the world and minimap merely because campaign scripts give them names. Applies to fresh games and loaded saves; co-op still shares sight through living party members.
- Performance:
  - Windows and Linux x86-64 use a compiled navigation kernel with the same route, movement and simulation rules. Other platforms retain the improved script path.
  - Reduced repeated navigation, perception, movement and sound work. Controlled Linux co-op measurements reduced host world work by about 33%; this does not establish Windows or Retroid frame rates.
- Co-op:
  - Hiring and dismissing village companions preserves their live character state, buffs and stamina. Scripted village characters no longer receive prototype AI spell actions.
  - Client movement-mode controls now play the live posture transition instead of using the instant pose restoration intended for loading saves.
- Interface:
  - Restored full original ability descriptions and rank details in the multiplayer character screen, including hover help for learned abilities. Corrected learned-row placement so the rows no longer overlap skill controls.
  - Training applies each purchase immediately. The default interface now explains this and hides the unused Accept/Cancel controls on that screen; transaction controls retain their actual enabled states.
  - Inventory and shop scrolling now use the original shaded arrow artwork and scrolling states, while keeping the corrected click targets.
  - Belt items, including the Goblin doll, return to their original size after deselection. Refused immediate use clears targeting, and unenchanted dolls do not enter target mode.
- Loading:
  - Keep newly created or resized portrait and character previews transparent until their first rendered image is ready. Hidden previews suspend rendering and retain their previous update policy.
- Saves:
  - Looted creatures added by scripts, including Orcs, no longer respawn after loading. Retained loot history is honored in older saves; deaths already lost and re-saved cannot be recovered automatically.
- Remaining limits:
  - The complete legal campaign script route and cooperative ending have passed automated checks. Complete ordinary combat playthroughs in single player and co-op remain unverified.
  - Direct public-IP play still needs a two-player retry across routers. Dense and snowy regions can remain CPU limited on Retroid Pocket 5; controlled Linux measurements do not establish Windows or Retroid frame rates.
  - The reported Modern dialogue-camera clipping with Estera and an ogre found in water remain unresolved.

## 1.0.1

- Co-op:
  - The host can pause and choose 2× speed for everyone. Campaign parties share vision.
  - Clients receive correct equipped and trained character stats, a notice when the host saves, and a loading screen that blocks actions while the host loads.
  - Character imports preserve supplied starting and trained skill levels. Levels already lost by an older import cannot be recovered automatically.
  - Clients cannot load a local save during a session. Death notices can be dismissed and clear after a host load; loading time no longer inflates the displayed ping.
  - Mercenaries respect their owner in conversations. An optional setting keeps hired companions across regions.
  - Late-join checks compare controller records while both players remain connected.
- Multiplayer and Internet:
  - The host screen suggests the public Internet address before LAN and VPN routes, preserves the external port and explains private router addresses.
  - Added an optional community directory browser and opt-in host listings.
  - Original multiplayer players can travel independently between the base and retained quest map. Character saves, respawn penalties, rewards, body loot and trade refunds stay with their owner.
  - Trades retain offered items until completion and refund them on cancellation, travel or disconnect. Joining requires a valid selected network character.
- Controls and interface:
  - The camp skills screen has a Refund all points button. It returns experience paid for skills and attribute or other perk upgrades, keeping starting allocations, quest gifts and earned experience intact.
  - Gamepad combat targeting skips teammates. Spells and belt items can target party portraits.
  - Added optional gyro pointer controls, sensitivity and calibration. Android Back works before the first controller event; controller B and Android Back produce one action in either order.
  - Fixed inventory and shop arrow hit areas, localized skill descriptions, active-button appearance and menu cursor ownership. Optional icon fitting keeps large item models inside their frames.
  - Item previews, camp filters, returned trade stacks, character armour summaries, perk help and floating hit numbers follow the original layouts and rules more closely.
- Gameplay:
  - Repeated fire-wall damage allows movement to escape. Removed combat targets, looted quest actors and surface-weather objects are handled safely.
  - Corrected native movement costs, turn improvements, block routes, local search windows and walking splines. Route checks no longer accept paths rejected by slopes or unit clearance.
  - Route searches avoid unnecessary whole-map work for connected and unreachable source blocks, reducing AI stalls.
  - Recruited companions can escape overlaps at village exits; fresh routes start from their current position.
  - Script variables retain case and iteration order through saves and multiplayer synchronization.
  - Living NPCs retain script-granted quest items and emptied pockets through saving, loading and revisiting a region. Older saves keep their available inventory; items omitted by older saves cannot be recovered automatically.
  - Keystones remain distinct from ready spells; zero-rune construction and dismantling retain the correct components. Equipped spells can contain duplicates below the original limit.
  - Corrected experience sharing and debt arithmetic for ordinary gains. Living tamed animals keep their experience and derived health and stamina through saving, travel and co-op updates.
- Performance:
  - World logic runs at the original completed 55 ms ticks, with smooth fractional drawing and correct elapsed time during slow frames.
  - Reuse exact animated mesh bounds and camera projection data, with bounded caches and cleanup when scenes close. Animation updates batch unchanged hierarchy work.
  - Navigation reuses exact successful searches and resolves connected regions with less work. Two matched Retroid Pocket 5 comparisons per region reduced total benchmark time by about 7% in a crowded region and 2% in snow, with identical world state and random sequences. These are controlled benchmark gains, not ordinary gameplay frame rates.
  - Retroid Pocket 5 graphics detection is calibrated from 65 menu and region measurements with simulation paused. Adreno 650 on Compatibility uses a conservative 30 FPS fallback with Original look, verified on the device. Manual settings remain intact. This graphics target and the navigation gains do not resolve dense-region CPU latency.
- Appearance, camera and audio:
  - Added grass blades with varied clumps, growth patches, colour, wind and sun shadows, plus shallow snow and sand tracks. Grass keeps clear of walls, rocks, pillars and tree trunks. Both options follow desktop graphics capability and default off on Android.
  - Corrected Original water wave grids and material rules, and rain and snow curves and clipping.
  - Figure materials and terrain lighting use the original vertex colors and light-channel rules; overlapping mapped lights receive the complete ground-shadow factor.
  - Repeated loading stages redraw the retained picture, and detached menu construction avoids invalid scene access.
  - Quest actors retain their sustained quest light and white figure. Electrical hit flashes, including absorbed strikes, reach both players.
  - Corrected fireball, lightning, healing, invoke and stationary spell-light timing, geometry and save replay. Tornado replay retains its creation age.
  - Original camera saves retain internal views and turning, pitch and zoom motion. Original right-drag restores the pointer correctly; optional village opening views use authored camera files.
  - Corrected door and lever timing, equipment textures and layering, footprint and blood dimensions, and minimap heading.
  - Camp music continues on the travel map. Corrected ambient sounds, weapon and animation sounds, acknowledgements and spell outcomes.
- Validation:
  - Checked the complete legal campaign script route through the ending in single player and on a real co-op pair, with matching quest state. Ordinary combat progression remains a separate ongoing check.
  - Fresh-profile save-list checks and repeated tutorial and reload checks now use reliable fixtures and state-based waits.
  - Reviewed the 22 reported issues and feature requests separately from the 134-entry fidelity audit. The audit retains 61 partial entries; review completion does not establish full original-engine parity.
- Remaining limits:
  - Complete ordinary combat playthroughs in single player and co-op remain unverified. Direct public-IP play still needs a two-player retry across routers; the corrected address display and local/VPN checks do not prove that connection.
  - Dense regions remain slow on the Retroid Pocket 5 with extra graphics disabled. Physical gyro aiming feel has limited hardware coverage.
  - Some cooldowns for identical item instances, combat prediction and animation, dialogue staging, script update order, visibility/weather, spell randomness and replay, and renderer/audio details still differ from the original. This includes damaging tornado trajectories, not only cosmetic randomness. Older saves cannot recover metadata that was never stored. Android and browser loading presents the start and end frames while construction blocks intermediate frames.


## 1.0.0

- Options:
  - A new Remake tab holds all of the remake's own settings, sorted into World and textures, Lighting and shadows, Water and effects, Camera, Interface and controls, Gamepad, Gameplay and Network and co-op. The original pages show only the original game's options again. Your saved settings are kept.
  - A new Screen tab gathers display mode, resolution, scaling, anti-aliasing, frame rate, VSync, brightness, contrast and gamma.
  - Graphics starts at the top and holds the "Original look" switch, graphics detection and links to the extra graphics pages.
  - "Original look" is now an on/off switch; switching it off brings the graphics effects back to this device's defaults, or to the settings the graphics test chose. The low-FPS notice and the new-graphics-card test respect this choice.
  - On a controller, B steps back one page, and the lists and tabs wrap around.
  - Remake › Game files… (from the main menu): choose another Evil Islands folder or installer, or import the game data again. The new files are checked in full before they replace the old ones; saves and settings are kept. On Android and in the browser the same entry re-imports or deletes the imported data (saves are kept).
  - Installer imports unpack into a new folder and can be cancelled; a failed or cancelled import leaves the current game files untouched.
  - Crash reports: the game keeps a log on every platform, including Android. If it closed unexpectedly last time, it offers to save the report to your Download folder or copy it; Remake › Export log… does the same at any time.
- Gameplay (closer to the original):
  - Stealing follows the original: success is decided by Use/Steal against the target's own steal skill, with no random roll and no facing check, so the tutorial ogre can be robbed. A failed theft only makes the target hostile. A theft takes a quest item, or else everything the unit carries.
  - Aggressive mode: heroes and companions always fight back when attacked, even from behind, after a missed blow, right after walking or an action, or while following someone. Defensive mode still never fights back.
  - Looting a body now makes noise.
  - Loading a save or entering a zone no longer replays the lie-down / kneel animation.
  - The camera icon above a party face marks the hero the camera is following; in the Original camera style, Home keeps following the hero.
  - The belt, spell, weapon and action buttons act when you let go of the mouse button over them; dragging off a button cancels the click.
  - The party portrait's smile after a kill is shown again. New option "Smiling portraits" (on by default) also smiles after a won fight, looting and finished quests.
  - New option "Enemy health bars" (Off / Auto / Always, default Auto): small bars over nearby visible enemies when you play with a controller or by touch.
- Co-op:
  - Spells already in progress (fireball, acid column, teleport, invoke lightning, clairvoyance, fire and lightning walls, acid fog, fireworks) continue where they were for a player who joins and after loading a save.
  - A mercenary kept for a player who is away puts what it loots or steals into that player's own purse and bag, as in the original; with shared loot on, the others still get their copies.
  - A hero who is dead when the party changes zone with Revive off rises at the zone change and pays the usual death penalty.
  - A player whose characters stand in an exit while the rest of the party is elsewhere sees the original line "We can't leave anyone here!".
- Gamepad:
  - Holding the left stick walks in a straight line instead of wiggling from side to side; the stick moves in the hero's current movement mode at any tilt.
  - Tap L3 for the movement-mode ring (pick with the left stick); hold L3 for names over people and objects; the pointer is on R3. Saved layouts with the old defaults are switched over once. Camera centring is on the RT wheel's Camera page.
  - A (Cross) closes a tutorial window at once.
  - The game-over notice after the hero's death works with the pad.
  - The target's attack mark and name sit just above the unit's real height; enemy health bars sit a little higher.
- Touch:
  - Dragging one finger over the world moves the map; two fingers still turn and zoom.
  - One tap on a party face selects the character and makes the camera follow them.
- Android and browser:
  - The loading screen shows right away when loading a save or starting a game, instead of a frozen picture.
  - Android: fixed the crash after a few minutes of play (looping sounds read past their end).
  - Android: new Screen setting "Renderer": Compatibility (default), Mobile (Vulkan) or Forward+ (Vulkan, experimental), applied after a restart, with an automatic fallback if Vulkan fails. Fixed flat cyan terrain with black blocks on Vulkan.
  - Sun shadows no longer flicker as the time of day passes.
  - Closing the Android app from recent apps is no longer reported as a crash.
  - Browser: sound effects no longer cut out after a while or stay silent from the start; the main menu signpost fits the screen again after importing; imports keep the game's camera files.
- Fixes:
  - A rare crash in the particle effects' background threads; two smaller thread races in the co-op world check and in background movie conversion.
  - A spell missile whose target's body is looted while it is still flying no longer causes errors.

## 0.1.7

- Multiplayer:
  - Games on your local network now appear in a list on the Multiplayer screen with their name, players, island and ping, as in the original. Click one to pick it, double-click to join.
  - Hosts can set an optional password. A wrong password is refused with the original "Incorrect password" message.
  - Original multiplayer game: the player strip on the base screen shows each player's face and status (On map, On Base, Trading, Enters).
  - Player swap, as in the original: click a player on the base strip to offer a swap; it opens when they click you back. Trade bag items and money; both players confirm, and any change resets the confirmation.
- Co-op:
  - A hero told to follow (F) another keeps following after a zone change, as in the original: it waits in villages, picks up again in the next zone, and saves keep it.
  - A mercenary hired by a friend no longer becomes the host's for good when the host loads a save before the friend rejoins. The host holds it until the friend is back.
  - Heroes with their own bags can swap items and money the same way in villages.
  - The player list no longer covers the camp screen's info panel.
- Gamepad:
  - Hold R3 to show names over nearby people, bodies, levers, chests, doors and exits.
  - Camera views 1–4 on the RT wheel's Camera page (LT + pick stores the current view).
  - In the Esc menu, Y quick saves and holding X quick loads.
  - The Multiplayer screen, network characters and the co-op player list work with the D-pad, A, B and Y. A talks to villagers and hires or dismisses mercenaries.
  - The DualSense and DualShock 4 light bar shows the leader's health (option "Light bar shows health").
  - Confirming a wheel pick with A no longer also casts it at once, and potions and heals can target your own hero.
- Fixes:
  - Magic arrows, fireballs, acid columns, teleports and bow shots that are in flight when you save now carry on after loading instead of vanishing.

## 0.1.6

- Fixes and changes:
  - Gamepad support (a remake extra; the original has none): the left stick moves (half tilt walks, full tilt runs, the party follows), the right stick turns and zooms the camera, A acts on the highlighted target, B cancels, Y pauses (hold it for fast speed).
  - Gamepad: controller wheels in the original's bronze style. LB opens spells and actions, RB the belt and weapons (LB / RB turn their pages), RT the inventory, journal, quests, minimap and quick save / load. The wheels pause single player while open.
  - Gamepad: X opens a target ring with the six aimed strikes, steal, follow and examine; X then A repeats the last aimed strike.
  - Gamepad: menus, Options, Load, dialogue, camp and trade screens and the travel map work with the D-pad and A / B; L3 turns on a pointer for anything else.
  - Gamepad: Options → Controls → Gamepad… sets vibration, dead zone, pointer speed, target range, button pictures (Xbox, PlayStation, Nintendo, Steam Deck), stick swap and button rebinding.
  - Gamepad: on-screen prompts and tutorial key names switch to controller buttons while you use one; unplugging the controller pauses single player.
  - Graphics: on first start, a few-second test over the main menu picks settings your device runs smoothly, stepping down from High through Low to "Original look" and, if needed, a lower resolution; phones fall back to a steady 30 FPS. It runs again after a graphics card change but never overrides settings you chose yourself. Options → Lighting and surfaces has "Detect graphics automatically" and "Detect best settings".
  - Graphics: if the game runs well below its target frame rate for about 20 seconds, a small notice offers to lower the graphics one step.
  - New graphics option "Portrait heads" (on by default): people with a face portrait wear its head model on their figure; helmets keep the original head, and "Original look" turns it off.
  - New graphics option "Sharp character textures" (on by default, off under "Original look"): faces, clothes, armour and weapons stay crisp up close, also on the inventory and unit panel figures.
  - Lightning in rain no longer makes the screen pop: the strike's light rises and fades softly and lights the clouds ("Original look" keeps the original hard flash). `--flash-log` now records every strike.
  - Co-op host: a new "Players" list in the Esc menu with Kick and Ban. A removed player returns to the main menu with a notice; a banned player can't rejoin until you stop hosting.
  - Co-op: new host option "Shared loot" (on by default): whatever one player finds or is given, every other player gets an identical copy of, plus the same money. Trades and shop buys are never copied; quest items stay shared by the party.
  - Co-op: story events (the villagers fleeing, conversations, quest steps) now happen once for the whole party instead of once per hero; traps still hit each hero.
  - Co-op: each player's name appears above their hero in their colour (option "Player names above heroes", on by default), and the other players' portraits are smaller and show health and stamina bars.
  - Co-op: heroes and creatures now turn smoothly on a joined player's screen too.
  - Big battles run much more smoothly: units no longer stall the game when closing in on an enemy in a crowd, and large patrols no longer cause periodic slowdowns.
  - Fixed creatures (such as a boar) being drawn where they were last seen after wandering in the fog of war, so attack paths led elsewhere and they jumped to their real spot once they moved.
  - Loading a save resumes that save's level scripts exactly as they were, so events like the praying villagers fleeing in the first level happen again after you load an earlier save.
  - After the intro movies, the original "Please wait... loading" screen now shows while the main menu loads, and loading screens fill their stone progress bar step by step as the zone loads, as in the original, instead of looping the movie.
  - Move-path dots are spaced like the original (0.25 m apart), no longer three times denser for a walking hero.
  - Modern camera: panning sideways with A / D or the screen edge no longer jerks up and down over uneven ground.
  - WASD camera controls and "Companions can revive the hero" are now on by default for new players.
  - Tutorial texts name the keys of your active layout (for example 9 / 0 / - / = for weapons with WASD controls) instead of always the classic keys.
  - Upright phones: the unit panel and minimap share the top row with the message log below them, and the weapon bar and belt stand above the party faces, so nothing on the HUD overlaps in portrait.
  - Multiplayer menu: only one row is highlighted at a time, and captions, descriptions and difficulty labels are centred at any window size or language.

## 0.1.5

- Fixes and changes:
  - Multiplayer: a new, clearer menu in the game's own style. Choose "Host / Join co-op campaign" or "Host / Join multiplayer game", and each page shows only what that game needs, with the addresses to give your friends and the router status in plain words.
  - Multiplayer: a host can now continue one of their saves with friends. Joining a host that runs the other kind of game switches to the right page and tells you what the host runs. WebSocket now sits under Connection settings with a note on when it's needed (only for friends playing in the browser).
  - Water and swamps now follow the original game's rules: the colour comes from the original water textures, lit like the original, with the original transparency. No more milky, fog-like surface, and the sea bed only shows in the shallows.
  - Where a river runs into a bog, the two waters now blend along a soft, natural line instead of blue and teal blocks with stair-stepped edges.
  - Rivers no longer show white streaks or bright floating shapes; reflections are subtle from the normal camera and stronger only at low viewing angles. Shores have a soft edge, rain rings catch the sky, and sun glints stay as gentle as the original's.
  - When your main hero dies, the game-over sound now plays at once and a small notice at the top of the screen offers Load, Main menu or Hide while your companions fight on (Options → Game → Remake extras). With the option off it works as in the original: the fight goes on and the "Game over" box appears only when the party tries to leave the zone.
  - A unit now dies when its health drops below 0.5, as in the original, instead of only at 0.
  - When a wounded or severed arm slows a spell, the caster now freezes mid-cast (on the cast animation's hit frame) until the spell goes off, as in the original, instead of finishing the animation early and standing idle.
  - Aimed-strike keys (Num 8 head, Num 5 body …) can now be pressed once instead of held: the aim cursor stays until your next click, and pressing the key again, Esc or a right click cancels it. Turn off "Aim keys: press once" in Options → Combat keys for the original hold-to-aim.
  - New option "Companions can revive the hero" (Options → Game → Remake extras, off by default): select a living hero or companion and click a fallen party member ("Help Zak up") to get them back on their feet with 1 health after 5 seconds of tending. Works in co-op too.
  - New option "Starting areas on the travel map" (on by default): after you leave the ruins where the campaign begins, they show up on the Gipat travel map as their own outlined area around the village, so you can travel back; what you killed or took there stays that way, and the opening scenes don't play again.
  - Fixed the banshee's scythe floating away from her hands, and bat, dragon and other monsters' wings and robes stretching out of shape, after the monster had played a few different animations.
  - Options: leaving the options screen with ✗ or Esc after changing settings or keys now asks whether to save them; Esc on that box returns to the options.
  - New: network characters for the original multiplayer game. Create a hero on the original screens (name, face, voice, attributes, height, starting weapon / potion / spell, first skills), then rename its clan, view or delete it. Choose or create one on the "Host / Join multiplayer game" pages.
  - Network characters are kept on your computer, one file each, travel with you to any server, and are saved automatically as you play: on joining, on every zone change, after respawning, after trading and every minute or so.
  - Heroes now speak with the voice chosen for them.
  - Multiplayer mode: a hero who dies no longer loses any of their starting experience, as in the original; the 5 % death penalty only applies to experience earned since then.
  - Fixed rare cases where a water, lighting, sky or particle calculation could produce an invalid pixel that bloom spreads into a full-screen flash, and added a `--flash-log` start option that records any sudden screen flash in godot.log.
  - A dead hero or companion is now saved and loaded lying dead, as in the original.
  - macOS: the Anti-aliasing choice "FSR 2" becomes Apple's MetalFX upscaler, and a render scale below 100 % uses MetalFX instead of FSR.
  - Checked that the whole single-player campaign can be finished, from the arrival on Gipat to the end credits: every main quest of Gipat, Ingos and Suslanger completes.

## 0.1.4

- Fixes and changes:
  - Fixed: clicking an enemy again during a fight could stop your character from ever striking (he kept switching between combat and relaxed stance) while the enemy kept attacking.
  - New: play the original game's multiplayer mode. On the co-op screen, the host picks a Base (Gipath, Ingos, Suslanger or the Cave), and the party starts at that base. It uses the original multiplayer maps, monsters and item stats; the base's exit leads to the quest's zone and back.
  - Multiplayer mode: each player has their own gold and bag. When your hero dies, your body keeps the lost gold and everything in your bag, and only you can loot it back.
  - Multiplayer mode: the base's quest giver offers one quest per area. Talk to them to take a quest, talk again to give it back, and return when it's done to collect the reward; the base exit stays closed until a quest is taken.
  - Multiplayer mode: each base's trader has the multiplayer stock, selling both items and spells, and each player pays from their own gold. Each base has its trader and intro conversations from the start.
  - Multiplayer mode: a fallen hero comes back when the party changes zone, as in the original. Their body, with the lost gold and the bag, stays where they fell, even after the party leaves and returns.
  - Multiplayer mode: when the host's hero is dead, the next player with a living hero leads the party through exits. When every hero is dead, the party returns to its base and all heroes rise; their bodies stay where they fell.
  - Web and Android: shaders for spells, fires, lightning, rain, move markers and lit terrain, objects and units are now prepared while the zone loads, so their first use no longer freezes the game.
  - Clicking a character to talk with several party members selected no longer makes the others trail the speaker; as in the original, only one goes, and companions you haven't ordered stay where they are.
  - Fixed party members sometimes freezing next to a large monster (such as the tutorial ogre) while still holding a move order; they now walk around it or give up the order.
  - Saving and loading now keeps body-part wounds (severed and crippled limbs) and active magic effects, with their remaining time, for heroes, mercenaries, pets and the NPCs of visited zones.
  - Restored magic effects reappear already running, without the start burst or sound.
  - Fire walls, lightning walls, acid fog, camp fires and fireworks still burning when you save or leave a zone now continue when you load or come back.
  - Enchanted weapons, armour and wands now keep their own charge. Wear, repair, trading and saving no longer refill it, and two identical wands no longer share a charge.
  - Older saves keep the charges they had.
  - Enchanting now works as in the original: only in a trader's item constructor, by building blueprint + material together with a spell that fits. A weapon or armour needs a spell containing an "it" or "ic" rune; wands take any spell. The spell must also fit the item's spell slots and Energy, and it is charged like any other piece (a fifth of its price).
  - Spell constructor: building from a spell in the bag now works; before, confirming silently did nothing.
  - Following a unit now works as in the original: followers stop about 2 m away, stay put while the leader is 2–4 m off, chase a walking leader by aiming slightly ahead of it, and step aside when the leader walks into them.
  - On the main menu, a hovered signpost board now stays turned while the mouse is on it, instead of springing back after a moment.
  - Hiring Merc1 no longer duplicates the stone short bow. Mercenaries carry their original kit, and nothing is copied into the party bag.
  - Co-op starting kits no longer put the carried weapons into the bag a second time. Party characters also get their prototype's second weapon, as in the original.
  - Scripted scenes that hold a character in place now stop the player from giving that character move, attack and use orders, including in co-op. The scene's own movement still works, and a character held by a scene can still talk to people in a village.
  - "Is this character blocked?" checks in scripts now also count a character who is speaking a scene line, as in the original.
  - Fixed error messages and stray spell effects that could appear after changing zone, loading a game or returning to the main menu while a lasting spell (camp fire, fire wall, poison cloud, fireworks) or a flying spell was still active.
  - Spell hits now wear the armour they hit, as strikes do, and also the caster's weapon in hand.
  - A spell your armour stops completely now counts as a hit that deals no damage.
  - Repairs and full-durability restores no longer refill an enchanted item's charge.
  - Weapons now also wear when a monster's natural armour absorbs a blow, as in the original; for bows and crossbows, the bow or crossbow wears.
  - An arrow or bolt whose shooter dies in flight now still lands with the damage of the shot, as in the original, instead of vanishing.
  - Fixed co-op clients showing natural armour on a mercenary who had lost it on joining a new zone; the armour now matches the host's.
  - Spell constructor: building costs 20% of the keystone and rune prices, and pieces taken from the trader cost their full price, as in the original.
  - Spell constructor: a spell with runes can now be taken apart for 10% of its price, giving back its keystone and runes.
  - Spell constructor: knowledge and stamina limits use the party's best values, as in the original.
  - Spell constructor: in co-op the host checks and settles each build or take-apart as one step, so a failure can't leave runes half-applied.
  - Runes can no longer be put into a known spell for free from the bag; use a trader's spell constructor.
  - New remake option "Severed limbs fly off" (Remake graphics page, on by default): a severed head, arm or leg is cut from the figure, flies off, lands, lies on the ground for 30 seconds, then sinks away. With it off, the cut part stays on the body, bloodied, as in the original; the "Original look" preset turns it off.
  - Camp: in the dressing and skills screens one click (or tap) now acts straight away, as in the original. Clicking an item in the bag puts it on, puts it on the belt, or learns the spell. Clicking an item the hero wears or knows puts it back in the bag. Spells can now be taken off a hero too.
  - Camp: a refused click plays the original cancel sound. Putting on and taking off play the original sounds, and a full weapon, belt or spell list takes nothing more.
  - Camp: removed the remake's Equip / Unequip / Put on belt / Take off belt / Learn / Use / Sell / Buy / Repair / Deconstruct / Build buttons.
  - Items keep their wear and charge when put on or taken off.
  - Removed the remake-only "<spell> on <item>" buttons that enchanted a ready item from the bag.
  - Units now choose routes the way the original does: climbing costs more than descending, steps over 40° are avoided, and swamp and water are priced from the game's ground table.
  - Path costs now include the original's turn penalties. Guards and wandering monsters skip spots that are too costly to reach, such as across a swamp.
  - Ranged monsters now check for a real path before choosing where to back away from their enemies.
  - Deep water now blocks according to the original's depth rules, and crawling units can't enter any water. Units standing in water, and units closing in on an attack target, plan by distance only, as in the original.
  - Shallow lava can now be walked across, as in the original. Units and monsters may cut across it, and it does no damage, also as in the original. Only lava deeper than a unit's height blocks the way.
  - Long paths are planned faster than before, removing the worst stalls on big zones.
  - Options: "Smooth motion" moved to the Lighting and surfaces page; it no longer shares a row with the "Original look" button.

## 0.1.3

- Fixes and changes:
  - Fixed random crashes (the game closing without an error) when lights went out while characters were off screen: after spells, deaths, and when changing zones or loading.
  - Windows: the game now renders through Direct3D 12 by default (Vulkan if D3D12 is unavailable), which stops the occasional whole-screen flash seen on some AMD systems.
  - Party characters no longer have the built-in natural armour the original removes when they enter a zone; only worn armour and protection spells reduce their damage. Toads' acid now hurts Zak, as in the original.
  - Walking, running, sneaking and crawling animations now play at the unit's actual speed, so feet no longer slide over the ground (most visible on running ogres and wolves).
  - All unit animations now play at the original game's speed (one frame per 55 ms tick instead of 20 frames per second).
  - New option "Full experience for companions" (Game page, off by default): in single player your hero and every hired companion such as Khador each get the whole experience of a kill or quest.
  - New option "Show the move path through objects" (Game, on by default): the move path dots and target markers stay visible under water, under arches and behind rocks and walls, faded where covered.
  - Zone exits that are closed for now show red-orange sparkles instead of yellow, as in the original, and change colour when they open or close.
  - The closed message log no longer leaves a black square behind its arrow at the top of the screen.
  - Cacti no longer sway like trees in the wind; they now move only slightly, mostly at the top.
  - Turning the wind effect on or off mid-zone now also reaches plants already placed on the browser and Android renderer.
  - The in-game Esc menu now animates like the original: the signpost rises into place when opened, and each board tilts while you point at it, even while the game is paused.
  - Steal (Science) and Follow show the original's cancel cursor where there is nothing to act on, instead of the spell icon; Follow shows the move cursor over a unit it can follow.
  - Dragging with the left mouse button now shows the selection frame (a thin white outline over a lightly darkened area), as in the original.
  - Water no longer shows black slivers and triangles on its surface, or dark blotches in deep lakes and rivers next to cliffs.
  - Water no longer shows a huge pale sun reflection across lakes and bogs when the camera is zoomed far out; the sun now only glints in small sparkles, no brighter than in the original.
  - Rain and snow now fall in front of trees, rocks and buildings instead of only behind them.
  - Attacking while sneaking or crawling now keeps Zak crouched or crawling all the way to the target; he stands up only to strike, so you can sneak up for a backstab. Double click still makes him get up and run.
  - The camera no longer gets stuck turning instead of moving with WASD (or the arrow keys) after loading: Alt or Ctrl pressed while switching windows during a load no longer stays held down.
  - The "Outer landscape" graphics option is removed.
  - Monsters chasing a fleeing hero now run after it properly instead of gliding along in their attack stance.
  - Leaving a zone to the global map while enemies chase you no longer keeps the battle music playing: the map is silent as in the original (no music, ambience, rain or other zone sounds), combat music no longer carries over into the next zone, and Stay here brings the zone's music and ambient sounds back.
  - On the global map, the camp (inventory) screen can again take weapons, armour and belt items off Zak and hired companions like Khador, or equip them from the bag, and the changes carry into the next zone.
  - A hero's belt holds four items, as in the original; saves with more move the extra items to the bag.
  - Minimap: north is at the top again, as in the original. The map picture, the unit and exit markers, the camera arrow and click-to-jump were all mirrored top to bottom (the save screen's zone picture too).
  - Enemies holding a bow or crossbow (brigand, orc and goblin archers) now have 0 Defence as in the original, so melee blows against them always hit.
  - Named NPCs and mercenaries waiting to be hired now take their Attack and Defence from their weapon and skills, as in the original, instead of fixed prototype values.
  - While a cutscene is being prepared, the Skip button sits right under the progress text.
  - Bats, dragons, succubi, banshees, beholders and other monsters now animate their wing membranes, robes and soft body parts as in the original; bat and dragon wings no longer flap their bones while the skin stays still.
  - The character view in the top-left corner no longer blinks black (or shimmers) when the shown character changes as you move the mouse between characters.
  - Spell hits that armour fully absorbs now still count as hits: a "0" appears and the target reacts and turns hostile, as in the original.
  - Map units with their own stats in the original's map files (some town guards and police, the Hadagan students, the first zone's runners, dragons, the earth elemental block, some villagers) now use those stats instead of their unit type's defaults.
  - Armour spells on worn items now also trigger when struck by spells.
  - Crash logs (godot.log) now record what the game was doing just before a crash.
  - Fixed an FSR warning when switching to a fullscreen resolution below native with render scale above 100%.

## 0.1.2

- Fixes and changes:
  - Minimap: units are now small arrowheads that point the way they face, green for selected, red for hostile, yellow for others, shown only inside the circle; zone exits are shown as yellow squares, as in the original.
  - Spells and belt items work again after loading a game, and spell targeting no longer stays active through a load.
  - Quick save and quick load show the original green "Saving game..." / "Loading game..." notice again, also on the travel map.
  - Options: double-clicking a key's name now also starts reassigning it (previously only the action's name worked).
  - Monsters now come to a packmate's aid: a wolf that hears its packmate fighting walks over and attacks you as soon as it sees you, instead of walking past you.
  - White wolves are white again, and dark boars and other creature variants (hares, tigers, skeletons, deer, trolls…) use their own colours.
  - Combat music plays again after loading a save and for joining players: the zone's opening music no longer restarts on every load (it holds off the combat music while it plays), and the zone's calm music starts right away, as in the original.
  - Wind in foliage: tree stumps, logs and mushrooms no longer sway like trees.
  - Combat: a blow already started now lands even if the target steps away, as in the original (enemies no longer seem to miss when you move), and monsters already fighting can no longer be backstabbed.
  - You can leave a village again after hiring a mercenary. As in the original, the village is left as soon as your hero walks into its exit, without the leave box.
  - The move path's dots and the click marker now lie on stone floors and platforms, and are hidden under water, as in the original (a red marker means the spot can't be reached).
  - The camera can no longer leave the map: in villages it stays over the village, as in the original, and at the map's edges it slides along them.
  - Aimed strikes: the touch Aim buttons show the original body-part icons, tapping any unit strikes the chosen part as the numpad keys do, and touch controls no longer stay on screen for mouse players after an accidental touch.
  - Aimed-strike keys (numpad, as in the original) can be rebound to any key in Options → Combat.
  - Lightning now lights the scene briefly like the original instead of washing the screen white, and the flash can no longer stay on.
  - The 3D figure in the unit panel animates smoothly at the game's frame rate (at least 30 fps on mobile and web).
  - Fire and smoke now draw over characters standing behind a campfire, as in the original.
  - Party face portraits are seen from the original's slightly raised camera angle and size.
  - The heat haze over fires is off in the browser and on Android, where it painted the ground over characters.
  - Fire and spell particles below a water surface are hidden by the water again.
  - Guarded against occasional white flashes of the whole screen at high frame rates (please report if you still see one).
  - Browser: fixed "This site can't be reached" when you open the game again; affected browsers recover on their own after one more visit.
  - Browser: you can press Play while the game is still downloading; it shows the progress and starts as soon as it is ready.
  - Browser: you can now choose your GOG installer (`setup_evil_islands_*.exe`); it is unpacked on your device without being run, so a data pack is no longer needed.
  - Fullscreen and borderless fullscreen now always fill the whole monitor (including 4K and Windows display scaling), and windowed mode fits on screen, so the menu is never cut off.
  - In the browser, Zak takes orders as soon as he has stood up, and the game no longer freezes when the music changes or a sound plays for the first time.
  - In the browser, the camera scrolls at the screen edges as on PC, and stops when the pointer leaves the page.
  - In the browser, the game's cursor has its PC size at any browser zoom or display scaling, so it points exactly where you click.
  - In the browser, the game's cursor no longer flickers to the Windows arrow, also near the screen edges.
  - In the browser, the music no longer drops out when the track changes.

## 0.1.1

- New: Android preview (APK on the Releases page), with touch controls for the original interface.

- New: play in your browser at [cursedlands.wwworm.com](https://cursedlands.wwworm.com/), with nothing to install. You choose your own game folder or `.eipack`; nothing is uploaded, and the game also starts offline after the first visit.

- New: optional fog of war in single player (Game options, on by default). Enemies beyond your party's sight are hidden, using the original multiplayer sight rule. Villages, conversations and cutscenes are never fogged.

- Fixes and changes:
  - No more hard shadow bands and dark patches on hills and cliffs. As in the original, the land does not shadow itself; trees, buildings and characters still cast shadows on it, on any slope.
  - In the browser, lights look the same as on PC. The hero's light no longer makes white blocks, camp fires light the same circle of ground, fires have their glow, the sky has its right colour, and the faint dotted lines along ground tiles are gone.
  - Helmets no longer stain arms and faces with their colours, and characters such as the new Sheriff have their own faces and hair again.
  - Faster graphics defaults: high shadows instead of ultra, SMAA anti-aliasing, cheaper ambient occlusion, bloom and fog, with no visible loss. FSR 2 now really upscales and is the fastest option.
  - While a hero is speaking a scripted line, clicks no longer draw a move path that he then ignores (as in the original, he takes no orders until the line ends).
  - Fixed a freeze in gz19h when the messenger bird was sent while the hero stood on the teleporter.
  - Co-op: a joining player no longer gets disconnected while the host loads a large zone for the first time.
  - Worn armour now reduces spell damage. Neutral creatures you hit, and monsters that see you kill their friend, turn on you, and invisible heroes shimmer so you can tell they are hidden (enemies can still sense them up close).
  - New "Smooth motion" option (on by default) for fluid movement on high-refresh screens. No more stutter when wounds appear, a faster enemy AI, and no more crash on quit.
  - Looting and stealing work from the original distances.
  - Spells follow the original timing and strength: missiles and fireballs hit when they arrive, fire walls and acid fog burn for their whole duration, flying units are not hit by ground areas, and alarms take a moment to raise.
  - The hero's name comes from your edition (Зак, Kiran). The travel map's extra buttons use the game font, and the credits scroll at the original speed.
  - The day passes at the original speed (49.5 s per game hour), so villagers keep their real schedules. Left and right arm and leg wounds are no longer swapped. Levers and other objects can be used from the original distance, which fixes the falling-stone quest.
  - Co-op: up to 6 players, as in the original. Players with a different game edition, or a different remake version, now get a clear message instead of joining a mismatched game. A full game says "server full".
  - Monsters that have seen you keep chasing for as long as they can reach you, as in the original; the invented leash is gone.
  - Monsters only fight back if they are aggressive by nature; timid animals and workers flee instead. Creatures flee from fire walls, acid fog and similar areas.
  - Wands and enchanted weapons and armour have charges, as in the original. Weapon spells fire on every strike while charged, and the invented random chance is gone. Belt items refill when you enter a zone; weapon and armour charges do not. The original camera option now moves, zooms and tilts at the original speeds and limits.
  - The minimap works like the original (zoom disc, whole-map view, centred on the camera). Tooltips show hotkeys, and the objectives screen opens over the paused game.
  - Enchanting uses up the spell, as in the original, and taking an enchanted item apart gives the spell back.
  - Line of sight now follows the original: walls, fences, cages and tree trunks hide units, so sneaking past guards works again (for example, Nalo at the Imperial camp).
  - Zone scripts follow the original more closely: AI moods and their priorities, waiting for units to finish, quest goals completed in order, and the danger checks.
  - Combat: armour layers are now applied in the original's order, aimed strikes hit exactly the chosen body part, and broken armour no longer protects.
  - Co-op: joining players now hear the zone's scripted music. Backspace clears the chat, as in the original.
  - Scripted zone changes now arrive at the right entrance; this fixes the party being killed by a guard on arriving at the Imperial camp.
  - Much faster in big zones (up to 4× in the largest; particle effects now use several CPU cores), with no more stutter when a sound plays for the first time. Tooltips look and sit like the original's.
  - Skipping dialogue now silences the skipped lines, like the original. Heroes and mercenaries say their idle "bored" lines again.
  - Zak's wake-up line and other scripted speech now play. Zone scripts run at the original's speed.
  - Combat sounds are no longer dropped when far-away sounds fill the channels.
  - Heroes and mercenaries say their voice lines on orders, kills and selection, as in the original.
  - Looting, levers and stealing play the original animations. Double-clicking an enemy, body or object runs there.
  - All original keys work, including during pause: Ctrl + click forced attack, held numpad aimed strikes, weapon, belt and camera keys.
  - The spell column is back on the right edge.
  - The save and load notice is back. Loading restores the camera where it was.
  - Game speed and running no longer carry into villages, and villagers no longer walk on the spot.
  - Nothing can hurt the party on the travel map.
  - The talk cursor and villagers' names on hover are back.
  - The dialogue camera is fixed, and so is main-menu hover at high resolutions.
  - The pick-up messages name materials correctly.
  - The fairy messenger has its sparkles.
  - Water reflections are fixed.
  - The map edge is shown as in the original.
  - Walking into a zone exit with the whole party now opens the leave-zone box.
- Co-op:
  - Automatic port opening now also tries NAT-PMP and PCP.
  - IPv6 works.
  - The multiplayer screen is easier to use, with hints, your address to copy, and paste and Enter to join.
  - The co-op options have their own page under Options → Game.
- New:
  - The remake's own texts are translated into Russian and German for those copies of the game.
  - There's an option to keep the mouse inside the game window.

## 0.1.0

First public release.

- The full single-player campaign, from the start to the ending, with the original intro and story videos.
- Online co-op for the campaign: host and join by address, join a game in progress, each player with their own hero and mercenaries.
- Co-op heroes come from each player's own save, with their own gold and bag. Shared quest progress is merged back into the player's own save. There are options for full experience per hero and for scaling monsters to the number of players, plus automatic router setup (UPnP), chat and a player list with ping.
- Modern camera with smooth pan, turn and zoom and see-through for objects in the way. The original camera is available as an option.
- Original combat, AI, pathfinding, scripting, traps, levers and day and night.
- Original interface: HUD, inventory, trading, spell crafting, journal, dialogues, Load and Save screens, difficulty and Options.
- Reads an installed copy or unpacks the GOG installer directly, on Windows, Linux and macOS.
- Display settings: resolution, fullscreen and a frame rate limit. Optional graphics improvements, a scaled interface and cursor.
