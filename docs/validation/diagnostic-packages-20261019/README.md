# Unpublished diagnostic packages

Local Windows x86-64 and Linux x86-64 packages contain production source
`66dda7db` and the existing patched Godot 4.7 desktop runtime. These are
diagnostic builds, not a new release. Version metadata remains `1.17.0`;
no published tags or artifacts were changed.

| Package | Bytes | Validation |
| --- | ---: | --- |
| `CursedLands-diagnostic-66dda7db-windows-20261019.zip` | 46,484,902 | ZIP CRC and every archived file's SHA-256 verified |
| `CursedLands-diagnostic-66dda7db-linux-20261019.tar.gz` | 49,431,993 | Every archived file's SHA-256 and executable mode verified |

The [build manifest](build-manifest.json) records local paths, complete file and
archive hashes, source revision, engine provenance and patch hashes. Each
package also contains `BUILD-METADATA.json`, license notices, Discord setup
instructions and [diagnostic instructions in EN/RU/DE](DIAGNOSTIC.txt).

Both platforms contain the **same PCK bytes**. Windows uses the byte-identical
patched engine recorded in the earlier preview2 manifest; all fourteen patch
file hashes still match. The current native DLL build reports no outstanding
work. Their PE x86-64 exports and dependencies were checked. Windows gameplay,
Direct3D 12 and Discord named-pipe operation were **not executed** on this
Linux machine. `Play-Vulkan.cmd` selects Vulkan without reducing graphics
quality; it is an optional comparison, not a claimed performance fix.

The Linux executable had only debug information removed; the executable
`.text` hash is unchanged from the tested runtime. The packaged runtime passed
all **20 performance-log checks** and then completed the
[release-default sustained gameplay run](../default-render-thread-20261019/README.md).
That run did not reproduce the reported large restart-sensitive FPS loss.

The existing **Export log…** action includes the periodic session measurements.
An affected session should be exported before closing or restarting the game.
The report remains local and nothing is uploaded automatically. Both co-op
players should use the same diagnostic build. A frontend export does not
bundle the private authority's separate worker log.

The source and packages retain the fixes already committed in this branch;
the accompanying benchmark changes affect diagnostics only. The remaining
investigation needs evidence from a session that actually exhibits the larger
slowdown, including its renderer, hardware and effective graphics settings.
