extends Node
## The solo campaign's simulation worker is a headless authority whose
## world presents nothing: its units get their figures, parts, geometry,
## meshes and clip libraries, but their materials no longer compose the
## body and secondary atlases nobody draws (a third of the worker's spawn
## time). A presenting world's units and models made directly keep them,
## and the wound overlay skips the atlas-less materials.
var checks := 0
var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("FAIL ", label)

func materials(m: EIUnitModel) -> Array:
	var out := []
	for mi in m.find_children("*", "MeshInstance3D", true, false):
		var mat: Material = (mi as MeshInstance3D).material_override
		if mat != null and not mat in out:
			out.append(mat)
	return out

func albedo(mat: Material) -> Texture2D:
	return mat.get("albedo_texture") if mat is ShaderMaterial or mat is BaseMaterial3D else null

func records() -> Array:
	var z := CampaignMap.load_from(GameData.texts).zone("gz1g")
	var mob := EIMob.load_bytes(GameData.read_file("maps/%s.mob" % String(z.get("mob", z.get("mpr", "")))))
	var out := []
	var seen := {}
	for o: Dictionary in mob.objects:
		if o.kind != "UNIT" or String(o.template).is_empty() or seen.has(o.template):
			continue
		seen[o.template] = true
		var r: Dictionary = o.duplicate(true)
		r.position = Vector3(5.0 + 3.0 * out.size(), 5.0, 0.0)
		out.append(r)
		if out.size() == 12:
			break
	return out

func _ready() -> void:
	var rows := records()
	check(rows.size() >= 6, "fixture records of distinct templates (%d)" % rows.size())
	var caches := [EIUnitModel._textures.size(), EIUnitModel._surface_textures.size()]
	# 1. The headless authority's units: no atlases, everything else.
	var w := GameWorld.new()
	w.zone = {"type": "game"}
	w.presentation = false
	add_child(w)
	var units: Array[GameUnit] = []
	for r in rows:
		var u := w.spawn_unit(r.duplicate(true))
		if u: units.append(u)
	check(units.size() == rows.size(), "the authority spawns every record (%d)" % units.size())
	# The detailed heads keep their authored face texture (not composed).
	var composed := EIUnitModel._textures.values() + EIUnitModel._surface_textures.values()
	var bare := true
	var complete := true
	for u in units:
		var mats := materials(u.model)
		if mats.is_empty():
			complete = false
		for mat in mats:
			if albedo(mat) in composed or (mat is ShaderMaterial and mat.get_shader_parameter("surface_tex") in composed):
				bare = false
				printerr("composed atlas on ", u.model.template)
		if u.model.player == null or not u.model.player.has_animation_library("ei") or u.figure_radius <= 0.0 \
				or u.model.get_meta("layers", []).size() != 2 or u.model.find_children("*", "MeshInstance3D", true, false).is_empty() \
				or u.model.get_meta(EIFigureGeometry.PARTS, []).is_empty():
			complete = false
	check(bare, "an authority unit's materials carry no composed atlas")
	check(complete, "an authority unit keeps its meshes, parts, geometry, layers and clip library")
	check([EIUnitModel._textures.size(), EIUnitModel._surface_textures.size()] == caches,
		"spawning them composed nothing (%s)" % [[EIUnitModel._textures.size(), EIUnitModel._surface_textures.size()]])
	# The wound overlay skips materials without an atlas.
	UnitWounds.apply(units[0].model, PackedByteArray([3, 2, 0, 0, 0, 0]), int(units[0].race.get("type_id", 0)) == 0x32)
	var still_bare := true
	for mat in materials(units[0].model):
		if albedo(mat) in composed or mat.has_meta("wound_base"):
			still_bare = false
	check(still_bare and [EIUnitModel._textures.size(), EIUnitModel._surface_textures.size()] == caches,
		"wounds on an atlas-less unit compose nothing")
	# 2. A presenting world (as the client, headless here) composes them.
	var p := GameWorld.new()
	p.zone = {"type": "game"}
	p.presentation = true
	add_child(p)
	var shown := p.spawn_unit(rows[0].duplicate(true))
	var shown_composed := false
	for mat in materials(shown.model):
		if albedo(mat) in EIUnitModel._textures.values():
			shown_composed = true
	check(shown != null and shown_composed, "a presenting world's unit has its composed atlas")
	check(EIUnitModel._textures.size() > caches[0] and EIUnitModel._surface_textures.size() > caches[1],
		"the presenting world composed into the caches")
	# The same record's authority unit still has none of the atlases now composed.
	composed = EIUnitModel._textures.values() + EIUnitModel._surface_textures.values()
	var authority_bare := not composed.is_empty()
	for mat in materials(units[0].model):
		if albedo(mat) in composed or (mat is ShaderMaterial and mat.get_shader_parameter("surface_tex") in composed):
			authority_bare = false
	check(authority_bare, "the authority's unit of the same record carries none of the composed atlases (%d exist)" % composed.size())
	# 3. A model made directly (previews, the encyclopedia) composes too.
	var direct := EIUnitModel.create(rows[1].duplicate(true))
	add_child(direct)
	var direct_composed := false
	for mat in materials(direct):
		if albedo(mat) in EIUnitModel._textures.values():
			direct_composed = true
	check(direct != null and direct_composed, "a model made directly has its atlas")
	# 4. Both worlds' models of one record share the figure: same parts and
	# clip library.
	var a := units[0].model
	var b := shown.model
	check(a.find_children("*", "MeshInstance3D", true, false).size() == b.find_children("*", "MeshInstance3D", true, false).size() \
			and a.player.get_animation_library("ei") == b.player.get_animation_library("ei") and a.get_meta("layers") == b.get_meta("layers"),
		"the authority's and the presenting world's models share parts, library and layers")
	print("AUTHORITY_UNIT_TEXTURES ", checks, " checks ", failures.size(), " failures")
	get_tree().quit(1 if not failures.is_empty() else 0)
