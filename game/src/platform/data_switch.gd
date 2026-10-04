class_name DataSwitch
extends RefCounted
## Remake: changing the original game files after the first start (Options ›
## Remake › "Game files…", main.gd change_game_files). The first-run
## screens (SetupScreen on desktop, PortableSetup on Android / web) are shown
## again; whatever they pick goes through `switch_to`:
## - the new files are checked in full first (`verify`: the required files,
##   every res/*.res archive's index and ranges, the database) while the old
##   ones stay open and in use;
## - only then does GameData open them (settings.cfg [game] root); if that
##   still fails the old files are opened again;
## - an old copy the remake unpacked itself (`managed`: user://game,
##   user://game-<n>, user://import-<n>) is deleted only after that, never a
##   folder of the player's; saves, settings.cfg (except the root), keyboard
##   and other user:// files are never touched;
## - the converted movie cache (user://movies) is dropped when the new copy's
##   movies differ (another edition);
## - `restart` then starts the game again into the main menu, so that every
##   cache built from the old files goes (desktop: a new process; web: the
##   page reloads; Android: the main scene is reloaded after `clear_caches`).
## New installer imports unpack into a new folder (`new_import_dir`); a
## failed or cancelled one is removed (`discard`) and the old files stay.

## Folder names under user:// that hold a copy unpacked by the remake.
const MANAGED := "^(game|game-\\d+|import-\\d+)$"
## Tests (tools/reimport_test.gd): called by `restart` in its place.
static var on_restart := Callable()
## Web: CursedFiles.forget reloads the page itself once the data is deleted.
static var _web_reloading := false


## user:// as an absolute path without a trailing slash.
static func _user_base() -> String:
	return ProjectSettings.globalize_path("user://").simplify_path().trim_suffix("/")


static func _abs(path: String) -> String:
	return ProjectSettings.globalize_path(path).simplify_path().trim_suffix("/")


## True when `path` is a copy of the game files the remake unpacked into its
## own data folder (and so may delete): never the player's install folder.
static func managed(path: String) -> bool:
	if path.is_empty() or GameFiles.virtual_path(path):
		return false
	var p := _abs(path)
	return p.get_base_dir() == _user_base() and RegEx.create_from_string(MANAGED).search(p.get_file()) != null


## True when the game files are an imported copy (Android / web, or a desktop
## installer import) that "Delete imported data" may remove.
static func imported(path: String = "") -> bool:
	if path.is_empty():
		path = GameData.root
	return GameFiles.virtual_path(path) or managed(path)


## A new, empty folder name for unpacking an installer (desktop).
static func new_import_dir() -> String:
	var base := _user_base()
	var n := Time.get_ticks_usec()
	while DirAccess.dir_exists_absolute(base.path_join("game-%d" % n)):
		n += 1
	return base.path_join("game-%d" % n)


## Bytes of the files under `path` (symlinked folders are not followed).
static func size_of(path: String) -> int:
	if GameFiles.virtual_path(path):
		var total := 0
		for k: String in GameFiles.manifest:
			total += int(GameFiles.manifest[k].get("size", 0))
		return total
	var d := DirAccess.open(path)
	if d == null:
		return 0
	var total := 0
	for f in d.get_files():
		var file := FileAccess.open(path.path_join(f), FileAccess.READ)
		if file:
			total += file.get_length()
	for sub in d.get_directories():
		if not d.is_link(sub):
			total += size_of(path.path_join(sub))
	return total


## The current game files for the Options tip and the setup screens: the
## folder, or "Imported data, N MB" for a copy in the app's storage (on the
## desktop with its folder unless `with_path` is off).
static func describe(path: String = "", with_path := true) -> String:
	if path.is_empty():
		path = GameData.root
	if path.is_empty():
		return RemakeText.t("No game files selected.")
	if not imported(path):
		return _abs(path)
	var text := RemakeText.t("Imported data, %d MB") % int(round(size_of(path) / 1048576.0))
	if with_path and not Portability.constrained():
		text += " (%s)" % _abs(path)
	return text


## "" when `path` is a complete, readable copy of the game; else the reason.
## Opens nothing GameData uses: the current files stay in use meanwhile.
static func verify(path: String) -> String:
	var err := GameData.validate(path)
	if err:
		return err
	var res := path.path_join("res")
	for f in GameFiles.files(res):
		if f.get_extension().to_lower() != "res":
			continue
		if EIResArchive.open_path(res.path_join(f)) == null:   # index or ranges beyond the file
			return RemakeText.t("Damaged game archive: %s") % ("res/" + f)
	var arc := EIResArchive.open_path(path.path_join("res/database.res"))
	var db := EIDatabase.load_from(arc, true) if arc else null
	if db == null or db.tables.is_empty():
		return RemakeText.t("Could not read the game archives in res/.")
	for rel in ["maps/zone1.mpr", "maps/zone1.mob"]:
		if GameFiles.length(path.path_join(rel)) <= 0:
			return RemakeText.t("Damaged game file: %s") % rel
	return ""


## Switches the game to the files at `path` (see the class notes). Returns ""
## or the reason it was refused; on a refusal nothing changed.
static func switch_to(path: String) -> String:
	path = path.strip_edges()
	var err := verify(path)
	if err:
		return err
	var old := GameData.root
	var old_ok := not old.is_empty() and GameData.validate(old) == ""
	# Web: the import already replaced the data under the same virtual root
	# (web/files.js commits last), so it is never "the same files".
	var same := old_ok and _abs(old) == _abs(path) and not GameFiles.virtual_path(path)
	var old_movies := _movie_stamp(old) if old_ok else ""
	MoviePlayer.shutdown()   # background conversions read the old movies
	err = GameData.open(path)
	if err:
		if old_ok:
			GameData.open(old)
		else:
			GameData.root = old
		return err
	GameData.trace("game files: %s" % _abs(path))
	if same:
		return ""
	if old_ok and (GameFiles.virtual_path(path) or _movie_stamp(path) != old_movies):
		clear_movie_cache()
	var a := _abs(path)
	if managed(old) and not (a + "/").begins_with(_abs(old) + "/"):
		discard(old)
	return ""


## "Delete imported data": the imported copy and the movies converted from it
## go; saves and settings stay. The setup screen follows (`restart`).
static func forget() -> void:
	MoviePlayer.shutdown()
	var old := GameData.root
	if GameFiles.virtual_path(old):
		var bridge := JavaScriptBridge.get_interface("CursedFiles")
		if bridge:
			bridge.forget()   # reloads the page when done
			_web_reloading = true
		GameFiles.manifest = {}
	elif managed(old):
		discard(old)
	else:
		return
	clear_movie_cache()
	GameData.root = ""
	GameData.save_settings()
	GameData.trace("game files deleted")


## Movie names and sizes: a different list means another edition's movies.
static func _movie_stamp(root: String) -> String:
	var dir := root.path_join("movies")
	var out := PackedStringArray()
	if not GameFiles.directory_exists(dir):
		return ""
	for f in GameFiles.files(dir):
		if f.get_extension().to_lower() == "bik":
			out.append("%s:%d" % [f.to_lower(), GameFiles.length(dir.path_join(f))])
	out.sort()
	return ",".join(out)


## Drops the converted movies (user://movies/*.eiv); left alone when the
## folder is a link (tools/isolated.sh shares the real one).
static func clear_movie_cache() -> void:
	var d := DirAccess.open("user://")
	if d == null or not d.dir_exists("movies") or d.is_link("movies"):
		return
	for f in DirAccess.get_files_at("user://movies"):
		if f.ends_with(".eiv"):
			DirAccess.remove_absolute("user://movies".path_join(f))


## Deletes a folder the remake made under user:// (an old or failed import).
## Links inside are removed, never followed; anything outside user:// or not
## named like an import is refused.
static func discard(path: String) -> void:
	if path.is_empty() or not managed(path):
		push_warning("DataSwitch.discard refused: " + path)
		return
	_remove_tree(_abs(path))


static func _remove_tree(path: String) -> void:
	if not path.begins_with(_user_base() + "/"):
		return
	var d := DirAccess.open(path)
	if d == null:
		return
	d.include_hidden = true
	for sub in d.get_directories():
		if d.is_link(sub):
			d.remove(sub)   # the link itself
		else:
			_remove_tree(path.path_join(sub))
	for f in d.get_files():
		d.remove(f)
	DirAccess.remove_absolute(path)


## Static caches built from the original files, emptied before the scene is
## reloaded on another copy (Android; desktop and web start afresh instead).
const CACHES := {
	"res://src/ui/interface800.gd": ["_tex"],
	"res://src/ui/village_name.gd": ["_pers"],
	"res://src/ui/menu_scene.gd": ["_reg_rects"],
	"res://src/ui/load_panel.gd": ["_pictures"],
	"res://src/ui/hud_dial.gd": ["_gait_icons"],
	"res://src/ui/spell_slots.gd": ["_icons"],
	"res://src/ui/game_cursor.gd": ["_frames", "_scaled"],
	"res://src/ei/unit_model.gd": ["_textures", "_surface_textures", "_adbs", "_by_name"],
	"res://src/ei/detailed_head.gd": ["_fits", "_meshes", "_materials"],
	"res://src/ei/anim.gd": ["_libraries", "_morphs"],
	"res://src/ei/acks.gd": ["_sets"],
	"res://src/ei/ei_audio.gd": ["_dirs", "_music_reg"],
	"res://src/ei/figure.gd": ["_models", "_materials", "_world", "_meshes", "_sways", "_sway_images"],
	"res://src/game/unit.gd": ["_hit_frames"],
	"res://src/game/side_quests.gd": ["_all", "_by_id"],
	"res://src/game/gfx.gd": ["_hd"],
	"res://src/game/items.gd": ["_cache"],
	"res://src/game/spells.gd": ["_cache"],
	"res://src/game/surface_materials.gd": ["_foliage"],
	"res://src/game/ai.gd": ["_spell_opts"],
	"res://src/game/music_system.gd": ["_streams"],
}


static func clear_caches() -> void:
	EIAudio.shutdown()
	for path: String in CACHES:
		var s: Script = load(path)
		if s == null:
			continue
		for n: String in CACHES[path]:
			var v: Variant = s.get(n)
			if v is Dictionary or v is Array:
				v.clear()


## Starts the game again into the main menu (or the setup screen when no game
## files are set) after the files changed.
static func restart(tree: SceneTree) -> void:
	if on_restart.is_valid():
		on_restart.call()
		return
	if OS.has_feature("web"):
		if not _web_reloading:
			JavaScriptBridge.eval("location.reload()")
		return
	if not Portability.constrained():
		var args := OS.get_cmdline_args()
		if not OS.has_feature("template"):   # a run from the project folder
			args = PackedStringArray(["--path", ProjectSettings.globalize_path("res://")]) + args
		var user := PackedStringArray()
		for a in OS.get_cmdline_user_args():
			# Not again: the old --ei-path, or a direct start / tool.
			if a.begins_with("--ei-path=") or a.begins_with("--tool=") or a.begins_with("--join=") \
					or a.begins_with("--map=") or a in ["--play", "--host", "--viewer"]:
				continue
			user.append(a)
		if not user.is_empty():
			args.append("--")
			args.append_array(user)
		OS.set_restart_on_exit(true, args)
		tree.quit()
		return
	clear_caches()
	tree.reload_current_scene()
