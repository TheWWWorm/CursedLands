class_name ShaderWarmup
extends Node3D
## Prepare materials that first appear during play while the zone is still
## loading, including spell variants absent from the initial camera view.
## Godot's GLES3 backend has no
## ubershader: a program is built for each shader on its first draw in each
## state (instancing, the sun's separate shadow pass, a point light in the
## base pass, a shadowed point light's additive pass, the shadow and depth
## passes ...), and a build on desktop GL, WebGL (ANGLE) or a phone took up to
## seconds, so the first fireball, lightning, rain, move order and so on
## stalled the game. Forward+ / Mobile also need a first draw to populate
## their pipeline cache for those previously unseen materials.
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
## run is skipped. GLES is bounded by `budget_ms` per load (stops between
## batches; the zone's first picture is not counted). Forward+ / Mobile
## finish the complete set, including spell pipelines needed in combat.

static var enabled := true
## GLES wall time per zone load; the rest compiles on first use. 0: no limit.
static var budget_ms := 2000
static var last_ms := 0
static var last_count := 0
const BATCH := 2
const DIST := 0.5         # metres in front of the camera (near plane 0.05..0.1)
const LIGHT_RANGE := 0.03
const GROUP_GAP := 0.08
enum {MESH, PARTICLE, INSTANCED, GRASS, REGIONAL, COLORED}

static var _warmed := {}   # key -> true
static var _keep: Array[Material] = []   # _shader_holder copies
static var _quad: QuadMesh
static var _mms := {}   # kind -> MultiMesh
static var _formats := {} # vertex format -> zero-area mesh of that exact format


static func active() -> bool:
	return enabled and DisplayServer.get_name() != "headless" \
		and not OS.get_cmdline_user_args().has("--ei-no-shader-warmup")


## Session: after the zone is built, the parties deployed and the camera set.
static func run(game: Game) -> void:
	last_ms = 0
	last_count = 0
	if not active() or game == null or not is_instance_valid(game.world) or game.rig == null:
		return
	var cam := game.rig.camera
	if cam == null or not cam.is_inside_tree():
		return
	var ambient := game.get_node_or_null("AmbientLife")
	if ambient: ambient.prepare_world()
	if game.world.ground_marks: game.world.ground_marks.prepare_footprints()
	var previews := game.hud.prepare_previews() if game.hud else []
	var forced := LoadingScreen._current != null and not (OS.has_feature("web") or LoadingScreen.force_deferred)
	if not previews.is_empty():
		if forced:
			RenderingServer.force_draw(true, 0.0)
			RenderingServer.force_sync()
			_restore_previews(previews)
		else:
			_finish_previews(game.get_tree(), previews)
	if game.world.terrain:
		var terrain:=game.world.terrain
		if not is_instance_valid(terrain.color_cache) and TerrainColorCache.available(terrain):
			terrain.color_cache=TerrainColorCache.create(terrain)
		if is_instance_valid(terrain.color_cache):terrain.color_cache.prepare(cam)
	var t0 := Time.get_ticks_msec()
	var env := _env_key(game)
	var items: Array = []   # [key, material, kind]
	var seen := {}
	# Most often needed first (the budget may stop the list): the particles
	# (move orders, every spell), the zone's materials under point lights
	# (any spell or fire light), then the other effects.
	for add in [false, true]:
		for through in [true, false]:
			for marker in [false, true]:
				# Path/target indicators have a separate reflection-exclusion
				# shader even when their through-obstacles option is off.
				var pm := ShaderMaterial.new()
				pm.shader = ParticleFx._shader(add, through, marker)
				_add(items, seen, pm, env, PARTICLE)
	# Regional particles are admitted only after loading finishes, so they
	# are absent from _zone_materials. Their MultiMesh has custom data but
	# no instance colours; warm that exact format before play resumes.
	if Gfx.on("gfx_ambient_particles"):
		var regional := preload("res://src/game/fx/ambient_particles.gd").make_material()
		_add(items, seen, regional, env, REGIONAL)
	for variant: Array in _zone_materials(game.world):
		_add(items, seen, variant[0], env, variant[1], variant[2])
	if ambient:
		for variant: Array in ambient.warmup_variants():
			_add(items, seen, variant[0], env, MESH, _zero_format(variant[1]))
	for m: Material in _effect_materials(game):
		_add(items, seen, m, env, MESH)
	if game.world.terrain and game.world.terrain.details and game.world.terrain.details._material:
		var grass := game.world.terrain.details
		_multimesh(GRASS).mesh = grass._mesh
		_add(items, seen, grass._material, env, GRASS)
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
	if forced:
		# The zone's first picture, under the loading screen: its programs
		# were built on the first frame of play before; not counted.
		_push(cam, w)
		RenderingServer.force_draw(true, 0.0)
		RenderingServer.force_sync()
	var first_ms := Time.get_ticks_msec() - t0
	t0 = Time.get_ticks_msec()
	var i := 0
	while i < items.size():
		var n := items.size() if not forced else mini(i + BATCH, items.size())
		var shown: Array[Node] = []
		for j in range(i, n):
			shown.append_array(w._show(items[j][1], items[j][2], items[j][3]))
			_warmed[items[j][0]] = true
			if items[j][1] is BaseMaterial3D:
				_keep.append(_shader_holder(items[j][1]))
		last_count += n - i
		i = n
		if forced:
			_push(cam, w)
			RenderingServer.force_draw(true, 0.0)
			# With a rendering worker, queue submission alone does not measure
			# compilation time or honor the loading budget. Wait only here.
			RenderingServer.force_sync()
			for c in shown:
				c.queue_free()   # freed at the frame's end; hidden for the next batch
				(c as Node3D).visible = false
			# RD's first unseen effect can otherwise synchronously compile a
			# missing pipeline in combat. Finish this small shader set at load;
			# Compatibility retains its bounded per-zone program budget.
			if Portability.compatibility() and budget_ms > 0 and Time.get_ticks_msec() - t0 >= budget_ms:
				break
	last_ms = Time.get_ticks_msec() - t0
	GameData.trace("shader warm-up: %d of %d materials, %d ms (zone's first picture %d ms)%s" % [
		last_count, items.size(), last_ms, first_ms, "" if forced else ", drawn with the first frame"])
	if forced:
		w.queue_free()
	else:
		w._free_after(2)


static func _restore_previews(previews: Array) -> void:
	for pair: Array in previews:
		if is_instance_valid(pair[0]): pair[0].render_target_update_mode = pair[1]


static func _finish_previews(tree: SceneTree, previews: Array) -> void:
	await tree.process_frame
	await RenderingServer.frame_post_draw
	_restore_previews(previews)


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


static func _add(items: Array, seen: Dictionary, m: Material, env: String, kind: int, mesh: Mesh = null) -> void:
	if m == null:
		return
	var k := _mat_key(m) + ("i%d" % kind if kind != MESH else "")
	if mesh: k += ":v%d" % mesh.get_instance_id()
	if k.is_empty() or seen.has(k):
		return
	seen[k] = true
	var key := k + "|" + env
	if _warmed.has(key):
		return
	items.append([key, m, kind, mesh])


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


static func _zone_materials(w: GameWorld) -> Array:
	var out: Array = []
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
		var kind := MESH
		var source: Mesh
		if g is MultiMeshInstance3D and g.multimesh:
			var mm: MultiMesh = g.multimesh
			source = mm.mesh
			kind = GRASS if mm.use_colors and mm.use_custom_data else \
				COLORED if mm.use_colors else REGIONAL if mm.use_custom_data else INSTANCED
		elif g is MeshInstance3D:
			source = g.mesh
		var mesh := _zero_format(source)
		if g.material_override:
			ms.append(g.material_override)
		var mi := g as MeshInstance3D
		if mi and mi.mesh and g.material_override == null:
			for s in mi.mesh.get_surface_count():
				var m := mi.get_active_material(s)
				if m:
					ms.append(m)
		for m: Material in ms: out.append([m, kind, mesh])
		# A map object the camera comes close to is drawn with CameraFade's
		# dither copy of its material.
		var sm := g.material_override as ShaderMaterial
		if sm and sm.shader and not faded.has(sm.shader) and _object_of(g, objects):
			faded[sm.shader] = true
			var d := CameraFade.dither_shader(sm.shader)
			if d:
				var dm := ShaderMaterial.new()
				dm.shader = d
				out.append([dm, kind, mesh])
	return out


## RD pipelines include vertex layout and instancing, not just the shader.
## A plain QuadMesh cannot warm a colored/compressed native figure or map
## surface. Keep one collapsed surface per layout, preserving its format.
static func _zero_format(source: Mesh) -> Mesh:
	if source == null or source.get_surface_count() == 0: return null
	var format: int
	var primitive: int
	if source is ArrayMesh:
		format = source.surface_get_format(0)
		primitive = source.surface_get_primitive_type(0)
	else:
		var surface := RenderingServer.mesh_get_surface(source.get_rid(), 0)
		format = int(surface.get("format", 0))
		primitive = int(surface.get("primitive", Mesh.PRIMITIVE_TRIANGLES))
	var key := str(format) + ":" + str(primitive)
	if _formats.has(key): return _formats[key]
	var arrays := source.surface_get_arrays(0)
	if arrays.is_empty() or not arrays[Mesh.ARRAY_VERTEX] is PackedVector3Array: return null
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	vertices.fill(Vector3.ZERO); arrays[Mesh.ARRAY_VERTEX] = vertices
	var mesh := ArrayMesh.new()
	var flags := format & (Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS | Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES)
	mesh.add_surface_from_arrays(primitive, arrays, [], {}, flags)
	_formats[key] = mesh
	return mesh


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


func _show(m: Material, kind: int, source: Mesh = null) -> Array[Node]:
	var out: Array[Node] = []
	for g in get_children():
		var gi: GeometryInstance3D
		if kind == MESH:
			var mi := MeshInstance3D.new()
			mi.mesh = source if source else _zero_quad()
			gi = mi
		else:
			var mmi := MultiMeshInstance3D.new()
			mmi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
			mmi.multimesh = _multimesh(kind, source)
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED if kind == GRASS else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			gi = mmi
		gi.material_override = m
		gi.custom_aabb = AABB(Vector3(-0.01, -0.01, -0.01), Vector3(0.02, 0.02, 0.02))
		g.add_child(gi)
		out.append(gi)
	return out


## One instance, all rows 0: for particle.gdshader a particle of size 0 at
## the origin (ParticleFx's format: colours and custom data), for the
## VisionFog overlay a cell of scale 0.
static func _multimesh(kind: int, source: Mesh = null) -> MultiMesh:
	var key := str(kind) + (":%d" % source.get_instance_id() if source else "")
	if not _mms.has(key):
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = kind in [PARTICLE, GRASS, COLORED]
		mm.use_custom_data = kind in [PARTICLE, GRASS, REGIONAL]
		mm.mesh = source if source else _zero_quad()
		mm.instance_count = 1
		mm.set_instance_transform(0, Transform3D(Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO), Vector3.ZERO))
		if kind in [PARTICLE, GRASS, COLORED]:
			mm.set_instance_color(0, Color(0, 0, 0, 0))
		if kind in [PARTICLE, GRASS, REGIONAL]:
			mm.set_instance_custom_data(0, Color(0, 0, 0, 0))
		_mms[key] = mm
	return _mms[key]


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
