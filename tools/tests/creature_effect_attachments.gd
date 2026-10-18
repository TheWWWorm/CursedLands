extends Node
## Audit every native monster rig for lost prefix-matched effect attachments.
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL ",label)

func _ready() -> void:
	var out := "user://creature-effect-attachments.json"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): out = arg.trim_prefix("--out=")
	var world := GameWorld.new(); world.process_mode = Node.PROCESS_MODE_DISABLED; add_child(world)
	var fx := ParticleFx.of(world); fx.set_process(false)
	var rigs := {}; var affected := []; var serial := 700000
	for proto: Dictionary in GameData.db.table("monster_prototypes"):
		var race := GameData.db.find("race_models",proto.base_race)
		var mask := String(race.get("mask",""))
		if mask.is_empty(): continue
		if not rigs.has(mask): rigs[mask] = []
		rigs[mask].append(String(proto.name))
	for mask: String in rigs:
		serial += 1
		var u := GameUnit.new()
		check(u.setup(world,{"prototype":rigs[mask][0],"nid":serial}),mask+" loads")
		world.add_child(u); u.pos=Vector2(20,20);u.resync_drawn();u.model.set_process(false)
		for sel: int in ParticleFx.BONES:
			var name: String = ParticleFx.BONES[sel]
			var exact := u.model.find_child(name,true,false)
			var expected = exact
			if expected == null:
				for ref: WeakRef in u.model.get_meta(EIFigureGeometry.PARTS,[]):
					var node = ref.get_ref()
					if is_instance_valid(node) and String(node.name).begins_with(name): expected=node;break
			var actual := fx._bone(u,name)
			check(actual==expected,mask+" resolves "+name)
			check(fx.unit_point(u,sel).is_finite(),mask+" finite attachment "+name)
			if exact==null and actual!=null:
				affected.append({"rig":mask,"selector":name,"part":String(actual.name),"variants":rigs[mask]})
			if expected==null: check(fx.bone_size(u,sel)==0.0,mask+" absent "+name+" has no fabricated hit radius")
			else: check(fx.bone_size(u,sel)>0.0,mask+" present "+name+" has a hit radius")
		u.free()
	FileAccess.open(out,FileAccess.WRITE).store_string(JSON.stringify({
		"checks":checks,"failures":failures,"rigs":rigs,"affected":affected},"\t"))
	print("CREATURE_EFFECT_ATTACHMENTS checks=",checks," failures=",failures," rigs=",rigs.size()," affected=",affected)
	world.free(); get_tree().quit(1 if failures else 0)
