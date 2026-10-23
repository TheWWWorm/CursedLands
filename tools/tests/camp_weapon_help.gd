extends Node
## The camp hero panel's Attack, Defense and Damage rows carry the original's
## help ("string attack" / "attack_desc", "defense", "camp_damage"; hit test
## 624c70, shown by 5f16df like the armour rows).
var failures := 0

func check(ok: bool, label: String) -> void:
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

func _ready() -> void:
	GameData.options.merge({"autosave":0,"show_tutorial":0,"auto_graphics":0,"net_upnp":0,"net_lan":0,"net_directory":0},true)
	TutorialPanel.auto_show = false
	var s:=Session.new();add_child(s);var g:=Game.new();g.session=s;s.game=g;add_child(g)
	s.state.ensure_hero(0,s._hero_proto(0))
	await s.enter_zone("bz2g",1,false)
	var u: GameUnit=s.party_units(0)[0];g.selected.assign([u])
	g.hud._inventory.open(false)
	var camp: CampView=g.hud._inventory._camp
	camp.refresh(u)
	var helps := {}
	for row: Array in camp._hero_rows():
		if not (row[3] as Array).is_empty(): helps[String(row[3][0])] = String(row[3][1])
	for key in ["attack", "defense", "camp_damage", "hl_skull", "magic_skills"]:
		var title := CampView._str(key)
		check(helps.has(title) and helps[title].begins_with(CampView._str(key + "_desc")) and not CampView._str(key + "_desc").is_empty(),
			"%s row has the original's help (%s)" % [key, title])
	print("RESULT failures=", failures)
	get_tree().quit(1 if failures else 0)
