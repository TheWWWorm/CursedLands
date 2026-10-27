extends Node
## Every option row is shown on its page: no two options share a row, every
## row is among the 14 the panel draws, and no page link (« back, section,
## Buttons…, Original look …) replaces it. skill_reset_button sat on Interface
## row 13, under the page's « link, and could not be changed in the menu.
var checks := 0
var failures := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL ", message)

func _ready() -> void:
	var pages := {}
	for o: Array in GameData.OPTIONS:
		if int(o[3]) < 0: continue   # rows without a page (vendor upscalers, set elsewhere)
		# Deliberately hidden: the renderer choice where only one renderer
		# exists, and the RT/PT page, which shows presets unless tuning is on.
		if o[0] == "renderer" and not RendererChoice.available(): continue
		if int(o[3]) == OptionsPanel.SCENE_RT_GROUP and not GameData.PathTraceSettings.tuning_enabled(): continue
		pages.get_or_add(int(o[3]), []).append(o)
	var options := OptionsPanel.new()
	add_child(options)
	options.open()
	for group: int in pages:
		var used := {}
		for o: Array in pages[group]:
			var at := "%s (page %s, row %d)" % [o[0], GameData.OPTION_GROUPS[group], o[4]]
			check(not used.has(int(o[4])), at + " shares its row with " + str(used.get(int(o[4]), "")))
			used[int(o[4])] = o[0]
			check(int(o[4]) >= 0 and int(o[4]) <= OptionsPanel.BACK_ROW, at + " is one of the drawn rows")
		for a: Array in EIKeymap.ACTIONS:
			if int(a[2]) == group:
				check(not used.has(int(a[3])), "%s shares %s row %d with key %s" % [used.get(int(a[3]), ""), GameData.OPTION_GROUPS[group], a[3], a[1]])
		options._show_group(group)
		for o: Array in pages[group]:
			var row: Dictionary = options._rows.get(int(o[4]), {})
			check(row.get("name", "") == o[0] and row.get("kind", "") != "link",
				"%s is shown on page %s row %d, found %s" % [o[0], GameData.OPTION_GROUPS[group], o[4], row.get("label", row.get("name", "nothing"))])
	# The reported option: reachable, and its switch works from the menu.
	var reset: Array = GameData.OPTIONS.filter(func(o: Array) -> bool: return o[0] == "skill_reset_button")[0]
	options._show_group(int(reset[3]))
	var keep: int = int(options._values.get("skill_reset_button", 1))
	options._sel = int(reset[4])
	check(options._rows.get(options._sel, {}).get("name", "") == "skill_reset_button", "skill reset button row can be selected")
	options._values.skill_reset_button = 1 - keep
	check(options._switch_text(options._rows[int(reset[4])]) != "", "skill reset button shows its switch")
	options._values.skill_reset_button = keep
	options.free()
	print("OPTIONS_ROWS_REACHABLE ", checks, " checks ", failures, " failures")
	get_tree().quit(1 if failures else 0)
