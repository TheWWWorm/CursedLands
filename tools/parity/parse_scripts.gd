extends SceneTree
## Load every staged test script once so parse and analysis errors surface
## without game data, a display or a full run. Run through
## tools/check_test_scripts.py, which stages tools/tests and tools/benchmarks
## and passes the copy as --scripts=<directory>.

var _done := false


## Autoloads such as GameData are registered after the main loop is created,
## so the scripts are compiled on the first frame rather than in _init.
func _process(_delta: float) -> bool:
	if _done: return true
	_done = true
	var root := ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--scripts="): root = arg.trim_prefix("--scripts=")
	var files: PackedStringArray = []
	_collect(root, files)
	files.sort()
	var failed: PackedStringArray = []
	for path in files:
		var script: Variant = ResourceLoader.load(path, "GDScript", ResourceLoader.CACHE_MODE_REUSE)
		if script == null or not script is Script or not (script as Script).can_instantiate():
			failed.append(path.trim_prefix(root).trim_prefix("/"))
	print("PARSE_SCRIPTS ", JSON.stringify({"scripts": files.size(), "failed": failed}))
	quit(1 if failed.size() > 0 else 0)
	return true


static func _collect(directory: String, out: PackedStringArray) -> void:
	var dir := DirAccess.open(directory)
	if dir == null:
		push_error("Cannot open " + directory)
		return
	for name in dir.get_directories():
		if name != "__pycache__": _collect(directory.path_join(name), out)
	for name in dir.get_files():
		if name.ends_with(".gd"): out.append(directory.path_join(name))
