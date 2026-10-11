# Cursed Lands

Play **Evil Islands: Curse of the Lost Soul** («Проклятые земли», Nival, 2000) and **Lost in Astral** («Затерянные в Астрале») on a modern engine on Windows, Linux, macOS and Android or in your browser, with **online co-op** support for the campaigns.

This is a separate game engine, built in Godot, in the spirit of OpenMW and fheroes2: it reads the Evil Islands files you already own (maps, models, textures, animations, sounds, music, texts, scripts and game tables) and plays them with natively written rendering, combat, AI, scripting and interface systems that follow the original game's rules.

> **You need your own copy of the game you want to play.** No game data ships with this engine: no models, textures, music, sounds, videos, texts or maps. Nothing is downloaded for you. The original game's **GOG version** is the main tested edition. The expansion can use an installed folder, a data pack or the supported two-disc ISO edition.

Windows and Linux x86-64 and Android ARM64 use compiled hot paths. macOS and the browser retain script implementations. Source and build instructions are in [the native guide](game/src/native/source/README.md).

The newest preview is [**1.0.4 Experimental 1**](https://github.com/TheWWWorm/CursedLands/releases/tag/v1.0.4-experimental.1), with mod profiles and options, Android simulation fixes and improved third-person movement. See its [release notes](docs/releases/1.0.4-experimental.1.md).

The current stable release is **1.0.3**. [Downloads](https://github.com/TheWWWorm/CursedLands/releases/tag/v1.0.3) are available for Linux, Windows, Android and macOS. See the [release notes](docs/releases/1.0.3.md) for the graphics, controls, gameplay and co-op changes, measured performance improvements and remaining platform limits.

## Screenshots

Captured in the engine at 3840×2160 with content read from the GOG version.

![Village](docs/screenshots/village.jpg)
![Sunset over the coast](docs/screenshots/sunset.jpg)
![A fight in the ruins](docs/screenshots/fight.jpg)
![Ruins on the coast](docs/screenshots/ruins.jpg)
![Snowy hills of Ingos](docs/screenshots/snow.jpg)

## Play in your browser

**[Play now at cursedlands.wwworm.com](https://cursedlands.wwworm.com/)** - nothing to install. Open the page, press **Play** and choose one of:

- the GOG offline installer (`setup_evil_islands_*.exe`). It is **not run**: the browser unpacks the game files from it once and checks each one. This takes a minute or two and needs about 1 GB of browser storage;
- the folder of your installed copy of Evil Islands;
- a game data pack (`.eipack`), if you made one.

Your files are never uploaded: the game reads them on your own device and keeps its copy in your browser's local storage, so the next start is quick and works offline.

A data pack is optional. It helps on a phone that has neither the installer nor the game folder: make the pack on your computer and copy it to the phone. You need Python 3 and the [`tools/prepare_game_data.py`](tools/prepare_game_data.py) script from this repository:

```sh
python3 prepare_game_data.py "/path/to/Evil Islands" EvilIslands.eipack
```

The installer and the pack hold your own game files, so keep them to yourself.

Needs WebGL 2 and a desktop-class browser or a recent phone. Browsers can clear their storage, so keep your game files and use **Export saves** on the Save screen now and then. In the browser, co-op can only join a desktop host that has chosen **WebSocket** in its network settings and is reachable at a secure `wss://` address; for the smoothest experience and for hosting co-op, use a desktop package below.

## Download and install

Download the package for your system from the [Releases](https://github.com/TheWWWorm/CursedLands/releases) page.

- **Windows (x86-64):** extract the ZIP and run `CursedLands.exe`. The EXE and native DLL are unsigned. SmartScreen may offer **More info → Run anyway**. Smart App Control is a separate policy: if it blocks the native DLL with `0xC0E90002`, the game shows a notice with an **Open Windows Security** button. You can manually turn Smart App Control Off under **App & browser control → Smart App Control**, then restart the game. This changes protection for all apps; older Windows versions may require a Windows reset to re-enable it. Native acceleration remains required on Windows.
- **Linux (x86-64):** extract the archive and run `CursedLands.x86_64`. If your file manager dropped the executable permission, run `chmod +x CursedLands.x86_64` first.
- **macOS (Apple silicon and Intel):** extract the ZIP and open the app. It is not signed or notarized, so macOS may block the first start; allow it under **System Settings → Privacy & Security**.
- **Android 8+ (ARM64):** install the APK; allow your browser or file manager to install apps when it asks. The APK retains the existing application ID and signing certificate, so it updates earlier releases without uninstalling them. On first start, choose a game data pack (`.eipack`, see [Play in your browser](#play-in-your-browser)) or the GOG installer (`setup_evil_islands_*.exe`), which is unpacked without being run. Touch controls are explained in the game. Older releases also provide x86-64 Android support.
- **Browser (WebGL 2):** nothing to download; [play the hosted version](https://cursedlands.wwworm.com/), see above.
  To host the browser version yourself, use `…-web.zip`. It needs HTTPS and the `Cross-Origin-Opener-Policy: same-origin` and `Cross-Origin-Embedder-Policy: require-corp` headers (included in its `_headers` file).

## Getting started

1. Start the engine.
2. When asked, choose either:
   - the folder of an installed copy of Evil Islands (the one containing `res`/`Res`, `maps`/`Maps` and `config`/`Config`; mixed capitalization is accepted too), or
   - the GOG offline installer itself (`setup_evil_islands_*.exe`). It is **not run**: the engine unpacks the game files from it once into its own user folder and checks each file. This takes a few minutes, and nothing needs to be installed on Linux or macOS, or
   - a game data pack (`.eipack`, see [Play in your browser](#play-in-your-browser)).
3. The chosen folder is remembered. The original intro videos play, then the main menu opens.

**New Game** asks for the difficulty first, as the original does. It can be changed at any time in **Options → Game**.

The setup screen and main menu let you choose **Main game — Evil Islands** or **Expansion — Lost in Astral**. Keep either or both installed; each has separate saves. **Options → Remake → Game files…** manages the two installations. For the expansion's supported CDs, choose **Import Lost in Astral ISO images…** and select both discs together. The engine reads the files without mounting the images or running the installer. Browser ISO import is unavailable; use a folder or data pack there. See [game library and expansion import](docs/campaign_library.md).

In a camp's skills screen, **Refund all points** returns the experience spent on training for redistribution. Starting skills and attributes, free quest rewards and total earned experience are kept. Older characters are supported when their paid training can be reconstructed safely.

Training purchases apply immediately. The default interface hides the unused Accept/Cancel controls on the skills screen and explains this; trade controls still reflect the current transaction.

## Mods and game rules (development source)

1.0.4 Experimental 1 includes **Mods and rules** in the main menu, Options and the in-game menu. Named profiles keep their own saves and network characters; data mods can provide configurable revival, texture/sound replacements and selected balance patches. Shared rules follow the host, and sandbox profiles keep cheat-enabled progress separate. See the [player and mod-author guide](docs/mods.md) and [Quick recovery example](examples/mods/quick-recovery/mod.json). These additions require the experimental build; stable 1.0.3 does not include them.

## Co-op

In **Multiplayer**, one player chooses **Host co-op campaign** (a new game or one of their saves); the others choose **Join co-op campaign** and pick the game from the list of games on the local network, or enter the host's address (add `:port` for a game hosted on another port). The host's machine runs the world, and every player controls their own hero and the mercenaries they hire.

For **Lost in Astral**, select the expansion and use its **Co-op campaign** button above the signpost. Every player needs the expansion and the same compatible remake version. The expansion offers story co-op; the original multiplayer bases belong to the main game.

- **Bring your own hero.** A joining player can bring the hero from their own single-player save, with their own gold and bag. Anything they earn, loot or buy is kept when they leave. In villages, players with their own bags can swap items and money through the player strip at the top right.
- **Shared progress.** Quests the host completes count for a joining player too, if that player has reached the same point in the story. A player who is further ahead simply helps. A player who is behind gets no credit for quests they have not reached yet. When they leave, the progress they made is merged into a new save of their own, so two players can finish the whole campaign together.
- **Router setup.** The host needs incoming connections on **UDP port 27015**. When the router supports it (UPnP), the port is opened automatically. Give friends the address labelled **Internet**, including its port. **LAN** addresses such as `192.168.x.x` work within the local network; VPN addresses work within that VPN. The host screen distinguishes these routes and explains when a public address is unavailable.
- **In game.** Press **Enter** to chat. A player list under the minimap shows each player's ping, and each player's name appears above their hero in their colour. Campaign parties share vision. Clients see a notice when the host saves and a loading screen while the host loads.
- **Host tools.** The host can protect the game with a password; a player who types a wrong one gets the original "Incorrect password" message. The **Players** list in the Esc menu can kick or ban a player; a banned player can't rejoin until the host stops hosting.
- **Options.** Every party member can get the full experience for a kill, instead of a share (on by default). With **Shared loot** (on by default), whatever one player finds, every other player gets a copy of too. Monsters can be made stronger with the number of players. **Shared pause and speed**, on by default, lets the host pause or choose 2× speed for everyone. **Mercenaries travel between regions**, off by default, lets hired companions stay with their owner across allods; enable it under **Options → Remake → Gameplay**.
- **Internet play.** If the router can't open the port automatically, forward UDP 27015 by hand, or use a virtual LAN such as Tailscale, ZeroTier or Radmin VPN and join with its address. IPv6 addresses work too, written as `[address]:port`.
- **Original multiplayer mode.** Instead of the campaign, the host can choose **Host multiplayer game** and pick one of the original game's four multiplayer bases (Gipath, Ingos, Suslanger or the Cave); the others choose **Join multiplayer game** and bring their network character. Take quests from the base's quest giver and play the original multiplayer quest zones. Players can travel independently between the base and the current quest map. Each player has their own gold and bag, and there is no manual world saving, as in the original; network characters are saved automatically. The player strip on the base screen shows every player's face and status; click a player there to offer a swap of items and money.
- Up to 6 players. Everyone needs the same edition of the game (Russian and English editions can play together; the German edition plays with German only). Players can join a game already in progress. Only the host can save and load. Single player pauses while menus are open; co-op menus keep the game running unless the host pauses it.
- **Community game lists.** An optional Internet browser can use a community directory URL configured under the network settings. No directory is configured by default; hosts choose whether to list their game. See [community directory setup](docs/internet_games.md) to run a service with the included Python tool.

## Controls

Keys are read from the game's own `keyboard.ini`. To change one, open **Options**, double-click its row and press the new key. The defaults are the original's:

| Input | Action |
|---|---|
| Left click on a hero / drag a frame | select heroes |
| Left click elsewhere | move, attack, talk, loot or use; a double click does it running |
| 1–8 or the spell column (right edge) | pick a spell, then click a target (the same key again or right click cancels); Ctrl / Alt + key or a double click casts at once |
| P / O / I / U or the belt (bottom right) | pick quick item 1–4, then click a target; Ctrl / Alt + key or a double click uses it at once |
| Q / W / E / R | take weapon 1–4 |
| Ctrl + click | attack the clicked unit, whoever it is; on the ground: move there and attack enemies near that spot |
| Alt + click | move to the clicked spot without attacking or talking |
| Numpad 8 / 5 / 4 / 6 / 1 / 3, then click | aimed strike at the head / body / right arm / left arm / right leg / left leg (harder to hit); the aim stays until the next click (hold the key instead with "Aim keys: press once" off) |
| A | aggressive / defensive stance |
| S / F | use or steal / follow, then click the unit |
| Z / X / C / V | run / walk / sneak / crawl |
| F1–F3, F4 | select hero 1–3 (with Ctrl / Alt: and centre the camera on them), select all |
| , / . / / / ' | hero panel: general / body parts / attributes / spell effects |
| L / K | text window: messages / collected items |
| M | minimap on / off (hold its + / − buttons to zoom) |
| Tab | quests of the current zone |
| Numpad + / − | fast / normal game speed (single player or co-op host with shared speed enabled) |
| F9–F12 | camera views: Ctrl / Alt + key stores zoom and tilt, the key alone recalls them |
| F5 / F8 | quick save / quick load (host) |
| Space | pause (single player or co-op host with shared pause enabled); orders can still be given while paused |
| H | show the last tutorial again |
| Home / N | centre the camera on the selected hero / turn it to face north |
| Arrows, screen edges, PgUp / PgDn, wheel | move and zoom the camera |
| Right drag, Ctrl / Alt + arrows | turn and tilt the camera; middle drag moves it (Modern style: middle drag also turns, Shift + middle drag moves, Delete / End turn, W / A / S / D can move it if enabled in Options) |
| B / J | inventory / journal |
| Esc | game menu: save, load, options, exit |
| Enter / Backspace | co-op: type a chat message / clear the chat |

### Gamepad

A controller works out of the box (a remake extra; the original has none). The left stick moves your hero in a straight line in the current movement mode (tap **L3** for the movement-mode ring), the right stick turns and zooms the camera, **A** acts on the highlighted target, **B** cancels and **Y** pauses (hold it for fast speed). **LB** opens the spells and actions wheel, **RB** the belt and weapons, **RT** the inventory, journal, quests, minimap and quick save / load; **X** opens a target ring with the aimed strikes. Menus and dialogues work with the D-pad and **A** / **B**, and **R3** turns on a pointer for anything else. Hold **L3** to show names over nearby people, bodies, levers, chests, doors and exits. The **RT** wheel's Camera page holds camera views 1–4, and in the Esc menu **Y** quick saves and holding **X** quick loads. The Multiplayer screens and network characters work with the D-pad as well. On a DualSense or DualShock 4, the light bar shows the leader's health. Vibration, dead zone, button pictures, the light bar and rebinding are under **Options → Remake → Gamepad…**. Optional gyro controls move the menu or R3 pointer; enable **Gyro pointer** and calibrate with the controller or handheld held still. Combat targeting skips teammates, while friendly spells and items can target them. After choosing a spell or belt item, a party portrait can also be used as its target.

## What is there

- **Campaign content**: the original islands, villages, quests, conversations, traders, mercenaries, crafting, scripted scenes and story videos, with single-player and co-op support.
- **Original gameplay**: combat with aimed strikes, wounds and stealth, monster AI and spell choice, pathfinding, traps, levers and gates, day and night are reconstructed from the original game's behaviour and tables. Fidelity remains partial in the areas described below.
- **Original interface**: the HUD, inventory, trading, spell crafting, journal, dialogues, Load and Save screens and Options use the game's own art and texts and its 800×600 layouts, scaled to your screen.
- **Modern camera**: a free camera that pans, rotates and zooms smoothly and fades walls and roofs out of the way, in the style of modern isometric RPGs. The original fixed camera can be chosen under **Options**.
- **Modern display**: any resolution, windowed or fullscreen, a frame rate limit, a sharper mouse cursor at high resolutions, and optional graphics improvements (better water and terrain detail, sky with sun, moon and stars, swaying vegetation, bloom, ambient occlusion, volumetric fog and heat haze). Display settings are under **Options → Screen**; the extra graphics pages open from **Options → Graphics** and **Options → Remake**, and **Original look** on the Graphics page turns all of them off.
- **Grass and soft ground**: varied grass blades cast sun shadows on green ground and keep clear of walls, rocks, pillars and tree trunks. Players and legged enemies leave connected trails in snow, with softer raised banks and individual foot impressions; sand deforms much less. Tracks fade within four minutes and clear on map changes or loads. These options are under **Options → Remake → World and textures**. They start enabled on capable desktops; Android defaults and automatic settings leave them off. **Original look** disables them.
- **Automatic graphics settings**: on first start, a short menu test chooses a graphics preset and resolution. Retroid Pocket 5's Adreno 650 Compatibility policy is calibrated against actual renderer costs in game regions and can fall back to Original look at a 30 FPS target. The detector preserves manual choices and can be run again from Options. Its graphics target does not account for every region's simulation cost.
- **Gamepad support**: play with a controller (Xbox, PlayStation, Nintendo or Steam Deck button pictures), with radial wheels for spells, belt, weapons and screens, a target ring for aimed strikes, and D-pad control of the menus. See [Gamepad](#gamepad).
- **Language**: the game plays in the language of your copy (the English, German and Russian GOG versions are supported).

The engine is still in development. Script-driven checks reached the campaign ending in single player and on a real co-op pair with matching quest state. Complete ordinary combat playthroughs and quest variants remain unverified; direct Internet play across different routers still needs an end-to-end retry.

Version 1.0.1's conservative navigation changes preserved identical world state and random sequences in matched tests. Two Retroid Pocket 5 comparisons per region reduced total benchmark time by about 7% in a crowded region and 2% in snow. Dense regions still have severe CPU latency with extra graphics disabled; these measurements do not promise playable frame rates. Physical gyro aiming feel has limited hardware coverage.

The 134-entry fidelity audit has been reviewed, with 61 partial cases retained separately from the 22 reported issues and feature requests. Remaining differences include cooldowns for identical item instances, combat prediction and animation, dialogue staging and script order, visibility/weather, spell randomness and replay, and renderer/audio behavior. Randomness differs for damaging tornado trajectories as well as cosmetic effects. Older saves cannot reconstruct metadata that was never stored, and Android/browser loading cannot present every intermediate frame during construction. Please report problems on the [Issues](https://github.com/TheWWWorm/CursedLands/issues) page.

## Saves and settings

Saves and settings are kept in the engine's user folder:

- **Windows:** `%APPDATA%\Godot\app_userdata\Cursed Lands`
- **Linux:** `~/.local/share/godot/app_userdata/Cursed Lands`
- **macOS:** `~/Library/Application Support/Godot/app_userdata/Cursed Lands`
- **Browser:** in the browser's storage for cursedlands.wwworm.com. Clearing the site's data removes them; **Export saves** on the Save screen keeps a backup file.

## Building from source

Open the `game` folder in [Godot 4.7](https://godotengine.org/) and export with the included presets. The Windows and Linux release packages use the [patched desktop templates](engine_patches/godot-4.7/README.md).

## License

The engine's code is licensed under the Apache License 2.0 (see [LICENSE.md](LICENSE.md)); see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for third-party components. Evil Islands and all of its content belong to their respective owners and are not part of this project.

## Donations

If you want to support this development or ones similar to it, you can do it here https://ko-fi.com/wwworm
Please only do it if you have money for it and always be financially responsibe. Nevertheless I am grateful for any support given.
