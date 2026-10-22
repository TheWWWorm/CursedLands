class_name WikiSource
extends RefCounted
## Read-only installed-campaign context. Alternate-campaign calculations and
## model construction run synchronously, then restore every borrowed global
## and cache before the next game/renderer frame. Never calls GameData.open,
## switches a session, writes preferences, or yields while a context is active.

const DATA := ["root","campaign_id","textures","figures","redress","menus","db","texts","texts_lmp",
	"_db_main","lmp_db","ai_reg","ground_types","_texture_cache","_text_cache"]
const CACHES := {
	"res://src/game/items.gd": ["_cache"],
	"res://src/game/spells.gd": ["_cache"],
	"res://src/game/side_quests.gd": ["_all","_by_id"],
	"res://src/ei/figure.gd": ["_models","_materials","_foliage","_foliage_local","_world","_meshes","_sways","_sway_images"],
	"res://src/ei/anim.gd": ["_libraries","_morphs"],
	"res://src/ei/unit_model.gd": ["_textures","_surface_textures","_adbs","_by_name"],
	"res://src/ei/figure_material.gd": ["_root","_loaded","_archive","_profiles"],
	"res://src/game/surface_materials.gd": ["_foliage"],
	"res://src/game/mod_store.gd": ["_archives","_mounted","startup_error"],
}
var campaign := ""
var state := {}


static func _capture() -> Dictionary:
	var result := {"data":{},"caches":{},"code_page":EIText.code_page}
	for key: String in DATA: result.data[key] = GameData.get(key)
	for path: String in CACHES:
		var script: GDScript = load(path)
		var values := {}
		for key: String in CACHES[path]: values[key] = script.get(key)
		result.caches[path] = values
	return result


static func _apply(value: Dictionary) -> void:
	for key: String in DATA: GameData.set(key, value.data[key])
	for path: String in CACHES:
		var script: GDScript = load(path)
		for key: String in CACHES[path]: script.set(key, value.caches[path][key])
	EIText.code_page = value.code_page


func read(callback: Callable) -> Variant:
	var previous := _capture()
	if not state.is_empty(): _apply(state)
	# Translated reference text belongs to this synchronous wiki read, never
	# to the live journal, inventory or running campaign's text cache.
	var original_texts: Dictionary = GameData._text_cache
	GameData._text_cache = original_texts.duplicate()
	WikiReferenceText.apply()
	var result: Variant = callback.call()
	GameData._text_cache = original_texts
	if not state.is_empty(): state = _capture()
	_apply(previous)
	return result


func load_installed(id: String) -> String:
	campaign = id
	if id == GameData.campaign_id: return ""
	var path := String(GameData.campaign_roots.get(id, ""))
	var error := GameData.validate(path)
	if error: return error
	var previous := _capture()
	# Each alternate context owns fresh caches, so identical internal item,
	# model and texture names cannot alias the running campaign's resources.
	for script_path: String in CACHES:
		var script: GDScript = load(script_path)
		for key: String in CACHES[script_path]:
			var old: Variant = script.get(key)
			if old is Dictionary: script.set(key, {})
			elif old is Array: script.set(key, [])
	GameData.root = path
	GameData.campaign_id = id
	GameData._text_cache = {}
	GameData._texture_cache = {}
	GameData.texts = _archive(path,"texts.res")
	GameData.texts_lmp = _archive(path,"textslmp.res")
	GameData.menus = _archive(path,"menus.res")
	EIText.code_page = EIText.detect_code_page(GameData.texts)
	if GameData.texts == null or CampaignProfile.detect(GameData.texts) != id:
		_apply(previous)
		return RemakeText.t("The installed game does not match this campaign.")
	# Resolve the alternate campaign's installed profile without mounting it
	# into the session or advancing the live data revision.
	var checked := ModStore.resolve(ModStore.profile())
	if checked.error:
		_apply(previous)
		return RemakeText.t("The installed campaign data could not be read.")
	ModStore._mounted = checked.order
	for key: String in checked.order:
		var package: Dictionary = ModStore.catalog[key]
		for override: Dictionary in package.get("overrides", []):
			ModStore._archives[override.archive + "/" + String(override.entry).to_lower()] = String(package._root).path_join(override.file)
	GameData.textures = _archive(path,"textures.res")
	GameData.figures = _archive(path,"figures.res")
	GameData.redress = _archive(path,"redress.res")
	var database := _archive(path,"database.res")
	if database == null or GameData.textures == null or GameData.figures == null or GameData.redress == null:
		_apply(previous)
		return RemakeText.t("The installed campaign data could not be read.")
	GameData.db = EIDatabase.load_from(database)
	error = ModStore.patch_database(GameData.db,false)
	var lmp := _archive(path,"databaselmp.res")
	if lmp:
		GameData.db.fallback = EIDatabase.load_from(lmp,true)
		GameData.db.merge_missing(GameData.db.fallback,"quest_items")
	GameData._db_main = GameData.db
	GameData.lmp_db = false
	GameData.ai_reg = EIRegFile.parse(GameFiles.read(path.path_join("config/ai.reg")))
	GameData.ground_types = {}
	state = _capture()
	_apply(previous)
	return RemakeText.t("The installed campaign data could not be read.") if error else ""


static func _archive(root: String, name: String) -> EIResArchive:
	var path := root.path_join("res/" + name)
	return EIResArchive.open_path(path) if GameFiles.exists(path) else null
