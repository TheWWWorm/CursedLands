extends "/home/llm2x/Documents/EI/local/scratchpad/cpu-traversal-20261025/traversal-scopes.gd"
func _ready()->void:
	if OS.get_cmdline_user_args().has("--bench-script-ambient-ground"):
		var script: Variant=load("res://src/game/fx/ambient_habitats.gd")
		script._ground_kernel=null
	await super._ready()
