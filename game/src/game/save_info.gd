class_name SaveInfo
extends RefCounted
## What the Load screen lists about a saved game, as the original keeps it next to
## each save (saves\<dir>\info.sav, written
## read; quick / auto saves):
##   u32 0x111, u32 3 (version), f32 gtime (game hours), cstr allod id,
##   cstr zone id, u32 time_t (real save time, version > 1), cstr name
##   (version > 2; empty = the default name).
## and saves\<dir>\shot.sav, the screen stretched to 256×192.
## Remake: the game state stays user://saves/<slot>.sav; beside it
## <slot>.info.sav in the original's format and <slot>.shot.png (256×192).

const DIR := "user://saves"
const SHOT_SIZE := Vector2i(256, 192)

var slot := ""
var name := ""         # "" = default name (default_name())
var gtime := 0.0
var allod := ""
var zone := ""
var time := 0          # unix time of the save
var error := false     # no info: listed as "Error Save" by the original
## The Save screen's first row, the save about to be made (
## Save mode): not on disk yet, its preview is the frame taken when the game
## switched to its menus (`frame`).
var fresh := false
var frame: Image


static func path(slot: String, ext := "sav") -> String:
	return directory().path_join("%s.%s" % [slot, ext])


static func directory() -> String:
	return CampaignProfile.save_directory(GameData.campaign_id)


static func files() -> PackedStringArray:
	return DirAccess.get_files_at(directory()) if DirAccess.dir_exists_absolute(directory()) else PackedStringArray()


static func write(slot: String, gtime: float, allod: String, zone: String, name := "") -> void:
	DirAccess.make_dir_recursive_absolute(directory())
	var f := FileAccess.open(path(slot, "info.sav"), FileAccess.WRITE)
	if f == null:
		return
	f.store_32(0x111)
	f.store_32(3)
	f.store_float(gtime)
	for s: String in [allod, zone]:
		f.store_buffer(s.to_utf8_buffer())
		f.store_8(0)
	f.store_32(int(Time.get_unix_time_from_system()))
	f.store_buffer(name.to_utf8_buffer())
	f.store_8(0)


##  (Save mode): the new entry's directory is "save%d", one more
## than the largest number after "save" among the existing ones (atoi of the
## name from its 5th character).
static func new_slot() -> String:
	var n := 0
	for fn in files():
		if fn.ends_with(".sav") and not fn.ends_with(".info.sav"):
			var slot := fn.get_basename()
			if slot.begins_with("save") and slot.length() > 4:
				n = maxi(n, slot.substr(4).to_int())
	return "save%d" % (n + 1)


## The new Save screen entry for the game as it is now.
static func make_fresh(gtime: float, allod: String, zone: String, frame: Image) -> SaveInfo:
	var i := SaveInfo.new()
	i.slot = new_slot()
	i.gtime = gtime
	i.allod = allod
	i.zone = zone
	i.fresh = true
	i.frame = frame
	return i


## the quick and auto saves (original saveq / savea / saveb; the
## remake's "quick" / "autosave") keep their names: their name cannot be edited.
func is_protected() -> bool:
	return slot in ["quick", "autosave", "saveq", "savea", "saveb"]


##  writes the shot the Save screen took when it opened (from the
## frame captured as the game switched to its menus) as shot.sav.
static func write_shot_image(slot: String, img: Image) -> void:
	if img == null or img.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(directory())
	var i := img.duplicate() as Image
	i.resize(SHOT_SIZE.x, SHOT_SIZE.y, Image.INTERPOLATE_BILINEAR)
	i.save_png(path(slot, "shot.png"))


## The frame on screen, stretched to 256×192 as does. Taken
## once the loading screen is gone (the original's autosave runs on the zone's 10th
## frame): up to 10 frames later, after drawing.
static func write_shot(slot: String, vp: Viewport, still_current := Callable()) -> bool:
	if vp == null or DisplayServer.get_name() == "headless":
		return false
	var destination := path(slot, "shot.png")
	var tree := vp.get_tree()
	for i in 10:
		await tree.process_frame
		if LoadingScreen._current == null and i >= 1:
			break
	await RenderingServer.frame_post_draw
	if not is_instance_valid(vp):
		return false
	if not still_current.is_null() and (not still_current.is_valid() or not still_current.call()):
		return false
	var img := vp.get_texture().get_image()
	if img == null or img.is_empty():
		return false
	img.resize(SHOT_SIZE.x, SHOT_SIZE.y, Image.INTERPOLATE_BILINEAR)
	return img.save_png(destination) == OK


static func read(slot: String) -> SaveInfo:
	var i := SaveInfo.new()
	i.slot = slot
	var f := FileAccess.open(path(slot, "info.sav"), FileAccess.READ)
	if f == null or f.get_32() != 0x111 or f.get_32() > 3:
		# Saves from before the remake wrote info: what the file tells.
		i.time = FileAccess.get_modified_time(path(slot))
		i.error = not FileAccess.file_exists(path(slot))
		return i
	i.gtime = f.get_float()
	i.allod = _cstr(f)
	i.zone = _cstr(f)
	i.time = f.get_32()
	i.name = _cstr(f)
	return i


static func _cstr(f: FileAccess) -> String:
	var b := PackedByteArray()
	while not f.eof_reached():
		var c := f.get_8()
		if c == 0:
			break
		b.append(c)
	return b.get_string_from_utf8()


## Every save, newest first (sorts by the stored time).
static func list() -> Array:
	var out := []
	for fn in files():
		if fn.ends_with(".sav") and not fn.ends_with(".info.sav"):
			var data: Variant = CampaignState.read_data(directory().path_join(fn))
			if data is Dictionary and not CampaignState.compatible_data(data):
				continue
			var info := read(fn.get_basename())
			if not data is Dictionary:
				info.error = true
			out.append(info)
	out.sort_custom(func(a: SaveInfo, b: SaveInfo): return a.time > b.time)
	return out


static func delete(slot: String) -> void:
	for ext in ["sav", "info.sav", "shot.png"]:
		if FileAccess.file_exists(path(slot, ext)):
			DirAccess.remove_absolute(path(slot, ext))


func shot() -> Texture2D:
	if fresh:
		if frame == null or frame.is_empty():
			return null
		var i := frame.duplicate() as Image
		i.resize(SHOT_SIZE.x, SHOT_SIZE.y, Image.INTERPOLATE_BILINEAR)
		return ImageTexture.create_from_image(i)
	if not FileAccess.file_exists(path(slot, "shot.png")):
		return null
	var img := Image.load_from_file(ProjectSettings.globalize_path(path(slot, "shot.png")))
	return ImageTexture.create_from_image(img) if img else null


## saveq «string save_quick», savea «save_auto_enter», saveb
## «save_auto_exit»; else the zone's name («zone <id>»), else «string save_camp».
func default_name() -> String:
	if error:
		return "Error Save"
	match slot:
		"quick": return _t("string save_quick", "QUICK SAVE")
		"autosave": return _t("string save_auto_enter", "Autosave (when entering)")
	var z := _t("zone " + zone, "") if zone else ""
	return z.get_slice("\n", 0).strip_edges() if z else _t("string save_camp", "Camp")


func display_name() -> String:
	return name if name else default_name()


## «%d/%m, %H:%M» of the save's real time (CTime::Format).
func date_text() -> String:
	if time <= 0:
		return ""
	var d := Time.get_datetime_dict_from_unix_time(time + _tz_bias())
	return "%02d/%02d, %02d:%02d" % [d.day, d.month, d.hour, d.minute]


static func _tz_bias() -> int:
	return int(Time.get_time_zone_from_system().get("bias", 0)) * 60


## «allod <id>», else "Unknown".
func allod_text() -> String:
	var a := _t("allod " + allod, "") if allod else ""
	return a.get_slice("\n", 0).strip_edges() if a else RemakeText.t("Unknown")


func zone_text() -> String:
	var z := _t("zone " + zone, "") if zone else ""
	return z.get_slice("\n", 0).strip_edges() if z else zone


## «string save_day»  day,  h:mm (m = gtime · 60; day = m / 1440 + 1).
func day_text() -> String:
	var m := int(gtime * 60.0)
	return "%s  %d,  %d:%02d" % [_t("string save_day", "Day"), m / 1440 + 1, (m % 1440) / 60, m % 60]


static func _t(key: String, fallback: String) -> String:
	var t := GameData.text(key).strip_edges() if GameData.texts else ""
	return t if t else fallback
