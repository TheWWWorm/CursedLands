# Collaboration

Do not use subagents or delegate to other agents unless the user explicitly asks.
This preference also applies when a skill recommends parallel agent work.

# Regression tests

Every issue or bug fix and every feature addition or change MUST include a
regression test in the same change. For fixes, the test must exercise the
reported failure and fail against the unfixed behavior. Register the test in
the relevant test runner, run it, and run related existing regression tests.
Do not mark work complete based only on inspection or a manual spot check.

# Withdrawn RTX 30 package

Never publish, upload, mirror, or bundle the withdrawn RTX 30 / `dlssg_for_sm86`
package or its modified NVIDIA kernels, including in drafts or previews. The
owner permanently withdrew it on 2026-10-24. A general request to push, publish,
or release does not override this prohibition. Keep local historical evidence
out of release staging. Run `python3 tools/check_release_assets.py ASSET...` on
every proposed release asset before uploading; a failure blocks publication.
Do not restore the disabled packaging scripts or use historical recipes to
recreate a distributable copy. See [the withdrawal record](docs/integrations/dlssg-sm86.md).

# Release notes and change logs

Describe the concrete changes made in neutral terms. Do not repeat user reports,
attribute changes to individual reports, or discuss unsubstantiated claims in
release notes or change logs. When a change addresses a GitHub issue, link that
issue. Keep technical validation evidence separate from the change description.

# Versioning

Use Semantic Versioning 2.0.0 for all new releases, starting with 1.0.5.
Follow [the versioning policy](docs/versioning.md): PATCH for compatible fixes,
MINOR for compatible new functionality, and MAJOR for breaking the documented
compatibility contract. Base the next version on the latest published stable
release, keep version metadata consistent, and never replace a published tag or
its artifacts. Historical versions remain unchanged.

# Branding

Use the approved transparent dragon CL artwork in `game/icon.png` for application and public
branding. Regenerate platform files with `tools/generate_branding.cjs`; keep the
approved master unchanged and preserve its alpha channel without adding a
background tile. Include `assets/branding` when staging exports.

Windows releases must embed `assets/branding/icon.ico` in the executable with
`application/modify_resources=true`. For a qualified custom engine, set it as
the export template and export the executable; copying an old executable and
exporting only the PCK leaves its previous file icon in place. Verify the
embedded icon in the final EXE. The macOS preset uses the corresponding ICNS.

# Browser publishing

An authorized "push and publish" must finish with a public GitHub release,
unless the user explicitly requests a draft. Verify that `isDraft` is false;
uploading assets to a draft is not completion. Do not delay GitHub publication
while waiting for browser checks or Cloudflare deployment. Continue that work
independently and report any deployment or browser failures separately.

When publishing a release, rebuild and commit the hosted browser export in
`public/` and its `parts.json` manifest from the release source. Verify a fresh
browser start and an update from the previous service-worker cache, then confirm
the Cloudflare deployment serves the committed assets. Desktop and mobile
release uploads alone do not update the hosted browser build.

For wiki changes, check both the native and standalone web interfaces. Refresh
the hosted UI with `python3 tools/prepare_public_wiki.py --refresh-ui --output
public/wiki`, and run the same tool with `--check` before publishing. Keep the
exported article version intact unless the articles were actually re-exported;
the manifest records the frontend version separately. Exercise new controls in
the public wiki itself, including EN/RU/DE and browser Back/reload.

# Localization

Every player-visible string must be translated into all supported languages
(English, Russian and German), including labels, options, help, errors, status
messages and generated item descriptions. Use the original localized text
archives where available and `RemakeText.t` for remake text. Add both Russian
and German entries with each new or changed English key, including keys chosen
dynamically. Do not expose internal item IDs or raw specifications as names.
Verify translation coverage and readable layout in all three languages.

Every new option must include its label, all choices and its help text in EN/RU/DE
in the same change. Verify dynamically selected option strings as well.

# Development and test sessions

For development and test runs, keep the cursor free, show FPS, and mute all
game audio. Set these values in the development/test profile before launching:

- `confine_mouse=0`
- `show_fps=1`
- `volume_sfx=0`
- `volume_stream=0`
- `volume_voice=0`

Keep these preferences when creating fresh profiles or resetting test settings.
Use an isolated development/test profile; do not change normal player defaults
or overwrite a player's saved preferences for this purpose.
