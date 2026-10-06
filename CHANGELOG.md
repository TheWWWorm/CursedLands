# Changelog

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
