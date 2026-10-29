# Collaboration

Do not use subagents or delegate to other agents unless the user explicitly asks.
This preference also applies when a skill recommends parallel agent work.

# Cleanup after work

Finish each task by removing the temporary files it created that are no longer
needed: disposable build/export staging, reproducible caches, duplicate downloads,
and superseded test outputs. Inspect existing leftovers too, and remove only
items whose purpose and disposability have been verified. Do not leave large
scratchpad trees behind by default. Record meaningful results and the minimum
useful evidence before removing bulky intermediates; report what was removed
and any large items deliberately retained.

Never treat a name such as `scratchpad`, `tmp`, `build`, or `old`, an ignored Git
status, or age alone as proof that something is junk. Preserve canonical source,
Git common directories and history, uncommitted/untracked work, unmerged branches,
original game assets/installers, saves, credentials, required toolchains, and
unique regression/reference evidence. Check running processes and references
before deleting their inputs or outputs. Inspect worktree status, ignored files,
and branch ancestry before retiring a checkout; use Git worktree commands, or the
Codex archive tool for app-managed worktrees, instead of deleting them blindly.
Do not use blanket `git clean -fdx`, recursive scratchpad deletion, or silent stashes.

Keep a compact workspace map and cleanup records in the workspace's
`local/maintenance/`, outside this Git checkout. Use the workspace's
`local/scratchpad/<task>/` for disposable experiments with an explicit purpose;
keep reusable assets, toolchains, and durable evidence in documented locations.
When something is uncertain, retain it and record why rather than guessing.

# Wine and Proton reuse

Before original base-game, LiA, or Windows remake testing, read
[`docs/wine-proton-workflow.md`](docs/wine-proton-workflow.md).
Reuse the verified toolchains and reference assets registered under the workspace's
`local/runtime/`; do not download or copy an entire Wine/Proton installation
per task or test. Keep base-game, patched LiA, and remake seed prefixes separate
and unchanged. Use one exclusively locked writable prefix per concurrent suite,
reuse it for serial cases, and remove disposable prefixes/caches after preserving
results and unique saves. Never retain a full prefix per screenshot or test case.
Fresh-prefix tests must document why they need isolation and clean up afterwards.
Do not hardlink mutable prefixes or share them between concurrent jobs or runtimes.
Use GPU Lab with `gpu=auto`; historical display numbers and per-case prefix-copy
recipes are not the current workflow. Prefixes marked `RETIRED-BY-CLEANUP.md`
are retained evidence, not runnable templates. Follow the guide's restoration
instructions if an old prefix is deliberately needed again.

# Local main and remote updates

On the Windows workstation, the canonical Cursed Lands integration checkout is
`C:/web/CursedLands`, on branch `main`; `C:/web` is the workspace.
On the Linux workstation, it is
`/home/llm2x/Documents/EI/local/scratchpad/issues-68-77-20261023/repo`,
on branch `main`. That folder name is historical; it is the current Linux main.
`/home/llm2x/Documents/EI` is the Linux workspace, not a Git checkout. Its
`publish/` checkout and `remake/` tree are legacy locations, not the integration source.

Verify the owning checkout with `git worktree list --porcelain` from the current
Cursed Lands repository; use the entry for `refs/heads/main`. If it moves,
update this location in both the workspace and repository `AGENTS.md` files.
Start new work from the current local main so accepted, unpublished fixes are
retained; `origin/main` alone can be older than the local integration state.

Before any authorized update to remote `main` or publication:

1. Inspect local main's status and history. Preserve other work and uncommitted
   changes; do not reset them away or silently stash them.
2. Fetch `origin` and compare `main...origin/main`. Integrate incoming remote
   commits and the accepted task branches into local main, using fast-forward
   merges where possible and resolving divergence without dropping either side.
   Local main MUST be up to date with remote main and contain the intended local
   fixes before updating the remote.
3. Run the required regressions on the integrated source. Build any release
   artifacts from that same verified commit. Confirm the checkout is on `main`,
   clean, and still at the verified commit before pushing.
4. Push from this integration checkout with a normal, non-forced
   `git push origin main:main`. Do not bypass stale local main by pushing a topic
   branch directly to remote main. If remote main advances, fetch, integrate and
   recheck affected behavior before retrying.
5. Verify that remote `refs/heads/main` matches the intended local main commit.
   Keep local main synchronized with the final remote state.

These instructions describe the workflow; they do not authorize a push or release.

# Issue and bug fixes

Verify the reported failure before changing behavior. Compare the affected logic
with the original game code and check the corresponding original behavior under
Wine. Record the comparison evidence and distinguish confirmed behavior from
inferences. If an original comparison is inapplicable or cannot be performed,
document the reason and the remaining uncertainty.

Preserve existing functionality and previous fixes. Review related code, fix
history and regression coverage, keep changes focused, and check adjacent
behavior and affected game modes. Run the new regression test and related
existing regressions as required below. Investigate failures before declaring
the fix complete; do not weaken earlier regression tests to make a fix pass.

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

## High-resolution UI

Keep all player-visible text crisp and readable on high-resolution displays,
including 2560×1440 and 3840×2160. Rasterize fonts and vector icons at their
displayed scale; do not enlarge low-resolution text or icon bitmaps. Check
padding, alignment, wrapping, clipping, hit targets, and safe-area placement
at normal and high resolutions in English, Russian and German. Include
high-resolution regression coverage and retained visual evidence for UI changes.

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
