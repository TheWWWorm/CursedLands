# Legacy mod compatibility checks — 2026-10-11

Six downloaded legacy packages were extracted and passed to the converter.
**Zero of six complete mods produced an `.eimod`.** All six returned exit code
1 with explicit blockers; none crashed or silently emitted a partial package.
This is a conversion assessment against mod API 1, not a gameplay playthrough.

## Packages tested

| Mod and tested release | Result | Main blockers | Candidate assets / numeric patches |
| --- | --- | --- | --- |
| [EItweaks 1.0.1](https://github.com/BGforgeNet/EItweaks/releases/tag/v1) | Blocked | 464 unsupported field edits, other database tables, 11 changed text entries, configuration and movie files | 1 / 58 |
| [Universal Mod 0.8.6 beta](https://github.com/Kyr4l/ei-universal-mod/releases/tag/0.8.6) | Blocked | `DEV.Plugin=um.dll`, `um.dll` and `um-engine.dll`, SpellAddon settings, maps/quests, models, new records/assets, overlapping archive providers, package size | 406 / 24 |
| [HD Lands 1.4.0](https://hd-lands.gipat.ru/) | Blocked | 719.47 MiB of candidate textures exceeds 128 MiB; nine new texture entries, credits/version text, bundled optional archive | 294 / 0 |
| [HG Mod 3.6.17](https://allods.gipat.ru/index.php?p=filesei) | Blocked | Maps/quests, models, new records/assets, unsupported database fields and configuration | 15 / 222 |
| [Jamais vu 1.0001](https://allods.gipat.ru/index.php?p=eimodsjamaisvu) | Blocked | 42 `.mob` files, AI configuration, changed/new records, unsupported database fields and text | 0 / 182 |
| [XP Mates 1.0](https://allods.gipat.ru/index.php?p=filesei) | Blocked | `addon.dll`, nine Lua files, AI configuration; no API 1 data replacements | 0 / 0 |

Candidates are individually representable changes, not a working partial mod
or a percentage of compatibility. Some resource changes require other changes
in the same mod. HG and Jamais vu are explicitly historical releases; this
test does not claim coverage of their newer releases.

The EItweaks ZIP also bundles `game.exe` outside its `eitweaks/` mod directory.
That executable was inventoried but not passed off as converter input or run.
HG's `Uninstall.exe` is conservatively reported as native content; its presence
is not evidence of an in-game native dependency. Universal's two DLLs and XP
Mates' `addon.dll` have PE machine type `0x014c` (Windows x86). No downloaded
executables, DLLs or Lua scripts were executed.

## Matching the base installation

Final conversion runs used resources extracted from the owned Russian game
data pack and `--encoding cp1251`. The EItweaks artifact also contains Russian
texts despite its English project documentation: 3,156 of 3,167 common text
entries match the Russian base, compared with 61 of 3,133 against English.
The initial English comparison was discarded for the final compatibility
counts. Resource fingerprints are included in the validation record.

All 763 extracted mod files and 36 base resource files were hashed before and
after the six-package conversion pass; all were unchanged. Inputs remained
read-only for the corrected EItweaks run as well. The Jamais vu ZIP's outer
folder had a legacy DOS-encoded name; only that wrapper directory was renamed
locally to `Jamais-vu`, with its contents unchanged.

## Runtime probe of supported assets

A separate, deliberately incomplete diagnostic sample used exact bytes from:

- HD Lands: seven textures covering DXT1, DXT3 and PNT3; dimensions 64, 512 and
  2,048 pixels; complete and missing mip chains; unit, object, UI and terrain
  assets.
- EItweaks: `acks/hh/scenario/169.wav`.

The converter produced one sample package, and the actual game passed
**62 checks with zero failures** in Godot 4.7 on Linux. Checks covered manifest
validation, import, private profile activation, byte hashes through the archive
resolver, image dimensions, both image-loading paths and generated mipmaps,
WAV decoding, default-profile restoration and unchanged original archives.
The probe used a private copy of the current game source, disposable XDG
directories and the owned English installation. It did not start a zone,
render a gameplay scene or play through either mod.

This demonstrates that these selected real assets work through the existing
API. It does not make either full mod compatible. The sample contains derived
game/mod resources and remains local, outside the source repository.

## Converter fixes from these checks

- Skip disabled `#` settings as well as `;` settings, and accept `AuthorEmail`
  as metadata. EItweaks previously stopped at the disabled `RES.#gipath` key.
- Read high-byte archive names using the same byte mapping as the runtime;
  strict ASCII decoding previously stopped on valid downloaded resources.
- Continue inventorying oversized packs with bounded retained payload memory,
  and report `package_limits` with the total candidate asset bytes instead of
  incorrectly classifying a size limit as an unreadable archive.

The asset-free Python regression suite passes **19 tests**. The original
synthetic importer test is recorded separately in
[the initial converter validation](validation/legacy-mod-converter-2026-10-11.json).

## Reproduction and next target

Download URLs, archive SHA-256 hashes, exact input subdirectories, base resource
hashes, blocker counts and runtime evidence are in
[the real-mod validation record](validation/legacy-mod-real-mods-2026-10-11.json).
No mod binaries are checked into the repository. After extracting a listed
archive, run the command in [the converter guide](legacy-mod-converter.md) with
the listed input subdirectory, Russian base and encoding, and a fresh output
directory. The command intentionally returns 1 for the full packages above.

HD Lands is the most direct next compatibility target: most of its payload is
already supported texture data. An explicit adapter would need to split the
texture replacements into size-bounded packages and account for its new and
auxiliary resources. Such a texture-only port must be labelled separately from
the original full bundle. Increasing the size limit alone does not resolve all
its blockers. Universal Mod and XP Mates require ports of executable behavior;
repacking their files cannot supply those features.
