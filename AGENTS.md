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

When publishing a release, rebuild and commit the hosted browser export in
`public/` and its `parts.json` manifest from the release source. Verify a fresh
browser start and an update from the previous service-worker cache, then confirm
the Cloudflare deployment serves the committed assets. Desktop and mobile
release uploads alone do not update the hosted browser build.
