extends Node
## Every original natural-weapon model must select an available clip; the
## goblin's two authored weapon masks must never cross into each other.
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok: failures+=1; printerr("FAIL ",label)
func _ready() -> void:
	for p: Dictionary in GameData.db.table("monster_prototypes"):
		var kind:=int(p.get("weapon_type_id",-1))
		if kind<0 or kind>6: continue
		var m:=EIUnitModel.create({"prototype":p.name},true)
		if m==null: continue
		add_child(m)
		if not m.adb.is_empty():
			for variant in range(1,5):
				var clip:=m.action_clip("attack",variant)
				check(not clip.is_empty() and m.has_anim(clip),"available natural attack "+p.name)
				if String(p.base_race).to_lower().contains("goblin"):
					check(clip=="uattack02" if kind==3 else clip in ["uattack01","uattack03","uattack04"],"correct goblin weapon clip "+p.name+" "+clip)
		m.free()
	print("CREATURE_WEAPON_ANIMATIONS ",checks," checks ",failures," failures")
	TexUpscale.shutdown();get_tree().quit(1 if failures else 0)
