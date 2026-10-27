extends Node
## The original still reads figure parts written before the "FIG" format
## (4f7480 -> 4f87d0). The early ogre (unmoog.mod) uses it; its hips carry a
## skull on the belt, which the remake gives the shipped ogres.
var checks := 0
var failures := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL ", message)

func package(name: String) -> EIResArchive:
	return EIResArchive.from_bytes(GameData.read_figure(name + ".mod"))

func counts(f: Dictionary) -> Array:
	return [f.vblocks, f.nblocks, f.uvs, f.indices, f.comps]

func uv_points(f: Dictionary) -> PackedVector2Array:
	var a := (f.data as PackedByteArray).slice(f.uv_off, f.uv_off + f.uvs * 8).to_float32_array()
	var out := PackedVector2Array()
	for i in range(0, a.size(), 2): out.append(Vector2(a[i], a[i + 1]))
	return out

func painted_skull(texture: String, points: PackedVector2Array) -> bool:
	var img := GameData.load_image(texture)
	if img == null: return false
	img.decompress()
	var values: Array[float] = []
	for p in points: values.append(img.get_pixelv(Vector2i(p * Vector2(img.get_size() - Vector2i.ONE))).get_luminance())
	var mean: float = values.reduce(func(a: float, b: float) -> float: return a + b, 0.0) / values.size()
	var spread: float = sqrt(values.reduce(func(a: float, b: float) -> float: return a + (b - mean) * (b - mean), 0.0) / values.size())
	print("Skull paint %s mean=%.3f spread=%.3f" % [texture, mean, spread])
	return mean > 0.6 and spread > 0.15

func _ready() -> void:
	check(GameData.has_figure("unmoog.mod") and GameData.has_figure("unmoog1.mod") and GameData.has_figure("unmoog2.mod"), "original ogre packages exist")
	var old := package("unmoog")
	var shipped := package("unmoog1")
	check(old != null and shipped != null, "ogre packages open")
	if old == null or shipped == null: return finish()
	var compared := 0
	for entry: String in old.entries:
		var raw := old.read(entry)
		if entry == "unmoog" or raw.slice(0, 3).get_string_from_ascii() == "FIG":
			continue
		var fig := EIFigure.legacy_fig(raw)
		check(not fig.is_empty(), "legacy part converts: " + entry)
		if entry != "hp" and shipped.has(entry):
			# The shipped model re-saved the same parts as FIG8; only the
			# normals were re-normalised (float rounding).
			var a := EIFigure._parse_fig(fig)
			var b := EIFigure._parse_fig(shipped.read(entry))
			var n_end: int = a.n_off + a.nblocks * 64
			var same: bool = fig.size() == (b.data as PackedByteArray).size() and fig.slice(0, a.n_off) == b.data.slice(0, a.n_off) \
				and fig.slice(n_end) == b.data.slice(n_end)
			var na := fig.slice(a.n_off, n_end).to_float32_array()
			var nb := (b.data as PackedByteArray).slice(a.n_off, n_end).to_float32_array()
			var worst := 0.0
			for i in na.size(): worst = maxf(worst, absf(na[i] - nb[i]))
			check(same and na.size() == nb.size() and worst < 1e-6, "legacy " + entry + " equals the shipped FIG8 part (normals within " + str(worst) + ")")
			compared += 1
	check(compared >= 9, "the unchanged ogre parts were compared: %d" % compared)
	var hp := EIFigure._parse_fig(old.read("hp"))
	check(not hp.is_empty() and counts(hp) == [19, 19, 88, 426, 98], "early hips parse with the belt skull: " + str(counts(hp) if not hp.is_empty() else []))
	var plain := EIFigure._parse_fig(shipped.read("hp"))
	check(counts(plain) == [11, 11, 49, 240, 54], "shipped hips have no skull")
	check(hp.material == plain.material and hp.texture_group == plain.texture_group, "the early hips use the shipped ogre texture")
	# Every UV stays inside the shared skin.
	var uv := (hp.data as PackedByteArray).slice(hp.uv_off, hp.uv_off + hp.uvs * 8).to_float32_array()
	check(uv.size() == 176 and Array(uv).all(func(v: float) -> bool: return v >= -0.01 and v <= 1.01), "skull UVs lie on the skin")
	# Damaged or foreign data is rejected instead of misread.
	var bad := old.read("hp")
	check(EIFigure.legacy_fig(bad.slice(0, bad.size() - 2)).is_empty() and EIFigure._parse_fig(bad.slice(0, 300)).is_empty(), "truncated legacy parts are rejected")
	bad.append(0)
	check(EIFigure.legacy_fig(bad).is_empty(), "trailing bytes are rejected")
	check(EIFigure._parse_fig(PackedByteArray([1, 2, 3, 4])).is_empty(), "short data is rejected")
	# The skull's own UVs must land on a painted skull: bright bone with dark
	# sockets on the Gipat skins, plain hide on the Hadagan one.
	var known := uv_points(plain)
	var skull := PackedVector2Array()
	for p: Vector2 in uv_points(hp):
		if p.x < 0.2 and p.y < 0.5 and not Array(known).any(func(k: Vector2) -> bool: return k.distance_to(p) < 0.002): skull.append(p)
	check(skull.size() >= 20, "the belt skull has its own UVs: %d" % skull.size())
	for race: Dictionary in GameData.db.table("race_models"):
		var mask := String(race.get("mask", "")).to_lower()
		if mask not in ["unmoog1", "unmoog2"]: continue
		for texture: String in race.get("textures", []):
			var painted := painted_skull(texture.to_lower(), skull)
			check(painted == EIFigure.DETAILED_PARTS.has(mask), "%s skin %s %s a painted skull" % [mask, texture, "has" if painted else "lacks"])
	# No map dresses a Gipat-rig ogre in the Hadagan skin.
	var gipat := {}
	for p: Dictionary in GameData.db.table("monster_prototypes"):
		if String(p.get("base_race", "")) == "Ogre": gipat[String(p.name).to_lower()] = true
	var placed := 0
	for file: String in GameFiles.files(GameData.root.path_join("maps")):
		if not file.to_lower().ends_with(".mob"): continue
		for o: Dictionary in EIMob.load_bytes(GameData.read_file("maps/" + file.get_file())).objects:
			if gipat.has(String(o.get("prototype", "")).to_lower()) or String(o.get("template", "")).to_lower() == "unmoog1":
				placed += 1
				check(String(o.get("texture", "")).to_lower() in ["", "ogre00", "ogre01"], "placed Gipat ogre uses a skull skin: %s %s" % [file.get_file(), o.get("texture", "")])
	check(placed > 0, "maps place Gipat ogres: %d" % placed)
	for name: String in ["unmoog1", "unmoog2"]:
		var model := EIFigure.get_model(name)
		var parts: Dictionary = model.get("parts", {})
		var swapped := name == "unmoog1"
		check(parts.has("hp") and counts(parts.hp) == ([19, 19, 88, 426, 98] if swapped else [11, 11, 49, 240, 54]),
			name + (" uses the skull-belt hips" if swapped else " keeps its own hips"))
		var original := package(name)
		var others := 0
		for part: String in parts:
			if (part != "hp" or not swapped) and (parts[part].data as PackedByteArray) == original.read(part): others += 1
		check(others == parts.size() - int(swapped), name + " keeps every other shipped part")
		check((model.bones as Dictionary).has("hp") and (model.links as Array).any(func(l: Array) -> bool: return l[0] == "hp"), name + " keeps its hip bone and link")
		var mesh := EIFigure.build_mesh(parts.hp, Vector3(0.5, 0.5, 0.5))
		check(mesh != null and mesh.get_surface_count() > 0 and mesh.get_aabb().size.length() > 0.1, name + " hips build a mesh")
	# The early ogre itself loads (its cut-content page shows it): every part,
	# and six-variant bone offsets expanded to the shipped ogre's eight.
	var early := EIFigure.get_model("unmoog")
	var gipat_model := EIFigure.get_model("unmoog1")
	# Linked parts drive the figure; the early package names its right limbs
	# rh01/rl01 and also keeps unlinked spare copies.
	var linked: Array = (early.get("links", []) as Array).map(func(l: Array) -> String: return l[0])
	var shipped_names := linked.map(func(n: String) -> String: return n.replace("01", "1").replace("02", "2").replace("03", "3"))
	var shipped_linked: Array = (gipat_model.links as Array).map(func(l: Array) -> String: return l[0])
	check(linked.size() == 16 and shipped_names == shipped_linked and linked.all(func(n: String) -> bool: return early.parts.has(n)),
		"the early ogre's linked parts match the shipped skeleton: " + str(linked))
	var bones_equal := true
	for i in linked.size():
		var b: PackedFloat32Array = early.bones.get(linked[i], PackedFloat32Array())
		bones_equal = bones_equal and b.size() == 24 and b == gipat_model.bones.get(shipped_names[i], PackedFloat32Array())
	check(bones_equal, "early ogre bones expand to the shipped eight-variant offsets")
	check(EIFigure.bone_pos(early.bones.hd, Vector3(0.3, 0.6, 0.9)) == EIFigure.bone_pos(gipat_model.bones.hd, Vector3(0.3, 0.6, 0.9)), "blended bone offsets match")
	check(not WikiCut.FIGURES.unmoog.text.contains("cannot"), "the cut-content text no longer calls the early ogre unreadable")
	check(String(WikiCut.FIGURES.unmoog.get("texture", "")) in ["ogre00", "ogre01"] and painted_skull(WikiCut.FIGURES.unmoog.texture, skull),
		"the early ogre's preview uses a Gipath skin with its skull")
	var cut := WikiCut.new()
	var page := cut.page({"kind": "cut_figure", "value": "unmoog"})
	check(page.preview.get("appearance", {}).get("texture", "") == WikiCut.FIGURES.unmoog.texture and page.preview.appearance.template == "unmoog",
		"the cut-content page previews the textured early ogre")
	finish()

func finish() -> void:
	print("LEGACY_FIGURE ", checks, " checks ", failures, " failures")
	get_tree().quit(1 if failures else 0)
