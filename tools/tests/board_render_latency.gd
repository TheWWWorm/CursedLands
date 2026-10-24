extends "esc_board_frames.gd"
## #111: repeat the older menu regressions with deliberately delayed pictures.
func _ready() -> void:
	delayed_viewport = true
	await super._ready()
