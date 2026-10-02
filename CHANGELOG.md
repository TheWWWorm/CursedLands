# Changelog

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
