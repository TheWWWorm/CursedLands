# Native creature portraits

These ninety 64 × 64 transparent PNGs were rendered directly from the original
Cursed Lands unit models, textures, equipment and rig. The prototype-to-file
mapping is in `manifest.json`; the filename is `<family index>-<zero-based rank>`.
No generated or repainted character design is used.

`tools/benchmarks/arena_portraits_export.gd` creates a full 384-pixel preview and
then a 64-pixel portrait, using a head crop when the rig supports it and the full
figure otherwise. UI texture filtering is nearest-neighbor. Native creatures
without a conventional head keep their characteristic silhouette or crystal group.

Run the exporter through the game’s `--tool=/absolute/path/to/script.gd` argument
with a valid `--ei-path` pointing to the original game data. The export directory
also includes the original-model previews for visual comparison. Runtime portraits
are loaded by `ArenaPortraits` and used in the friendly damage list.
