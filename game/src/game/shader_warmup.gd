class_name ShaderWarmup
extends Node3D
## Remake, Compatibility renderer only (web, Android, --rendering-method
## gl_compatibility): compiles the GL programs of materials that first appear
## during play while the zone is still loading. Godot's GLES3 backend has no
## ubershader: a program is built for each shader on its first draw in each
## state (instancing, the sun's separate shadow pass, a point light in the
## base pass, a shadowed point light's additive pass, the shadow and depth
## passes ...), and a build on desktop GL, WebGL (ANGLE) or a phone took up to
## seconds, so the first fireball, lightning, rain, move order and so on
## stalled the game. Forward+ / Mobile keep their own pipeline cache.
##
## `run` (Session, at the end of a zone load) puts zero-area quads with each
## material under the camera, just past the near plane, at four spots: no
## point light, an unshadowed one, a shadowed one, both (lights of 3 cm range
## that reach only their spot). The zone's first picture and then each batch
## are drawn with RenderingServer.force_draw while the loading screen covers
## the view; on the web (no forced draws there, see LoadingScreen) the whole
## set is drawn with the zone's first frame. Zero area: no pixel is ever
## written. The materials are:
##   - the zone's own (terrain, water, map objects, units, their camera-fade
##     dither copies), for the point light and shadow variants,
##   - effects that are not in the zone yet: the four particle shaders
##     (blend mix / add, depth tested or not, drawn as a MultiMesh like
##     ParticleFx), lightning, light halo, rain / snow, the Field of vision
##     overlay, arrows, the selection triangle.
## A material set (shader, light state, environment) already warmed in this
## run is skipped. Bounded by `budget_ms` per load (stops between batches;
## the zone's first picture, built on the first frame of play before, is not
## counted).

static var enabled := true
## Wall time per zone load; the rest compiles on first use as before. 0: no limit.
static var budget_ms := 2000
static var last_ms := 0
static var last_count := 0
const BATCH := 2
const DIST := 0.5         # metres in front of the camera (near plane 0.05..0.1)
const LIGHT_RANGE := 0.03
const GROUP_GAP := 0.08
enum {MESH, PARTICLE, INSTANCED}

static var _warmed := {}   # key -> true
static var _keep: Array[Material] = []   # _shader_holder copies
static var _quad: QuadMesh
static var _mms := {}   # kind -> MultiMesh


static func active() -> bool:
	return enabled and Portability.compatibility() and DisplayServer.get_name() != "headless"


## Session: after the zone is built, the parties deployed and the camera set.
static func run(game: Game) -> void:
	last_ms = 0
	last_count = 0
	if not active() or game == null or not is_instance_valid(game.world) or game.rig == null:
		return
	var cam := game.rig.camera
	if cam == null or not cam.is_inside_tree():
		return
	var t0 := Time.get_ticks_msec()
	var env := _env_key(game)
	var items: Array = []   # [key, material, kind]
	var seen := {}
	# Most often needed first (the budget may stop the list): the particles
	# (move orders, every spell), the zone's materials under point lights
	# (any spell or fire light), then the other effects.
	for add in [false, true]:
		for through in [true, false]:
			var pm := ShaderMaterial.new()
			pm.shader = ParticleFx._shader(add, through)
			_add(items, seen, pm, env, PARTICLE)
	for m: Material in _zone_materials(game.world) + _effect_materials(game):
		_add(items, seen, m, env, MESH)
	# VisionFog: its overlay is a MultiMesh of plain transforms.
	_add(items, seen, VisionFog.material(), env, INSTANCED)
	if items.is_empty():
		return
	var w := ShaderWarmup.new()
	w.name = "ShaderWarmup"
	cam.add_child(w)
	w.position = Vector3(0, 0, -maxf(DIST, cam.near * 4.0))
	w._make_groups()
	# Under the loading screen: draw batch by batch, stop at the budget.
	var forced := LoadingScreen._current != null and not (OS.has_feature("web") or LoadingScreen.force_deferred)
	if forced:
		# The zone's first picture, under the loading screen: its programs
		# were built on the first frame of play before; not counted.
		_push(cam, w)
		RenderingServer.force_draw(true, 0.0)
	var first_ms := Time.get_ticks_msec() - t0
	t0 = Time.get_ticks_msec()
	var i := 0
	while i < items.size():
		var n := items.size() if not forced else mini(i + BATCH, items.size())
		var shown: Array[Node] = []
		for j in range(i, n):
			shown.append_array(w._show(items[j][1], items[j][2]))
			_warmed[items[j][0]] = true
			if items[j][1] is BaseMaterial3D:
				_keep.append(_shader_holder(items[j][1]))
		last_count += n - i
		i = n
		if forced:
			_push(cam, w)
			RenderingServer.force_draw(true, 0.0)
			for c in shown:
				c.queue_free()   # freed at the frame's end; hidden for the next batch
				(c as Node3D).visible = false
			if budget_ms > 0 and Time.get_ticks_msec() - t0 >= budget_ms:
				break
	last_ms = Time.get_ticks_msec() - t0
	GameData.trace("shader warm-up: %d of %d materials, %d ms (zone's first picture %d ms)%s" % [
		last_count, items.size(), last_ms, first_ms, "" if forced else ", drawn with the first frame"])
	if forced:
		w.queue_free()
	else:
		w._free_after(2)


## A BaseMaterial3D's shader is freed with the last material of its kind (a
## VisionFog cast makes a new one each time): a copy that keeps it, with
## a 1 x 1 stand-in for each texture (no zone's textures held).
static func _shader_holder(m: BaseMaterial3D) -> BaseMaterial3D:
	var c := m.duplicate() as BaseMaterial3D
	for p: Dictionary in c.get_property_list():
		if int(p.type) == TYPE_OBJECT and (int(p.usage) & PROPERTY_USAGE_STORAGE) and c.get(p.name) is Texture2D:
			c.set(p.name, _stand_in())
	return c


static var _tex: ImageTexture

static func _stand_in() -> ImageTexture:
	if _tex == null:
		_tex = ImageTexture.create_from_image(Image.create(1, 1, false, Image.FORMAT_RGBA8))
	return _tex


## Mid-load the tree has not sent the new transforms to the renderer yet
## (that happens once per frame): push the camera's and the quads' so they
## are drawn where they are.
static func _push(cam: Camera3D, w: Node3D) -> void:
	cam.force_update_transform()
	w.force_update_transform()
	for g in w.get_children():
		(g as Node3D).force_update_transform()
		for c in g.get_children():
			(c as Node3D).force_update_transform()


static func _add(items: Array, seen: Dictionary, m: Material, env: String, kind: int) -> void:
	if m == null:
		return
	var k := _mat_key(m) + ("i%d" % kind if kind != MESH else "")
	if k.is_empty() or seen.has(k):
		return
	seen[k] = true
	var key := k + "|" + env
	if _warmed.has(key):
		return
	items.append([key, m, kind])


## One material per shader: a ShaderMaterial by its shader, a BaseMaterial3D
## by the settings its generated shader depends on (flags and enums, which
## texture slots are set; not colours or amounts).
static func _mat_key(m: Material) -> String:
	if m is ShaderMaterial:
		var sh := (m as ShaderMaterial).shader
		return "s%d" % sh.get_instance_id() if sh and sh.get_mode() == Shader.MODE_SPATIAL else ""
	if not m is BaseMaterial3D:
		return ""
	var k := PackedStringArray([m.get_class()])
	for p: Dictionary in m.get_property_list():
		if not (int(p.usage) & PROPERTY_USAGE_STORAGE):
			continue
		match int(p.type):
			TYPE_BOOL, TYPE_INT:
				k.append(str(m.get(p.name)))
			TYPE_OBJECT:
				k.append("1" if m.get(p.name) != null else "0")
	return "b" + str(hash(",".join(k)))


## Fog, sky light and sun shadow decide variants for every material.
static func _env_key(game: Game) -> String:
	var e: Environment = game.get_viewport().world_3d.environment if game.get_viewport().world_3d else null
	var we := game.find_child("WorldEnvironment", true, false) as WorldEnvironment
	if we and we.environment:
		e = we.environment
	var k := ""
	if e:
		k = "%d%d%d%d" % [int(e.fog_enabled), int(e.volumetric_fog_enabled), e.background_mode, e.ambient_light_source]
	var sun := game.get("_sun") as DirectionalLight3D
	if sun:
		k += "%d%d" % [int(sun.shadow_enabled and sun.visible), sun.directional_shadow_mode]
	k += "%d" % int(_shadowed_points())
	return k


## LocalLighting gives fire, spell and lava lights shadows with these options.
static func _shadowed_points() -> bool:
	return Gfx.on("gfx_firelight") or Gfx.on("gfx_lava_light")


static func _zone_materials(w: GameWorld) -> Array[Material]:
	var out: Array[Material] = []
	var objects := {}
	var faded := {}   # Shader -> true
	if w.map:
		for o in w.map.object_nodes:
			if is_instance_valid(o):
				objects[o] = true
	var haze := Gfx.heat_haze_on()
	for n: Node in w.find_children("*", "GeometryInstance3D", true, false):
		var g := n as GeometryInstance3D
		if not haze and g.is_in_group(&"gfx_heat_haze"):
			continue   # never shown on this renderer (Gfx.heat_haze_on)
		var ms: Array[Material] = []
		if g.material_override:
			ms.append(g.material_override)
		var mi := g as MeshInstance3D
		if mi and mi.mesh and g.material_override == null:
			for s in mi.mesh.get_surface_count():
				var m := mi.get_active_material(s)
				if m:
					ms.append(m)
		out.append_array(ms)
		# A map object the camera comes close to is drawn with CameraFade's
		# dither copy of its material.
		var sm := g.material_override as ShaderMaterial
		if sm and sm.shader and not faded.has(sm.shader) and _object_of(g, objects):
			faded[sm.shader] = true
			var d := CameraFade.dither_shader(sm.shader)
			if d:
				var dm := ShaderMaterial.new()
				dm.shader = d
				out.append(dm)
	return out


static func _object_of(n: Node, objects: Dictionary) -> bool:
	while n:
		if objects.has(n):
			return true
		n = n.get_parent()
	return false


## Effect materials that are not in a freshly loaded zone, as their owners
## make them.
static func _effect_materials(game: Game) -> Array[Material]:
	var out: Array[Material] = [FxLightning._strip_mat(false), FxLightning._glow_mat(),
		VisionFog.material(), Projectile.material()]
	if Gfx.on("gfx_torch_glow"):
		var h := Gfx.torch_halo(1.0, Color.WHITE)
		out.append(h.material_override)
		h.free()
	var rain := game.get_node_or_null("RainSnow") as FxRainSnow
	if rain:
		out.append(rain.material_override)
	if game.marks:
		out.append(game.marks._sel_mat)
	return out


## Four spots side by side (GROUP_GAP apart, each light reaching LIGHT_RANGE):
## no point light; an unshadowed one (it goes into the base pass); a shadowed
## one (its own additive pass, the sun's shadow then a pass of its own); both.
## Each is a state of its own, for unshaded materials too (the light counts
## are part of every program's defines).
func _make_groups() -> void:
	var lights := [[], [false]]
	if _shadowed_points():
		lights += [[true], [false, true]]
	for gi in lights.size():
		var g := Node3D.new()
		add_child(g)
		g.position = Vector3((gi - (lights.size() - 1) * 0.5) * GROUP_GAP, 0, 0)
		for shadowed: bool in lights[gi]:
			var l := OmniLight3D.new()
			l.omni_range = LIGHT_RANGE
			l.light_energy = 0.001
			if shadowed:
				LocalLighting._light_quality(l)
				l.shadow_enabled = true
			g.add_child(l)


func _show(m: Material, kind: int) -> Array[Node]:
	var out: Array[Node] = []
	for g in get_children():
		var gi: GeometryInstance3D
		if kind == MESH:
			var mi := MeshInstance3D.new()
			mi.mesh = _zero_quad()
			gi = mi
		else:
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = _multimesh(kind)
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			gi = mmi
		gi.material_override = m
		gi.custom_aabb = AABB(Vector3(-0.01, -0.01, -0.01), Vector3(0.02, 0.02, 0.02))
		g.add_child(gi)
		out.append(gi)
	return out


## One instance, all rows 0: for particle.gdshader a particle of size 0 at
## the origin (ParticleFx's format: colours and custom data), for the
## VisionFog overlay a cell of scale 0.
static func _multimesh(kind: int) -> MultiMesh:
	if not _mms.has(kind):
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = kind == PARTICLE
		mm.use_custom_data = kind == PARTICLE
		mm.mesh = _zero_quad()
		mm.instance_count = 1
		mm.set_instance_transform(0, Transform3D(Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO), Vector3.ZERO))
		if kind == PARTICLE:
			mm.set_instance_color(0, Color(0, 0, 0, 0))
			mm.set_instance_custom_data(0, Color(0, 0, 0, 0))
		_mms[kind] = mm
	return _mms[kind]


## A quad of size 0: every draw state and program as for a real one, no
## pixel covered.
static func _zero_quad() -> QuadMesh:
	if _quad == null:
		_quad = QuadMesh.new()
		_quad.size = Vector2.ZERO
	return _quad


func _free_after(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame
	queue_free()
