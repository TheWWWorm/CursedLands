extends Node
## Placed LIGHT records (.mob 0xAA01) become world point lights, as the
## original's map loader creates them (481f00 -> 46d960 / 46dbf0 / 46dd70).
## The main menu's signpost is lit by two of them.
var checks := 0
var failures := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL ", message)

func frames(count := 4) -> void:
	for i in count: await get_tree().process_frame

func _ready() -> void:
	var menu := EIMob.load_bytes(GameData.read_file("maps/zonemainmenunew.mob"))
	check(menu.lights.size() == 6, "the menu map has six LIGHT records")
	var post := Vector3.INF
	for o: Dictionary in menu.objects:
		if o.get("template", "") == "unmoco2": post = o.position
	check(post != Vector3.INF, "the menu map places the signpost")
	var white := menu.lights.filter(func(l: Dictionary) -> bool: return l.color == Color.WHITE)
	check(white.size() == 2, "two white lights")
	for l: Dictionary in white:
		check(Vector2(l.position.x, l.position.y).distance_to(Vector2(post.x, post.y)) < 0.5, "white light stands at the signpost")
	var radii := white.map(func(l: Dictionary) -> float: return l.radius)
	radii.sort()
	check(radii == [5.0, 8.5], "signpost light radii 5 and 8.5 m: " + str(radii))
	for l: Dictionary in menu.lights:
		check(l.radius > 0.0 and l.flag == 1 and l.name.begins_with("Light-") and l.extra == "none" and l.id > 0, "record fields are read: " + str(l))
	# Recorded per-map totals from the installed archives.
	for map: String in ["zone10", "zone17", "zone15", "bz7g"]:
		var mob := EIMob.load_bytes(GameData.read_file("maps/%s.mob" % map))
		check(mob.lights.size() == {"zone10": 34, "zone17": 28, "zone15": 19, "bz7g": 13}[map], map + " light count")
	# Placed records are absolute: the signpost lights sit just above its hill.
	var scene := MenuScene.create()
	check(scene != null, "the menu scene builds")
	if scene == null: return finish()
	add_child(scene)
	await frames()
	var ground := scene.world.ground_at(post.x, post.y)
	for l: Dictionary in white:
		check(l.position.z - ground > 1.0 and l.position.z - ground < 4.0, "signpost light height above ground " + str(l.position.z - ground))
	var fx: ParticleFx = scene._fx
	check(fx.map_lights.size() == 6, "the menu scene creates all six map lights")
	for i in fx.map_lights.size():
		var d: Dictionary = fx.map_lights[i]
		var node: OmniLight3D = d.light
		var rec: Dictionary = menu.lights[i]
		check(node.is_inside_tree() and node.is_in_group(Gfx.POINT_LIGHT_GROUP), "map light %d is an active point light" % i)
		check(is_equal_approx(node.omni_range, rec.radius) and node.light_color.is_equal_approx(rec.color), "map light %d colour and radius" % i)
		check(node.global_position.is_equal_approx(ParticleFx.godot(rec.position)), "map light %d position is absolute" % i)
		check(d.until == -1 and not d.has("halo") and node.light_volumetric_fog_energy == 0.0, "map light %d is permanent, without torch extras" % i)
	# Replacing the set (a second setup) never duplicates lights.
	fx.add_map_lights(scene.world.mob)
	check(fx.map_lights.size() == 6 and fx.lights.size() == 6, "re-adding replaces the previous map lights")
	scene.free()
	# A campaign zone gets its records through the zone setup.
	var w := GameWorld.new()
	w.zone = {"type": "zone"}
	check(w.load_map("zone10", "", false), "zone10 loads")
	add_child(w)
	var zfx := ParticleFx.of(w)
	zfx.setup_zone()
	check(zfx.map_lights.size() == 34, "zone10 setup creates its 34 map lights")
	zfx.setup_zone()
	check(zfx.map_lights.size() == 34, "a second zone attach does not add them again")
	w.free()
	finish()

func finish() -> void:
	print("MAP_LIGHTS ", checks, " checks ", failures, " failures")
	get_tree().quit(1 if failures else 0)
