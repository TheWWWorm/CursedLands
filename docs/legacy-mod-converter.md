# Legacy mod converter

The source tree and Experimental 4 **tools.zip** include a Python 3.10+ command-line converter for the subset of
legacy Evil Islands mods representable by mod API 1. No additional Python
packages are required. Its `.eimod` output can be imported through **Mods and
rules** in 1.0.4 Experimental. It is not integrated into the game's import picker.

Extract the complete tools bundle, keeping `convert_legacy_mod.py` and
`package_mod.py` together in its `tools` directory. From the extracted bundle
or repository root:

```sh
python3 tools/convert_legacy_mod.py /path/to/LegacyMod \
  --base-game /path/to/CleanEvilIslands \
  --output /path/to/new-conversion \
  --id example.legacy-mod --version 1.0.0 \
  --campaign cursed_lands --encoding cp1252
```

Unpack the legacy mod first. Supply a clean installation of the campaign and
edition it targets: English/German use `cp1252`; Russian uses `cp1251` (default).
Use `--campaign lost_in_astral` for Lost in Astral. This selection declares the
target; the converter does not infer or certify campaign compatibility. The
supplied ID/version identify the converted package and need not match a legacy
mod's informal version label. The output directory must be new and outside both
inputs. Neither input is modified; existing output directories are never reused.

The output contains `conversion-report.json` and, when all changes are supported,
`<id>.eimod`. `--report-only` suppresses package creation. Exit code 0 means the
analysis found no blockers; exit code 1 means the report contains blockers;
argument/output-directory errors return 2. A conversion is not a playthrough or
a guarantee of identical gameplay: test the package in a new mod profile before
using it for an ongoing campaign or co-op session.

## Supported translation

- Nival binary `config.reg` metadata and `RES` archive mappings; Windows path
  separators and case-insensitive paths. `MOD.Single`/`Multi` restrict the
  generated package's modes. Disabled keys prefixed with `#` or `;` are skipped;
  author contact metadata is retained in the report. Original saves are not
  converted. Archive names use the runtime's Latin-1 byte mapping independently
  of the selected registry/database text encoding.
- Conventional `res/<archive>.res` files when no explicit mapping replaces them.
- Changed existing MMP entries in `textures.res`, WAV entries in `sfx.res`, and
  MP3 entries in `speech.res`. Asset bytes are preserved; this is not an audio
  or image format transcoder. Unchanged entries are omitted.
- Existing-record numeric edits in `database.res` and `databaselmp.res`:
  monster HP, mana, minimum/maximum damage and XP; spell price, mana, range,
  effect and duration; perk cost. All other fields are compared as well.
- Nonconflicting layered archives, including identical duplicate entries.
  Different providers of the same entry are reported as ambiguous instead of
  guessing the legacy loader's priority.

The existing [API 1 limits](mods.md) still apply, including 128 MiB per package,
4,096 ZIP members, 1 MiB manifest and 1,024 database patches. Large packs must
be authored as supported packages; this converter does not silently split them.
The report records base-entry hashes for changed content. These are audit
evidence, not a new runtime requirement: the existing loader does not enforce
base-entry hashes. Use the matching clean installation when computing changes.

## Content that needs a port

`DEV.Plugin`, native libraries, SpellAddon configuration, maps, story scripts,
models, translations, new or removed database records, and unsupported field
changes prevent package creation. Other unhandled configuration and files are
also listed. Top-level README/license/changelog documents may be omitted and
are listed separately. A DLL is never loaded or executed.

A blocked report can still list candidate replacements and numeric patches;
these are an inventory for a future port, not a partially functional package.
Oversized packs are still scanned for other unsupported content. The report's
`candidate_asset_bytes` counts all candidate replacements, including those that
cannot fit in one package; retained payload memory remains bounded.
Do not delete a DLL dependency just to get a successful conversion: its behavior
must first be implemented through a supported engine capability. Different
versions of known plugins will need explicit, tested compatibility adapters.

Malformed archives, duplicate names, path traversal, links, ambiguous casing and
unsupported binary layouts are rejected. Copies containing such paths must be
corrected before conversion. Unknown data is never silently accepted as a
complete conversion.

## Validation

The [real-mod compatibility results](legacy-mod-compatibility.md) record six
downloaded packages and a separate runtime probe using selected real assets.
None of those six complete packages currently converts without blockers.

Run the asset-free Python regression suite from the repository root:

```sh
python3 -m unittest discover -s tools/tests -p 'test_legacy_mod_converter.py' -v
```

`tools/tests/legacy_mod_import.gd` exercises the actual game importer, profile
activation, database patches, audio resolution/decoding, default-profile
restoration and source-file preservation. It needs a converted fixture and
expected-value JSON, plus a private project copy and disposable XDG directories.
It loads data only; it does not run a gameplay route.

`tools/tests/legacy_mod_assets.gd` checks a converted asset-only diagnostic
sample through the actual importer, archive resolver and game image/audio
decoders. Its expected JSON contains an `assets` array with `archive`, `entry`
and `sha256`, plus `width` and `height` for textures. It also requires a private
project copy and disposable XDG directories. Passing a selected sample does
not certify the full mod from which it was taken.
