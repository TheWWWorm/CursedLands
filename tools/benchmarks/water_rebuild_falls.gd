extends "res://src/game/fx/waterfalls.gd"
## Instrument the actual deferred production callbacks; no replacement rules.
var mesh_us := 0
var refreshes := []

func _rebuild() -> void:
	var started := Time.get_ticks_usec()
	super._rebuild()
	mesh_us = Time.get_ticks_usec()-started

func _refresh() -> void:
	var old_builds: int = field.builds
	mesh_us = 0
	var started := Time.get_ticks_usec()
	super._refresh()
	refreshes.append({"refresh_us":Time.get_ticks_usec()-started,"mesh_us":mesh_us,
		"classification_us":field.build_us if field.builds!=old_builds else 0,
		"classified":field.builds!=old_builds,"falls":field.falls.size()})
