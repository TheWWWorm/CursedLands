extends Node
## Fail before a costly world load if a private capture adapter cannot parse.
func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--trailer-driver="):
			var script := load(argument.trim_prefix("--trailer-driver=")) as Script
			get_tree().quit(0 if script != null and script.can_instantiate() else 2)
			return
	get_tree().quit(2)
