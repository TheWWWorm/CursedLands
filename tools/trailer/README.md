# Cursed Lands reusable trailer

A native-game recording and editing project: 60 seconds, 3,600 frames, 3840 × 2160, 60 fps, SDR Rec.709. The English first cut uses music and real game sounds, without narration. Russian and German title tracks are supplied in the same manifest.

## Re-shoot or edit

Install Python 3 with Pillow, FFmpeg and FFprobe. Use the game's **custom engine** and its matching `.pck`/native libraries, plus your own original game files. A stock Godot engine is not a substitute for the patched renderer. Copy `config.example.json` to a private machine-specific configuration and fill in its absolute paths. The optional `music` configuration entry replaces the original game's `main.mp3` music track.

Run from this repository:

```bash
python3 tools/trailer/trailer.py validate --config /path/to/local-config.json
python3 tools/trailer/trailer.py probe --config /path/to/local-config.json --only 03-ingos
python3 tools/trailer/trailer.py record --config /path/to/local-config.json --only 03-ingos
python3 tools/trailer/trailer.py compose --config /path/to/local-config.json --language en
python3 tools/trailer/trailer.py verify --config /path/to/local-config.json --language en
```

Omit `--only` to record the entire sequence. Use `--force` for a fresh take even when an identical cached take exists. `compose` changes titles/music without recording again. Select `ru` or `de` for the other title tracks; re-record UI shots with `--language ru`/`de` when the actual in-game interface also needs localization. The English original data must likewise be replaced by the corresponding original localized archives for native campaign text.

Each take has its own folder, clean video, PCM game audio, start/middle/end images, exact shot specification, frozen capture scripts, engine log, command and frame metadata. Existing takes are retained. The `receipt.json` at each shot's root selects the current take. Machine-specific paths, game assets, HD Lands files and generated media live outside Git. The master also gets a `.project.json` snapshot preserving its exact source selection, soundtrack hash and manifest.

The recorder pins a copy of each runtime and writes a private `override.cfg` before starting it. This is essential: `--resolution` by itself can leave Godot Movie Maker recording the project's 1600 × 900 canvas. Both the viewport and the **encoded AVI dimensions** are checked. Recording uses fixed simulation steps and offline frame output; render speed does not drop frames from the 60 fps movie. Every take uses a private user profile, leaving campaign saves and preferences alone.

On this Linux workstation, an isolated capture display was started with `Xephyr :19 -screen 3840x2160 -nolisten tcp -no-host-grab`. An existing suitable display also works. The configured GPU must support presentation to that display. No screen recording of other desktop windows is used.

## Direct a shot

Edit `trailer.json`. The array order is the edit order and `frames` is its exact length at 60 fps. `zone` and `campaign` choose actual original data. `hour` fixes the light, and `seed` (default 6519) fixes the authored random seed.

`focus` is a terrain XY point with optional `focus_height`; `focus_world` is an absolute Godot XYZ target. `eye_from`/`eye_to` are offsets from the target; `eye_world_from`/`eye_world_to` are absolute camera positions. Godot Z is the negative of map Y. The camera follows a smooth eased move between endpoints. `fov` defaults to 55 degrees. A useful shot needs a deliberate subject and an inspected move, not merely a valid coordinate.

Probe mode saves alternative angles and, for action shots, middle and final action frames. A `scout_views` array can supply named absolute `eye` and `target` pairs for location scouting. Alternatively, `scout_locations` supplies a named map-XY `center`, terrain-relative `lift` and camera `eye` offset. Original wiki map images are already north-up: pixel Y is `1 - map_y / map_height`; do not flip them again. Keep scouting-only entries out of the production manifest. Inspect the entire recorded clean clip before accepting it; endpoint images alone cannot prove the path stays clear.

The graphics profile pins **Ultra**: all renderer effects enabled, natural terrain transitions, highest volumetric clouds, mirror water reflections, Ultra shadows, 16× texture filtering, MSAA 4× + SMAA and 100% native render scale. Automatic quality selection is disabled. Each recording logs resolved graphics options. HD Lands shots additionally mount the actual `community.hd-lands-textures@1.5.0` package. The author credit is **Atom**.

Combat uses the original encounter actors at their original MOB coordinates, with native orders, spells, equipment and damage. The manifest records the staged equipment and positions; it does not alter the released game. The co-op shot starts a real second ENet client, sends an ordinary guest movement command and records the participant count and guest positions. A second staged offline character is not used as proof of co-op.

`wardrobe` selects a complete seven-slot regional kit, including trousers and boots: Gipath leather/stone, Ingos Kania armour, Suslanger Hadagan steel, and player-craftable Kania steel for later Lost in Astral scenes. Equipment comes from the original databases and is validated for a real visual model and compatible material. Per-shot `equipment` can additionally set character attributes and skills. The same wardrobe applies to the co-op guest.

Each enemy entry must specify its original positive `nid` and matching `prototype` from the selected zone. The recorder finds that already loaded actor and retains its authored position, skin, equipment and statistics. Missing IDs and relocation offsets are rejected. Nearby actors are not removed to fabricate an encounter. The tactical fight uses the original orc, white wolf and orc spellcaster by the Gipath bridge. Ingos uses its native white tiger; the third-person fight uses the original ogre outside the later Suslanger city (gz18h, NID 150993). The prison-camp fight is explicitly rejected: Zak has no such equipment during that story sequence.

The manifest records the location review and excludes the rejected opening village, arrival manor, prison camp and early expansion locations. Original map descriptions, the campaign shop catalogue, authored MOB actors and inspected frames establish the scene context. Armour must fit the story phase as well as the allod.

First-person combat uses the normal first-person camera and weapon animation. `track_enemy` directs its heading and tilt toward the actual enemy from the live camera position. The coastal ruins and dragon valley, Dead City fountain, Ingos lake/castle and waterfall, later Suslanger irrigation canals and late Jigran Sadrok fortress have explicit reviewed views. `pre_roll` lets a native attack reach the useful part of its animation before the take; `keep_distance` and `approach` send normal movement commands. Physical input is isolated while the director supplies the camera and control commands. No damage or projectile impact is fabricated.

## Extend the edit

Copy a shot entry, assign a unique ID and title key, choose its campaign/runtime and author its camera/action. Add every title line in English, Russian and German under `text`. Keep the main cut near one minute by changing shot lengths; validation currently accepts 55–65 seconds. A different-duration trailer can deliberately change that validation policy.

`12-trials` uses a separately pinned preview runtime and is visibly marked **New mode preview**. It is not presented as a released 1.8.0 feature. Replace that entry and the `arena.gd` adapter when the mode becomes final, without touching the other takes.

`13-wiki` records the real in-game wiki and its live model preview. The caption also gives the public web wiki address. Touch and controller shots show the game's own controls in later Gipath locations. Every radial menu now uses the Alt selector's pie sections, with active-item rims, disabled states and wrapped localized labels. The field HUD can be hidden behind the controller wheel during filming; the actual wheel and its navigation are unchanged. The platform end card names Windows, Linux, macOS, Android and Browser, and reminds viewers that original game files are required.

## Delivery and validation

The upload file is `Cursed-Lands-Trailer-en-2160p60.mp4`. It uses H.264 High, progressive 4:2:0, Rec.709, a 30-frame GOP, AAC stereo at 48 kHz/384 kbps and a fast-start MP4 header. The NVIDIA encoder targets 60 Mbps with a 68 Mbps ceiling; the portable x264 path uses CRF 16 with the same ceiling. These settings follow [YouTube's upload guidance](https://support.google.com/youtube/answer/1722171?hl=en). Rendering follows [Godot's offline movie workflow](https://docs.godotengine.org/en/stable/tutorials/animation/creating_movies.html).

`verify` decodes/counts the final frames and checks dimensions, frame rate, codec, pixel format, duration and stereo sample rate. It saves a validation JSON and SHA-256. Game audio is assembled as exact PCM samples before the single final AAC encode, avoiding per-clip AAC padding drift. The music bed is normalized to the manifest's `music_lufs` target before applying `music_gain`; `sfx_gain` controls native effects. The final limiter reserves peak headroom. Title PNGs, title subtitles, clean takes and separate game-sound audio remain available for another editor.

Source baseline for the first cut: stable v1.8.0 (`9da078010abe25ba2756939a8b379ca5ce3444f6`), with local fixes for ground projection onto bridge decks and consistent radial pie menus, plus the separately identified Trials of Gipath preview pack. Each take pins its exact pack; earlier unaffected shots retain the stable pack. The renderer fix uses authored BASE walking-surface parts in `game/src/game/fx/ground_contact.gd` and `ground_contact_shader.gd`, with rendered regressions in `tools/tests/ground_contact.gd`. The radial renderer is `game/src/ui/pad_wheel.gd`; its existing English, Russian and German strings are retained. No release tag, published game package, public site or YouTube upload is changed by this project.
