extends "res://tools/tests/material_shader_options.gd"
## Draw the real terrain, foliage, character, contact and water variants
## with scene RT requested, including both volumetric-fog combinations.
func _ready() -> void:
	GameData.options.rt_shadows=1;GameData.options.rt_gi=1
	await super._ready()
