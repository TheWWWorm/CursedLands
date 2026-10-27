extends Node
## The original's Esc signpost is already in place on the first frame after
## Esc (Wine recording, 25 fps), although its code requests the rise clip
## uspecial02. By default the remake opens on that clip's last frame; the
## esc_menu_rise option shows the rise.
var checks := 0
var failures := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL ", message)

func pose(sp: EscSignpost) -> Array:
	var out := []
	for n: Node in sp._post.find_children("*", "Node3D", true, false):
		if not n is MeshInstance3D: out.append((n as Node3D).transform)
	return out

func same(a: Array, b: Array) -> bool:
	if a.size() != b.size() or a.is_empty(): return false
	for i in a.size():
		if not (a[i] as Transform3D).is_equal_approx(b[i]): return false
	return true

func open(sp: EscSignpost) -> Array:
	sp.visible = false
	await get_tree().process_frame
	sp.visible = true
	return pose(sp)

func _ready() -> void:
	var row: Array = GameData.OPTIONS.filter(func(r: Array) -> bool: return r[0] == "esc_menu_rise").front() if \
		GameData.OPTIONS.any(func(r: Array) -> bool: return r[0] == "esc_menu_rise") else []
	check(row.size() == 6 and row[1] == 1 and row[2] == 2 and row[3] == 18 and row[4] < OptionsPanel.BACK_ROW and row[5] == 0, "Gameplay switch above the page links, off by default: " + str(row))
	check(GameData.REMAKE_OPTIONS.has("esc_menu_rise") and "esc_menu_rise" in GameData.OPTIONS_APPLIED, "labelled and applied at once")
	var texts: Array = GameData.REMAKE_OPTIONS.get("esc_menu_rise", ["", ""])
	for key: String in texts:
		check(RemakeText.TEXTS.has(key) and (RemakeText.TEXTS[key] as Array).size() == 2 and not RemakeText.TEXTS[key].has(""), "RU/DE: " + key.left(40))
	GameData.options.esc_menu_rise = 0
	var sp := EscSignpost.new()
	sp.visible = false
	add_child(sp)
	await get_tree().process_frame
	check(sp._player != null and sp._player.has_animation("ei/uspecial02"), "the signpost has its rise clip")
	if sp._player == null: return finish()
	var clip := sp._player.get_animation("ei/uspecial02")
	check(clip.length > 0.2, "the rise lasts %.2f s" % clip.length)
	# Reference poses: the clip's first and last frames.
	sp._player.play("ei/uspecial02"); sp._player.seek(0.0, true)
	var first := pose(sp)
	sp._player.seek(clip.length, true)
	var last := pose(sp)
	check(not same(first, last), "the clip moves the post")
	var settled := await open(sp)
	check(same(settled, last), "default: the post is in place on opening, as in the original")
	sp._player.advance(0.05)
	check(same(pose(sp), last), "default: no rise follows")
	check(not sp._player.is_playing() or sp._player.current_animation_position >= clip.length - 0.001, "the rise clip is finished")
	GameData.options.esc_menu_rise = 1
	var rising := await open(sp)
	check(same(rising, first), "option on: the post starts below")
	sp._player.advance(clip.length * 0.5)
	var mid := pose(sp)
	check(not same(mid, first) and not same(mid, last), "option on: the post rises")
	sp._player.advance(clip.length)
	check(same(pose(sp), last), "option on: the rise ends in place")
	GameData.options.esc_menu_rise = 0
	check(same(await open(sp), last), "turning it off again opens in place")
	sp.free()
	finish()

func finish() -> void:
	print("ESC_MENU_RISE ", checks, " checks ", failures, " failures")
	get_tree().quit(1 if failures else 0)
