extends Node
## #79/#84/#87: use the actual creation panel, serialized character and camp
## command path. This guards the reported outcomes, not merely option defaults.
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

func frames() -> void:
	for i in 4: await get_tree().process_frame

func _ready() -> void:
	GameData.options.merge({"auto_graphics":0,"show_tutorial":0,"pad_enabled":0,"item_icon_fit":1}, true)
	var panel := MpCharPanel.new(); add_child(panel); panel.open(false)
	await frames()
	var prototype := ""
	for face: String in panel.faces[0] + panel.faces[1]:
		if MpCharacter.hero_of(MpCharacter.create(face)).spells.size() > 1:
			prototype = face; break
	check(not prototype.is_empty(), "original multiplayer kit supplies multiple spell choices")
	if prototype.is_empty(): get_tree().quit(1); return
	var original := MpCharacter.create(prototype)
	var original_hero := MpCharacter.hero_of(original)
	original_hero.name = "Audit"
	original_hero.skills = {}; original_hero.perks = []
	var spells: Array = original_hero.spells.duplicate()
	var unusable := 0
	for spell: String in spells:
		panel.edit = original.duplicate(true)
		panel._set_state(MpCharPanel.CREATE)
		panel._next_from_create()
		check(panel.state == MpCharPanel.KIT, "creation opens the kit screen")
		var cell: Array = []
		for value: Array in panel._item_cells():
			if value[2] == "spell" and value[3] == spell: cell = value; break
		check(not cell.is_empty(), "authored spell has a selectable kit cell: " + spell)
		if cell.is_empty(): continue
		# Feed the same hit result as mouse/controller activation, without
		# bypassing the screen's selection or finish handlers.
		var hit := panel._hit((cell[1] as Rect2).get_center())
		panel._press(hit)
		check(panel.pick.spell == spell and panel._picked(cell), "clicked spell becomes the selected kit piece: " + spell)
		if not MpCharacter.spell_usable(panel._hero(), spell):
			unusable += 1
			for lang: String in ["en", "ru", "de"]:
				RemakeText.lang = lang
				check(not Spells.unmet(panel._hero(), MpCharacter.stamina_of(panel._hero()), spell).is_empty(),
					"unusable spell explains requirements in " + lang)
		panel._press(["next"])
		check(panel.state == MpCharPanel.SEL, "finish returns to character selection")
		var file := String(panel.chars[panel.sel].file)
		var saved := MpCharacter.load_file(file)
		check(MpCharacter.hero_of(saved).spells == [spell], "chosen spell survives disk reload: " + spell)
		check(MpCharacter.hero_of(MpCharacter.accept(saved)).spells == [spell], "host admission retains chosen spell: " + spell)
	check(unusable > 0, "fixture includes a spell the new hero cannot cast yet")
	panel._press(["view"]); await frames()
	check(panel.state == MpCharPanel.VIEW and panel._camp != null, "View opens the actual camp for the saved character")
	if panel._camp == null: get_tree().quit(1); return
	var camp: CampView = panel._camp
	var actor: GameUnit = panel._camp_host.unit
	var hero: Dictionary = actor.get_meta("hero")
	check(not camp._can_step_hero(), "single-character camp has no hero-cycle arrows")
	hero.exp = 1000000.0; hero.exp_total = 1000000.0; hero.skills = {}
	camp.set_mode("spells")
	GameData.options.skill_reset_button = 0
	var command := {"t":"train", "unit":actor.uid, "stat":"melee"}
	var cash := float(hero.exp)
	camp._train(command)
	check(Skills.level(hero,"melee") == 0 and hero.exp == cash, "pending training leaves saved skill and XP untouched")
	check(Skills.level(camp._training_hero(),"melee") == 1 and camp._pending_cost() > 0, "pending preview shows the next skill and its price")
	camp._on_cancel()
	check(camp._pending.is_empty() and Skills.level(hero,"melee") == 0 and hero.exp == cash, "Cancel discards training without charging XP")
	camp._train(command)
	var cost := camp._pending_cost()
	camp._on_yes()
	check(Skills.level(hero,"melee") == 1 and hero.exp == cash - cost and camp._pending.is_empty(), "Accept applies exactly one skill and its displayed price")
	camp._on_yes()
	check(Skills.level(hero,"melee") == 1 and hero.exp == cash - cost, "repeated Accept cannot buy again")
	camp._train(command); camp.set_mode("weapons")
	check(camp._pending.is_empty() and Skills.level(hero,"melee") == 1, "leaving Skills discards unaccepted changes")
	camp.set_mode("spells"); GameData.options.skill_reset_button = 1
	camp._train(command)
	check(Skills.level(hero,"melee") == 2 and camp._pending.is_empty(), "default training mode applies the command immediately")
	for code: String in Perks.available(hero):
		check(bool(Perks.get_perk(code).get("active",true)), "inactive ability is never offered: " + code)
	var file := panel._edit_file
	panel._close_camp(); await frames()
	check(Skills.level(MpCharacter.hero_of(MpCharacter.load_file(file)),"melee") == 2,
		"closing View saves accepted training to the character")
	panel._close(false); panel.queue_free(); await frames()
	TexUpscale.shutdown()
	print("RECENT_CHARACTER_CONTROLS ", checks, " checks ", failures, " failures")
	get_tree().quit(1 if failures else 0)
