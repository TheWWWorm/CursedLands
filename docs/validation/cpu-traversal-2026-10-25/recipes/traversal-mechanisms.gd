extends "/home/llm2x/Documents/EI/local/scratchpad/cpu-traversal-20261025/traversal.gd"
func _ready()->void:
	GameUnit.MeshScreenRect._native_mechanisms = not OS.get_cmdline_user_args().has("--bench-script-mechanisms")
	await super._ready()
