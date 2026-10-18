# Collaboration

Do not use subagents or delegate to other agents unless the user explicitly asks.
This preference also applies when a skill recommends parallel agent work.

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
