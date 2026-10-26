extends "/home/llm2x/Documents/EI/local/scratchpad/issues-68-77-20261023/repo/tools/tests/pause_menu_clock.gd"
func _ready() -> void:
	GameData.options.fps_limit=2
	await super._ready()
