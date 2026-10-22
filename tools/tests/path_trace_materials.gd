extends "res://tools/tests/material_shader_options.gd"
func _ready() -> void:
	GameData.options.pt_mode=1
	await super._ready()
