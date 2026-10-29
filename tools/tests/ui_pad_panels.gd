extends Node
## PadUI gives the pad to the topmost visible panel of the group "pad_panel".
## The load/save screen and the mod panel open over the main menu or the
## Escape signpost, which are such panels: unless they join the group, the
## D-pad keeps moving the menu underneath. Both take the key bridge (D-pad →
## arrows, A → Enter, B → Esc); the load screen names X as Delete and Y as
## Rename (F2), the mod panel handles the buttons itself.
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

func key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code; e.physical_keycode = code; e.pressed = true
	return e

func _ready() -> void:
	var pad := PadUI.new(); add_child(pad)
	var menu := Control.new(); menu.add_to_group("pad_panel"); add_child(menu)   # the main menu / Escape signpost
	check(pad.top_panel() == menu, "the menu takes the pad while nothing is above it")

	var load := LoadPanel.new(); add_child(load)
	load.open(false)
	check(load.is_in_group("pad_panel") and pad.top_panel() == load, "the load screen takes the pad over the menu")
	check(load.pad_targets().is_empty(), "the load screen navigates through the key bridge, not snap targets")
	var keys: Dictionary = load.pad_keys()
	check(int(keys.get("context", 0)) == KEY_DELETE and int(keys.get("pause", 0)) == KEY_F2, "X deletes and Y renames on the load screen")
	var a := SaveInfo.new(); a.slot = "pad_a"; a.name = "A"
	var b := SaveInfo.new(); b.slot = "pad_b"; b.name = "B"
	load.saves = [a, b]; load._select(0)
	load._unhandled_key_input(key(KEY_DOWN))
	check(load.sel == 1, "the bridge's Down arrow selects the next save")
	load._unhandled_key_input(key(KEY_UP))
	check(load.sel == 0, "the bridge's Up arrow selects the previous save")
	load._close()
	check(not load.visible and pad.top_panel() == menu, "closing the load screen returns the pad to the menu")

	var mods := ModPanel.new(); add_child(mods)
	mods.open()
	check(mods.is_in_group("pad_panel") and pad.top_panel() == mods, "the mod panel takes the pad over the menu")
	check(mods.pad_press("down", "down") and mods.visible, "the mod panel moves its own focus with the D-pad")
	check(mods.pad_press("cancel", "down") and not mods.visible, "B closes the mod panel")
	check(pad.top_panel() == menu, "closing the mod panel returns the pad to the menu")
	for i in 4: await get_tree().process_frame
	print("UI_PAD_PANELS ", checks, " checks ", failures, " failures")
	get_tree().quit(1 if failures else 0)
