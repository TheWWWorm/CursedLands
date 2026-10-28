extends Node
## Current authored part bounds must match before/after parenting and pose edits.
var checks := 0
var failures := 0
var native_us := 0
var script_us := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		if failures < 12: printerr("FAIL ",label)

func compare(model: Node3D, label: String) -> void:
	if model is EIUnitModel: model.flush_pending_pose()
	var start := Time.get_ticks_usec()
	var expected := EIFigureGeometry._of_script(model)
	script_us += Time.get_ticks_usec()-start; start=Time.get_ticks_usec()
	var actual := EIFigureGeometry.of(model)
	native_us += Time.get_ticks_usec()-start
	check(actual == expected,label+" exact current geometry")

func _ready() -> void:
	check(EIFigureGeometry._kernel != null,"native geometry available")
	if failures: get_tree().quit(1); return
	check(EIFigureGeometry._kernel.measure(null).is_empty(),"null model")
	var rng := RandomNumberGenerator.new(); rng.seed=91732
	for trial in 80:
		var model := Node3D.new()
		model.transform=Transform3D(Basis.from_euler(Vector3(.23,.56,.71)).scaled(Vector3(1.2,.7,2)),Vector3(5,17,-9))
		var refs: Array[WeakRef] = []
		var parent: Node3D = model
		for part in trial%17:
			var node := Node3D.new(); parent.add_child(node)
			node.transform=Transform3D(Basis.from_euler(Vector3(rng.randf(),rng.randf(),rng.randf())).scaled(Vector3(.7,1.1,1.3)),Vector3(rng.randf(),rng.randf(),rng.randf())*4)
			node.set_meta(EIFigureGeometry.META,{"centre":Vector3(.12,-.34,.56),"min":Vector3(-1,-2,-3),"max":Vector3(2,3,4)})
			refs.append(weakref(node)); parent=node
		model.set_meta(EIFigureGeometry.PARTS,refs)
		compare(model,"detached nested model "+str(trial))
		add_child(model); compare(model,"parented model "+str(trial))
		parent.position+=Vector3(.7,-.3,.2); compare(model,"same-frame part edit "+str(trial))
		if parent != model:
			parent.reparent(self); compare(model,"part moved outside model "+str(trial))
			parent.free(); compare(model,"freed weak part "+str(trial))
		model.free()
	var seen := {}
	for family: Dictionary in ArenaRules.FAMILIES:
		# Expansion forms are Lost in Astral models; they exist only with that campaign's data.
		if family.get("expansion", false) and GameData.campaign_id != CampaignProfile.ASTRAL: continue
		for prototype: String in family.forms:
			if seen.has(prototype): continue
			seen[prototype]=true
			var model:=EIUnitModel.create({"prototype":prototype})
			check(model!=null,"authored model "+prototype)
			if model == null: continue
			compare(model,"detached "+prototype);add_child(model)
			for pose in ["idle","walk","attack"]:
				model.act(pose,1,0.0);model.player.advance(.23)
				compare(model,prototype+" "+pose)
			model.free()
	print("FIGURE_GEOMETRY checks=",checks," failures=",failures," models=",seen.size()," native_us=",native_us," script_us=",script_us)
	get_tree().quit(1 if failures else 0)
