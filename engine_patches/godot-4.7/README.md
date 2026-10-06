# Desktop export templates

The Windows and Linux x86-64 release templates use Godot 4.7, source commit
`5b4e0cb0fd279832bbdd69fed5354d4e5ad26f88`, with the three patches in this
directory. Apply them in the order listed below and build normal release
templates with the standard Godot build instructions:

1. `render-thread-shutdown.patch`
2. `queued-image-snapshot.patch`
3. `unobserved-pose.patch`

The first two patches repair separate-render-thread shutdown and snapshot
mutable images for queued texture uploads. The third lets an unobserved looping
character advance its animation clock while delaying pose evaluation until it
is needed. The game also supports unmodified Godot through capability checks.
Android, macOS and Web use the official 4.7 templates. These patches retain
Godot's MIT license; complete engine notices accompany every release package.
