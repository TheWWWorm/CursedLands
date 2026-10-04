# Cursed Lands

Play **Evil Islands: Curse of the Lost Soul** («Проклятые земли», Nival, 2000) on a modern engine on Windows, Linux, macOS and Android or in your browser, with the whole campaign playable in **online co-op**.

This is a separate game engine, built in Godot, in the spirit of OpenMW and fheroes2: it reads the Evil Islands files you already own (maps, models, textures, animations, sounds, music, texts, scripts and game tables) and plays them with natively written rendering, combat, AI, scripting and interface systems that follow the original game's rules.

> **You need your own copy of the game.** No game data ships with this engine: no models, textures, music, sounds, videos, texts or maps. Nothing is downloaded for you. The **GOG version** is recommended; it is the one the engine is developed and tested with.

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

- **Windows (x86-64):** extract the ZIP and run `CursedLands.exe`. Windows may warn about an unrecognised app; choose **More info → Run anyway**.
- **Linux (x86-64):** extract the archive and run `CursedLands.x86_64`. If your file manager dropped the executable permission, run `chmod +x CursedLands.x86_64` first.
- **macOS (Apple silicon and Intel):** extract the ZIP and open the app. It is not signed or notarized, so macOS may block the first start; allow it under **System Settings → Privacy & Security**.
- **Android 8+ (ARM64 / x86-64), preview:** install the APK; allow your browser or file manager to install apps when it asks. On first start, choose a game data pack (`.eipack`, see [Play in your browser](#play-in-your-browser)) or the GOG installer (`setup_evil_islands_*.exe`), which is unpacked without being run. Touch controls are explained in the game.
- **Browser (WebGL 2):** nothing to download; [play the hosted version](https://cursedlands.wwworm.com/), see above.
  To host the browser version yourself, use `…-web.zip`. It needs HTTPS and the `Cross-Origin-Opener-Policy: same-origin` and `Cross-Origin-Embedder-Policy: require-corp` headers (included in its `_headers` file).

## Getting started

1. Start the engine.
2. When asked, choose either:
   - the folder of an installed copy of Evil Islands (the one containing `res`, `maps` and `config`), or
   - the GOG offline installer itself (`setup_evil_islands_*.exe`). It is **not run**: the engine unpacks the game files from it once into its own user folder and checks each file. This takes a few minutes, and nothing needs to be installed on Linux or macOS.
3. The chosen folder is remembered. The original intro videos play, then the main menu opens.

**New Game** asks for the difficulty first, as the original does. It can be changed at any time in **Options → Game**.

## Co-op

The whole campaign can be played together. In **Multiplayer**, one player chooses **Host co-op campaign** (a new game or one of their saves); the others choose **Join co-op campaign** and pick the game from the list of games on the local network, or enter the host's address (add `:port` for a game hosted on another port). The host's machine runs the world, and every player controls their own hero and the mercenaries they hire.

- **Bring your own hero.** A joining player can bring the hero from their own single-player save, with their own gold and bag. Anything they earn, loot or buy is kept when they leave. In villages, players with their own bags can swap items and money through the player strip at the top right.
- **Shared progress.** Quests the host completes count for a joining player too, if that player has reached the same point in the story. A player who is further ahead simply helps. A player who is behind gets no credit for quests they have not reached yet. When they leave, the progress they made is merged into a new save of their own, so two players can finish the whole campaign together.
- **Router setup.** The host needs incoming connections on **UDP port 27015**. When the router supports it (UPnP), the port is opened automatically and the address to give friends is shown; otherwise forward the port by hand.
- **In game.** Press **Enter** to chat. A player list under the minimap shows each player's ping, and each player's name appears above their hero in their colour.
- **Host tools.** The host can protect the game with a password; a player who types a wrong one gets the original "Incorrect password" message. The **Players** list in the Esc menu can kick or ban a player; a banned player can't rejoin until the host stops hosting.
- **Options.** Every party member can get the full experience for a kill, instead of a share (on by default). With **Shared loot** (on by default), whatever one player finds, every other player gets a copy of too. Monsters can be made stronger with the number of players.
- **Internet play.** If the router can't open the port automatically, forward UDP 27015 by hand, or use a virtual LAN such as Tailscale, ZeroTier or Radmin VPN and join with its address. IPv6 addresses work too, written as `[address]:port`.
- **Original multiplayer mode.** Instead of the campaign, the host can choose **Host multiplayer game** and pick one of the original game's four multiplayer bases (Gipath, Ingos, Suslanger or the Cave); the others choose **Join multiplayer game** and bring their network character. Take quests from the base's quest giver and play the original multiplayer quest zones. Each player has their own gold and bag, and there is no saving, as in the original. The player strip on the base screen shows every player's face and status; click a player there to offer a swap of items and money.
- Up to 6 players. Everyone needs the same edition of the game (Russian and English editions can play together; the German edition plays with German only). Players can join a game already in progress. Only the host can save. Single-player pauses while menus are open; co-op never pauses.

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
| Numpad + / − | fast / normal game speed (single player) |
| F9–F12 | camera views: Ctrl / Alt + key stores zoom and tilt, the key alone recalls them |
| F5 / F8 | quick save / quick load (host) |
| Space | pause (single player); orders can still be given while paused |
| H | show the last tutorial again |
| Home / N | centre the camera on the selected hero / turn it to face north |
| Arrows, screen edges, PgUp / PgDn, wheel | move and zoom the camera |
| Right drag, Ctrl / Alt + arrows | turn and tilt the camera; middle drag moves it (Modern style: middle drag also turns, Shift + middle drag moves, Delete / End turn, W / A / S / D can move it if enabled in Options) |
| B / J | inventory / journal |
| Esc | game menu: save, load, options, exit |
| Enter / Backspace | co-op: type a chat message / clear the chat |

### Gamepad

A controller works out of the box (a remake extra; the original has none). The left stick moves your hero (half tilt walks, full tilt runs), the right stick turns and zooms the camera, **A** acts on the highlighted target, **B** cancels and **Y** pauses (hold it for fast speed). **LB** opens the spells and actions wheel, **RB** the belt and weapons, **RT** the inventory, journal, quests, minimap and quick save / load; **X** opens a target ring with the aimed strikes. Menus and dialogues work with the D-pad and **A** / **B**, and **L3** turns on a pointer for anything else. Hold **R3** to show names over nearby people, bodies, levers, chests, doors and exits. The **RT** wheel's Camera page holds camera views 1–4, and in the Esc menu **Y** quick saves and holding **X** quick loads. The Multiplayer screens and network characters work with the D-pad as well. On a DualSense or DualShock 4, the light bar shows the leader's health. Vibration, dead zone, button pictures, the light bar and rebinding are under **Options → Controls → Gamepad…**.

## What is there

- **The full campaign**: all islands, villages, quests, conversations, traders, mercenaries, crafting and scripted scenes, played from the start to the ending, with the original intro and story videos.
- **Original rules**: combat with aimed strikes, wounds and stealth, monster AI and spell choice, pathfinding, traps, levers and gates, day and night, follow the original game's behaviour and tables.
- **Original interface**: the HUD, inventory, trading, spell crafting, journal, dialogues, Load and Save screens and Options use the game's own art and texts and its 800×600 layouts, scaled to your screen.
- **Modern camera**: a free camera that pans, rotates and zooms smoothly and fades walls and roofs out of the way, in the style of modern isometric RPGs. The original fixed camera can be chosen under **Options**.
- **Modern display**: any resolution, windowed or fullscreen, a frame rate limit, a sharper mouse cursor at high resolutions, and optional graphics improvements (better water and terrain detail, sky with sun, moon and stars, swaying vegetation, bloom, ambient occlusion, volumetric fog and heat haze) under **Options → Graphics**.
- **Automatic graphics settings**: on first start, a short test over the main menu picks settings your device runs smoothly. It never overrides settings you chose yourself and can be run again from the Options.
- **Gamepad support**: play with a controller (Xbox, PlayStation, Nintendo or Steam Deck button pictures), with radial wheels for spells, belt, weapons and screens, a target ring for aimed strikes, and D-pad control of the menus. See [Gamepad](#gamepad).
- **Language**: the game plays in the language of your copy (the English, German and Russian GOG versions are supported).

The engine is still in development. The campaign can be played through, but not every quest variant and co-op situation has been tested. Please report problems on the [Issues](https://github.com/TheWWWorm/CursedLands/issues) page.

## Saves and settings

Saves and settings are kept in the engine's user folder:

- **Windows:** `%APPDATA%\Godot\app_userdata\Cursed Lands`
- **Linux:** `~/.local/share/godot/app_userdata/Cursed Lands`
- **macOS:** `~/Library/Application Support/Godot/app_userdata/Cursed Lands`
- **Browser:** in the browser's storage for cursedlands.wwworm.com. Clearing the site's data removes them; **Export saves** on the Save screen keeps a backup file.

## Building from source

Open the `game` folder in [Godot 4.7](https://godotengine.org/) and export with the included presets.

## License

The engine's code is licensed under the Apache License 2.0 (see [LICENSE.md](LICENSE.md)); see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for third-party components. Evil Islands and all of its content belong to their respective owners and are not part of this project.

## Donations

If you want to support this development or ones similar to it, you can do it here https://ko-fi.com/wwworm
Please only do it if you have money for it and always be financially responsibe. Nevertheless I am grateful for any support given.
