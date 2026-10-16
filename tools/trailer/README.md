# Cursed Lands reusable trailer

Revision 4 is a 65-second native-game trailer: 3,900 frames, 3840 × 2160, 60 fps, SDR Rec.709. It uses the original “Cool” music and native game sounds, without narration. Titles are supplied in English, Russian and German. The English master is `Cursed-Lands-Trailer-v4-en-2160p60.mp4`; older deliveries remain intact.

## Re-shoot or edit

Install Python 3 with Pillow, FFmpeg and FFprobe. Recording requires the game's custom engine and matching `.pck`/native libraries, your original game files, and the HD Lands package for shots that use it. A stock Godot engine cannot replace the custom renderer. Copy `config.example.json` to a private configuration and fill in the paths.

```bash
python3 tools/trailer/trailer.py validate --config /path/to/local-config.json
python3 tools/trailer/trailer.py probe --config /path/to/local-config.json --only 33-tiger-melee
python3 tools/trailer/trailer.py record --config /path/to/local-config.json --only 33-tiger-melee
python3 tools/trailer/trailer.py compose --config /path/to/local-config.json --language en
python3 tools/trailer/trailer.py verify --config /path/to/local-config.json --language en
```

Omit `--only` to record the selected edit. `--force` creates a fresh take. `compose` changes trims, order, titles and music without re-recording. Use `ru` or `de` for localized titles. To localize the in-game interface too, record its shots with `--language ru` or `de` and use the corresponding original localized data archives.

The portable editable delivery includes selected clean 4K60 MP4 takes, separate PCM game audio, Cool music, fonts, capture scripts and the multilingual manifest. After extraction, install the dependencies and run:

```bash
python3 tools/trailer/trailer.py compose --config edit-config.json --language en
```

The bundle's paths resolve relative to its configuration. Original game data and runtime binaries are not included. Supply them through a private recording configuration for new takes. A `music` configuration entry can replace `cool.mp3`.

## Direct and review shots

`shots` in `trailer.json` defines source recordings. `edit` selects a source `shot`, zero-based `start` frame, exact `frames` duration and optional title for each segment. An empty title leaves the action unobscured. `energy` adjusts the continuous music level for calm, action, feature and ending sections. The current validator accepts 55–65 seconds and requires unique campaign encounters, including four first-person and four third-person fights.

`zone` and `campaign` select native map data. `hour` fixes the light and `seed` fixes the initial random seed. `focus` is a terrain XY point with `focus_height`; `focus_world` is an absolute Godot XYZ target. Godot Z is negative map Y. `eye_from`/`eye_to` are target-relative offsets; `eye_world_from`/`eye_world_to` are absolute positions. Scenic camera motion uses smooth easing. `fov` defaults to 55 degrees.

`probe` saves alternate angles and action start/middle/end frames. `scout_views` supplies named absolute eyes/targets; `scout_locations` supplies map XY centers, terrain-relative lifts and eye offsets. Remove scouting entries before recording. Native map images are north-up: pixel Y is `1 - map_y / map_height`. Review the full take, including camera clearance and impact frames; valid coordinates alone do not make a useful shot.

Direct views use the native first/third-person camera. `track_enemy` smoothly follows the real target; `camera_response` controls heading/tilt smoothing and `camera_distance` sets third-person distance. `minimum_tilt` can constrain first-person framing. `advance_frames` provides continuous movement; `minimum_advance_distance` rejects blocked walks. The recorder maintains the native direct-input watchdog during slow offline rendering, so held input does not expire between simulation frames. Physical mouse input cannot steer the capture camera.

`spell_frames` schedules ordinary native casts, including pre-roll. `aim_parts` selects native aimed melee attacks. Damage and limb physics are never synthesized. `minimum_damage` requires recorded native HP loss; `minimum_severed` checks actual severed limbs. Every combat trim must retain a successful hit and at least eight aftermath frames. Limb-removal trims must include a new severing event inside their own edit window. Contacts alone are insufficient evidence of a hit.

## Campaign accuracy and graphics

Enemy entries identify the original positive MOB `nid` and matching `prototype`. The recorder uses those already loaded actors at their authored coordinates, preserving native enemy equipment and statistics. It rejects missing IDs and relocation offsets. Nearby actors are not removed to fabricate a battle.

`wardrobe` provides regional equipment: Gipath leather/stone, Ingos Kania, Suslanger Hadagan, or late-expansion Kania armour. Material/model combinations are validated. Per-shot `equipment` records staged player attributes, skills and available weapons. The expansion's opening exception uses Kir's native trousers and starting dagger. The original prison camp and rejected opening locations remain excluded; Kir's first map is deliberately included at the user's request.

All new takes use Ultra graphics, automatic quality disabled, native 100% render scale, highest clouds, mirror reflections, Ultra shadows, 16× texture filtering and MSAA 4× + SMAA. Each receipt records resolved options. HD Lands sources mount `community.hd-lands-textures@1.5.0`; its credited author is **Atom**. The contiguous graphics sequence shows clouds, rain/water rings, grass, currents, waterfalls and HD terrain. Rain takes verify that the native surface-rain state and shelter mask are ready. The currents take checks the live flow field at its camera target. Later footage returns to combat before the end card.

## Revision 4 footage

| Source | View | Content |
| --- | --- | --- |
| 33-tiger-melee | First person | Original Ingos white tiger, steel battle axe |
| 34-troll-melee | Third person | Original blue troll on the snow path |
| 35-ogre-melee | Third person | Suslanger ogre among palms, adamantium battle axe |
| 36-fortress-third | Third person | Dar-Ulgorn canal guard, wider camera and smooth tracking |
| 37-dragon-spell | Elevated | Island of Death dragon, lightning and water reflection |
| 38-kir-walk | Third person | Kir walking through Lost in Astral's opening map |
| 39-kir-skeletons | Third person | Kir fighting a native opening skeleton; native flying limbs |
| 40-coop-first | First person | Real second client fighting beside the camera player |
| 41-touch-combat | Isometric | Native screen-touch targeting and combat, no inventory sequence |
| 42–45 | Scenic | Clouds, rain/water rings, grass and stream currents |
| 46-trials-snow | Arena | Current snowy Trials of the Allods map, live fight |
| 47-banshee-melee | First person | Two Rivers banshee with a meteoric sword |
| 48-orc-melee | First person | Original Big Lake orc camp |
| 49-dead-city-spells | Isometric | Native skeleton encounter and spell impacts |

The earlier Ingos lake/castle, waterfall, HD Lands, isometric co-op, wiki, gamepad and end-card sources remain available. Tiger, troll and ogre encounters remain in the cut with new successful melee recordings. Rejected sources remain archived but are excluded from the edit.

Both co-op scenes launch an actual second ENet client. The new first-person take sends a native guest attack command, shows the partner in the same frame and records client identity/movement. The caption states the native campaign limit: **up to 6 players**. Two players are present in these recordings. The private recording connections allow longer loading timeouts for offline 4K rendering.

`46-trials-snow` uses a separately pinned current preview pack, explicitly labelled **Preview**. Its adapter starts a live wave on the current snowy map; it fails if the run is not fighting. Replace the runtime/adapter when that mode changes without altering campaign takes.

The touch shot injects real press/release events on the enemy and verifies that inventory stays closed. A small editorial ring marks finger contact. The controller shot retains the native pie menu. The wiki shot uses the actual in-game wiki and live model preview. The five-second end card includes the uppercase website, repository and wiki addresses, supported platforms and the original-data requirement.

## Recording and validation

The recorder pins each runtime and applies a private viewport override. It checks both the viewport and encoded AVI are 3840 × 2160. Fixed simulation steps and offline MovieWriter output preserve 60 frames per second regardless of render speed. Each take uses an isolated profile; player saves and preferences are not modified. The Linux capture display can be started with `Xephyr :19 -screen 3840x2160 -nolisten tcp -no-host-grab`; choose a GPU that can present to it.

New immutable take directories preserve clean video/audio, screenshots, native hit/movement reports, exact shot settings, frozen capture scripts, command and engine log. A shot's `receipt.json` selects its current take. Early scenery predates frozen drivers but retains its media and specifications. The master's `.project.json` preserves the manifest, selected receipts and soundtrack hash.

The upload master is H.264 High, progressive 4:2:0, Rec.709, a 30-frame GOP, AAC stereo 48 kHz/384 kbps and fast-start MP4. NVENC targets 60 Mbps with a 68 Mbps ceiling; portable x264 uses CRF 16 with the same ceiling. `verify` decodes/counts frames and checks dimensions, rate, duration, codecs and audio. It saves a SHA-256 validation report. PCM game sounds are assembled sample-exactly before the single final AAC encode. Music follows the edit's energy levels, with a final limiter for peak headroom.

Source baseline: stable v1.8.0 (`9da078010abe25ba2756939a8b379ca5ce3444f6`) plus local bridge-ground projection and radial pie-menu fixes. Trials has its own pinned preview runtime. No release tag, published package, public site or YouTube upload is changed by this project.
