# Versioning

Starting with 1.0.5, Cursed Lands follows [Semantic Versioning 2.0.0](https://semver.org/).
Historical release names and tags remain unchanged.

Use `MAJOR.MINOR.PATCH` for stable releases:

- **PATCH**: backward-compatible fixes to existing behavior, packaging, downloads,
  rendering or UI. The HD Lands catalogue correction and rune placement fixes
  are 1.0.5, following stable 1.0.4.
- **MINOR**: backward-compatible new features or supported capabilities. Reset
  PATCH to zero. New optional features do not require a major release.
- **MAJOR**: incompatible changes to the compatibility contract below. Reset
  MINOR and PATCH to zero and document the migration.

The compatibility contract covers supported campaign saves and network
characters, user settings and profiles, documented mod/package APIs, documented
tool inputs/outputs, and supported game-data formats. A compatible migration
preserves existing data and behavior; removing support or requiring a lossy or
manual conversion is a breaking change. Internal classes and implementation
details are not a public API.

Co-op uses a separately numbered network protocol and requires matching supported
builds. Release notes must state that protocol and any cross-version restrictions.
A protocol-number change alone does not require a major version: cross-version
co-op is not part of the compatibility promise.

Choose the next version from the latest published stable release and the changes
being shipped. Previews use the next intended stable version with a numbered
suffix, such as `1.1.0-alpha.1`, `1.1.0-beta.1` or `1.1.0-rc.1`. An explicit
`experimental.N` suffix is also valid. Never issue a new preview below an already
published stable version. Published tags and artifacts are immutable; corrections
require a new version.

Use `vMAJOR.MINOR.PATCH` for Git tags and the version without `v` in the game,
release title, package filenames and platform version names. Android's integer
version code must increase for every published APK while retaining the existing
application ID and signing certificate. Platform formats that cannot represent
a preview suffix must carry the numeric version and identify the full preview
version in the game and build metadata.

Record changes in the changelog and release notes. Keep validation evidence in a
separate release record, including build provenance and platform limits.
