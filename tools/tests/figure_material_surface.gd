extends Node
## Object surface families and figure material records reach both the raster
## material and the path-traced scene, for the base game and Lost in Astral.
const Scene = preload("res://src/game/fx/water_raytrace_scene.gd")
var checks := 0
var failures := 0
## Names in the family table that only the expansion archive contains.
const ASTRAL_ONLY := ["hadoganwall02", "crypt01", "almaz00", "goldpile00", "goldpile01", "goldchest00",
	"jskeleton00", "runnerstent01", "runnerstent02", "runnerstent03", "tent02", "tent04", "carpet01", "carpet02",
	"carpet03", "redcarpet00", "jigranwall00", "jigranwall01", "jigranwall02", "jigranwall03", "jigranwall04",
	"jigrantower00", "jigrantower01", "jigrantower02", "jigrantower03", "jigrantower04", "jyardwall00", "jcrypt00",
	"jlion00", "jkstatue", "teleport01", "teleport02", "teleport03", "jigranhouse00", "jigranhouse00b",
	"jigranhouse01", "jigranhouse01b", "jigranhouse02", "jigranhouse02b", "jigranhousebig00", "jigranhousebig01",
	"jigranbridge00", "jigranbridge01", "jigranshipyard00", "jigranshipyard01", "jhhouse00", "jdekhouse00",
	"jvhouse00", "jvhouse01", "jhwall00", "jhgates00", "jigranprops00", "jigranprops01", "jfield", "jhvivary00"]


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)


func profile_of(node: Node3D) -> Array:
	var found := []
	for mesh: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		var material := mesh.material_override as ShaderMaterial
		if material:
			found.append([mesh.get_parent().name, material.get_shader_parameter("surface_profile"), material])
	return found


func placed(template: String, texture: String) -> Node3D:
	var obj := EIFigure.instantiate(template, texture, Vector3(0.5, 0.5, 0.5), PackedStringArray(), false, true)
	check(obj != null, "original figure loads: " + template + "/" + texture)
	if obj:
		add_child(obj)
	return obj


func traced(obj: Node3D) -> Array:
	var scene := Scene.new()
	scene.path_materials = true
	scene.lighting_camera_mask = 1
	for mesh: MeshInstance3D in obj.find_children("*", "MeshInstance3D", true, false):
		scene._pack_mesh(mesh, mesh.mesh)
	return scene.geometries


func test_table() -> void:
	var astral := GameData.campaign_id == CampaignProfile.ASTRAL
	var missing := []
	for name: String in SurfaceMaterials.OBJECT_FAMILIES:
		if not GameData.textures.has(name + ".mmp"):
			missing.append(name)
	check(missing.is_empty() if astral else missing.all(func(n: String) -> bool: return n in ASTRAL_ONLY),
		"every listed family name is an original atlas of this edition: " + str(missing))
	if not astral:
		check(missing.size() == ASTRAL_ONLY.size(), "the expansion-only names are exactly those absent from the base archive")
	# Verified atlases keep their established profiles.
	check(SurfaceMaterials.object_profile("stone03") == Vector4(0.20, 0.84, 0.0, 0.70), "stone atlases keep full relief")
	check(SurfaceMaterials.object_profile("columnruins01.mmp", 22) == Vector4(0.20, 0.84, 0.0, 0.70), "ruin columns keep full relief")
	check(SurfaceMaterials.object_profile("barrel00", 18) == Vector4(0.16, 0.86, 0.0, 0.45), "plank atlases keep wood relief")
	# Masonry and houses were dull before: a wall now has stone roughness and relief.
	var wall := SurfaceMaterials.object_profile("hadoganwall00", 22)
	check(is_equal_approx(wall.y, 0.84) and wall.z == 0.0 and wall.w > 0.0, "Hadagan wall is masonry with relief: " + str(wall))
	check(SurfaceMaterials.object_profile("kanianhouse00", 18).w > 0.0, "Kanian timber house gains wood relief")
	check(SurfaceMaterials.object_profile("hadoganhouse00", 22) == SurfaceMaterials.PLASTER, "plaster houses use the lighter mixed profile")
	# Figure records: metal always wins, stone/wood refine unlisted atlases without relief.
	check(SurfaceMaterials.object_profile("torch00", 19).z >= 0.8, "iron brazier is metal")
	check(SurfaceMaterials.object_profile("torchbase00", 19).z >= 0.8 and SurfaceMaterials.object_profile("torchbase00", 18).z == 0.0,
		"a metal part inside a timber atlas stays metal while its wooden parts stay dielectric")
	check(SurfaceMaterials.object_profile("unlisted_atlas", 22) == Vector4(0.20, 0.84, 0.0, 0.0), "unlisted stone record: rough stone, no relief")
	check(SurfaceMaterials.object_profile("unlisted_atlas", 18) == Vector4(0.16, 0.86, 0.0, 0.0), "unlisted wood record: wood roughness, no relief")
	check(SurfaceMaterials.object_profile("unlisted_atlas", 25).z >= 0.8, "second metal record is metal")
	check(SurfaceMaterials.object_profile("unlisted_atlas", 17) == SurfaceMaterials.LEATHER, "leather record")
	for id in [0, 20, 21, 23, 24, 11]:
		check(SurfaceMaterials.object_profile("unlisted_atlas", id) == Vector4(0.04, 0.96, 0.0, 0.0), "record %d has no surface semantics" % id)
	# Listed cloth, clay and bone props override misleading stone/wood records.
	check(SurfaceMaterials.object_profile("runnerstent00", 22) == SurfaceMaterials.CLOTH, "tent marked stone stays cloth")
	check(SurfaceMaterials.object_profile("jug00", 18) == SurfaceMaterials.CLAY, "clay jug marked wood")
	check(SurfaceMaterials.object_profile("skeleton00", 18) == SurfaceMaterials.BONE, "skeleton marked wood is bone")
	check(SurfaceMaterials.object_profile("goldpile00", 21) == SurfaceMaterials.GOLD, "gold pile marked skin is gold")
	check(SurfaceMaterials.object_profile("jigranwall00", 21) == SurfaceMaterials.MASONRY, "Jigran wall marked skin is masonry")
	check(SurfaceMaterials.object_profile("ambush00", 22).w == 0.0 and SurfaceMaterials.object_profile("bushset01", 0).w == 0.0,
		"families match whole names, never substrings")


func test_placed_objects() -> void:
	GameData.options.gfx_materials = 1
	EIFigure.clear_cache()
	var wall := placed("stwa10", "hadoganwall00")
	if wall:
		var parts := profile_of(wall)
		check(not parts.is_empty() and parts.all(func(p: Array) -> bool: return is_equal_approx(p[1].y, 0.84) and p[1].w > 0.0),
			"placed Hadagan wall parts carry the masonry profile: " + str(parts.map(func(p: Array): return [p[0], p[1]])))
		var geometries := traced(wall)
		check(not geometries.is_empty() and geometries.all(func(g: Dictionary) -> bool:
			return g.surface == Vector3(0.84, 0.0, 0.5) and g.relief > 0.0), "PT packs the same wall roughness and relief")
		wall.free()
	var torch := placed("stto2", "torch00")
	if torch:
		var parts := profile_of(torch)
		check(parts.any(func(p: Array) -> bool: return p[1].z >= 0.8), "placed brazier has a metal part: " + str(parts.map(func(p: Array): return [p[0], p[1]])))
		var geometries := traced(torch)
		check(geometries.any(func(g: Dictionary) -> bool: return g.surface.y >= 0.8), "PT packs the brazier metalness")
		torch.free()
	var tent := placed("stbuho53", "runnerstent00")
	if tent:
		check(profile_of(tent).all(func(p: Array) -> bool: return p[1].z == 0.0 and p[1].w == 0.0), "placed tent stays dull cloth")
		check(traced(tent).all(func(g: Dictionary) -> bool: return g.surface == Vector3(0.96, 0.0, 0.5) and g.relief == 0.0), "PT keeps the tent dull")
		tent.free()
	var chest := EIFigure.world_material_for("hadoganchest00", 18) as ShaderMaterial
	check(chest.get_shader_parameter("surface_tex") != null, "authored chest mask is retained")
	var barrel := EIFigure.world_material_for("barrel00", 18) as ShaderMaterial
	check(barrel.get_shader_parameter("surface_tex") == null and barrel.get_shader_parameter("surface_profile") == Vector4(0.16, 0.86, 0.0, 0.45),
		"plank atlas keeps its profile without a mask")
	# Surface materials off restores rough dielectrics in PT, as in raster.
	var stone := EIFigure.world_material_for("stone03", 22)
	check(Scene.surface_profile(stone) == Vector3(0.84, 0.0, 0.5), "PT reads the stone profile with Surface materials on")
	GameData.options.gfx_materials = 0
	check(Scene.surface_profile(stone) == Vector3(1.0, 0.0, 0.5), "PT ignores profiles with Surface materials off")
	GameData.options.gfx_materials = 1
	var tree := EIFigure.foliage_material_for("tree02", true, false, 18)
	check(Scene.surface_profile(tree) == Vector3(0.86, 0.0, 0.5), "foliage traces with its raster bark roughness")
	check(Scene.surface_profile(EIFigure.material_for("")) == Vector3(1.0, 0.0, 0.5), "plain materials stay rough dielectrics")


func mask_agreement(a: Image, b: Image, channel: int) -> float:
	var same := 0
	var total := a.get_width() * a.get_height()
	for y in a.get_height():
		for x in a.get_width():
			if (a.get_pixel(x, y)[channel] > 0.5) == (b.get_pixel(x, y)[channel] > 0.5):
				same += 1
	return float(same) / float(total)


func test_astral_foliage() -> void:
	var reference := SurfaceMaterials.foliage_mask("tree02")
	check(reference != null, "base tree02 mask is available in the expansion")
	for name in ["tree01", "tree05", "tree06"]:
		var mask := SurfaceMaterials.foliage_mask(name)
		check(mask != null, "autumn %s receives a foliage mask" % name)
		if mask == null or reference == null:
			continue
		var image := mask.get_image()
		var ref := reference.get_image()
		check(image.get_size() == ref.get_size(), "%s mask matches the donor size" % name)
		if image.get_size() != ref.get_size():
			continue
		var leaves := mask_agreement(image, ref, 0)
		var bark := mask_agreement(image, ref, 1)
		check(leaves > 0.98 and bark > 0.98, "%s leaf/bark classification follows the green original: %.4f / %.4f" % [name, leaves, bark])
		var leaf_pixels := 0
		for y in range(0, image.get_height(), 4):
			for x in range(0, image.get_width(), 4):
				if image.get_pixel(x, y).r > 0.5:
					leaf_pixels += 1
		check(leaf_pixels > 1000, "%s has translucent leaves: %d sampled" % [name, leaf_pixels])
		var material := EIFigure.foliage_material_for(name, true, false, 18) as ShaderMaterial
		check(material.get_shader_parameter("foliage_mask") == mask, "%s foliage material binds the mask" % name)
	var autumn := placed("nafltr21", "tree01")
	if autumn:
		check(traced(autumn).any(func(g: Dictionary) -> bool: return g.foliage_layer >= 0), "PT collects the autumn tree mask layer")
		autumn.free()
	var gold := placed("goldpile00", "goldpile00")
	if gold:
		check(traced(gold).all(func(g: Dictionary) -> bool: return g.surface.y >= 0.8), "placed gold pile traces as metal")
		gold.free()


func _ready() -> void:
	GameData.options.gfx_materials = 1
	GameData.options.gfx_foliage_light = 1
	test_table()
	test_placed_objects()
	if GameData.campaign_id == CampaignProfile.ASTRAL:
		test_astral_foliage()
	else:
		check(SurfaceMaterials.foliage_mask("tree01") == null, "the base archive has no autumn trees")
	print("FIGURE_MATERIAL_SURFACE_CAMPAIGN ", GameData.campaign_id)
	print("FIGURE_MATERIAL_SURFACE ", checks, " checks ", failures, " failures")
	TexUpscale.shutdown()
	get_tree().quit(1 if failures else 0)
