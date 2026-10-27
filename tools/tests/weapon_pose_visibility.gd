extends Node
## Native 5341a0/537cb0 hide equipped parts for an unarmed ADB clip.
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL ", label)

func held_meshes(m: EIUnitModel) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for n: Node in m.find_children("*", "MeshInstance3D", true, false):
		var part := String(n.get_parent().name)
		if part.begins_with("rh3_") or part.begins_with("lh3_bw") or part.begins_with("crbow") or part.begins_with("bw") or part in ["quiver", "arrows"]:
			out.append(n)
	return out

func shown(meshes: Array[MeshInstance3D], value: bool) -> bool:
	return not meshes.is_empty() and meshes.all(func(n: MeshInstance3D): return n.visible == value)

func _ready() -> void:
	GameData.options.merge({"auto_graphics":0,"gfx_smooth_characters":0}, true)
	for tmpl: String in ["unhuma", "unhufe", "unorma"]:
		for weapon: String in ["battle axe.adamantium", "stone dagger.bronze", "crossbow.wood", "long bow.wood"]:
			if tmpl == "unorma" and weapon == "crossbow.wood": continue # Original orc rig has no crossbow geometry.
			var record := {"template":tmpl, "weapons":PackedStringArray([weapon]), "armors":PackedStringArray()}
			var m := EIUnitModel.create(record)
			check(m != null, tmpl + " builds")
			if m == null: continue
			add_child(m)
			var meshes := held_meshes(m)
			var label := tmpl + " " + weapon
			check(not meshes.is_empty(), label + " has real equipment meshes")
			m.pose_state = EIUnitModel.ST_ATTACK; m.act("idle", 1, 0.0)
			check(shown(meshes, true), label + " armed idle shows the whole weapon")
			for speaking: bool in [true, false]:
				var clip := m.dialogue_clip(speaking, 1 if speaking else 2)
				check(not clip.is_empty(), label + " has native dialogue clip")
				m.play(clip, 0.0, true)
				check(shown(meshes, false), label + " dialogue hides every weapon part")
				m.act("attack", 1, 0.0)
				check(shown(meshes, true), label + " combat restores every weapon part")
			m.pose_state = EIUnitModel.ST_NEUTRAL; m.act("idle", 1, 0.0)
			print("WEAPON_POSE ", JSON.stringify({"template":tmpl,"weapon":weapon,"neutral":m._current,"meshes":meshes.size()}))
			check(shown(meshes, true), label + " armed village guard idle keeps its weapon")
			var preview := EIUnitModel.create(record, true)
			check(shown(held_meshes(preview), true), label + " inventory preview still shows equipped weapon")
			preview.free(); m.free()
	TexUpscale.shutdown()
	print("WEAPON_POSE_VISIBILITY ", checks, " checks ", failures, " failures")
	get_tree().quit(1 if failures else 0)
