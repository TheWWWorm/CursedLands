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
const REFLECTION_WARMUP_LAYER := 1 << 13
const WaterReflection = preload("res://src/game/fx/water_reflection.gd")
enum {MESH, PARTICLE, INSTANCED, GRASS, REGIONAL, COLORED}

static var _warmed := {}   # key -> true
static var _keep: Array[Material] = []   # _shader_holder copies
static var _quad: QuadMesh
static var _lightning: ImmediateMesh
static var _mms := {}   # kind -> MultiMesh
static var _formats := {} # vertex format -> zero-area mesh of that exact format
static var _progress_serial := 0
var _progress_owner: StringName
var _reflection_view: SubViewport
var _reflection_camera: Camera3D


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
	_progress_serial += 1
	var progress_owner := StringName("materials:%d" % _progress_serial)
	var progress := ShaderCompilationScreen.begin(game.get_tree(), progress_owner, ShaderCompilationScreen.SCENE)
	if progress: progress.present()
	var ambient := game.get_node_or_null("AmbientLife")
	if ambient: ambient.prepare_world()
	if game.world.ground_marks: game.world.ground_marks.prepare_footprints()
	var previews := game.hud.prepare_previews() if game.hud else []
	var polygons := CanvasPolygons.new()
	# The HUD (where conversations draw) accepts children while a zone is
	# entered from a _ready; the root is then busy setting up its own.
	(game.hud if game.hud and game.hud.is_inside_tree() else cam.get_tree().root).add_child(polygons)
	polygons.free_after(3)
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
	_prepare_bird(game)
	var t0 := Time.get_ticks_msec()
	var env := _env_key(game)
	var items: Array = []   # [key, material, kind, mesh, shadow mode]
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
	_add(items, seen, Projectile.material(), env, MESH, _zero_format(Projectile.shaft_mesh()))
	for m: Material in _effect_materials(game):
		_add(items, seen, m, env, MESH)
	if game.world.ground_marks:
		var ground_mark := game.world.ground_marks.warmup_variant()
		if not ground_mark.is_empty():
			_add(items, seen, ground_mark[0], env, MESH, ground_mark[1])
	if game.world.terrain and game.world.terrain.details and game.world.terrain.details._material:
		var grass := game.world.terrain.details
		_multimesh(GRASS).mesh = grass._mesh
		_add(items, seen, grass._material, env, GRASS)
		if grass._grass:
			# Far tiles stream in a few seconds after play starts.
			var far: Array = grass._far_grass.prepare()
			_add(items, seen, far[1], env, GRASS, far[0])
		for variant: Array in grass.cover_warmup_variants():
			_add(items, seen, variant[0], env, MESH, _zero_format(variant[1]), variant[2])
	# VisionFog: its overlay is a MultiMesh of plain transforms.
	_add(items, seen, VisionFog.material(), env, INSTANCED)
	if items.is_empty():
		_prepare_mirror(game, cam, forced)
		ShaderCompilationScreen.end(progress_owner)
		return
	ShaderCompilationScreen.update(progress_owner, ShaderCompilationScreen.SCENE, 0, items.size())
	var w := ShaderWarmup.new()
	w._progress_owner = progress_owner
	w.name = "ShaderWarmup"
	cam.add_child(w)
	w.position = Vector3(0, 0, -maxf(DIST, cam.near * 4.0))
	w._make_groups()
	if _warm_reflections(): w._make_reflection_view(cam)
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
			shown.append_array(w._show(items[j][1], items[j][2], items[j][3], items[j][4]))
			if items[j][1] is BaseMaterial3D:
				_keep.append(_shader_holder(items[j][1]))
		var start := i
		i = n
		if forced:
			_push(cam, w)
			# Newly placed geometry enters Forward+'s motion-vector pass for
			# several draws. Keep it still long enough to prepare the stationary
			# color pass too; streamed far grass otherwise first builds that
			# pipeline after play starts. Do not push transforms between draws.
			for settle in (4 if RenderingServer.get_current_rendering_method()=="forward_plus" else 1):
				RenderingServer.force_draw(true, 0.0)
				# Queue submission alone is not compilation completion with a
				# rendering worker. Wait only under the loading screen.
				RenderingServer.force_sync()
			# Count only batches whose draw has completed. A submitted shader
			# or a pipeline-counter increment is not compilation completion.
			for j in range(start, n): _warmed[items[j][0]] = true
			last_count += n - start
			ShaderCompilationScreen.update(progress_owner, ShaderCompilationScreen.MATERIALS, last_count, items.size())
			if progress: progress.present()
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
		_prepare_mirror(game, cam, true)
		w.queue_free()
		ShaderCompilationScreen.end(progress_owner)
	else:
		w._finish_deferred(items)


static func _prepare_mirror(game: Game, source: Camera3D, forced: bool) -> void:
	if not forced or not is_instance_valid(game.world.terrain): return
	var reflection := game.world.terrain._reflection
	if is_instance_valid(reflection): reflection.prepare_loading(source)


func _finish_deferred(items: Array) -> void:
	for i in (4 if RenderingServer.get_current_rendering_method()=="forward_plus" else 2):
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
	for item: Array in items: _warmed[item[0]] = true
	last_count = items.size()
	ShaderCompilationScreen.update(_progress_owner, ShaderCompilationScreen.MATERIALS, last_count, items.size())
	ShaderCompilationScreen.end(_progress_owner)
	queue_free()


func _exit_tree() -> void:
	if not _progress_owner.is_empty(): ShaderCompilationScreen.end(_progress_owner)
	if is_instance_valid(_reflection_view): _reflection_view.queue_free()


## QuestBird.prepare at the local hero (the bird's first flight is there),
## else in front of the camera.
static func _prepare_bird(game: Game) -> void:
	var w := game.world
	var cam := game.rig.camera
	var at := cam.global_position - cam.global_basis.z * maxf(DIST, cam.near * 4.0)
	if game.session:
		for u: GameUnit in w.units.values():
			if u.controller == game.session.my_index and u.has_meta("hero") and not u.dead \
					and u.is_inside_tree():
				at = u.global_position + Vector3(0, 2, 0)
				break
	QuestBird.prepare(w, at)


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
	if is_instance_valid(w._reflection_camera):
		w._reflection_camera.global_transform = cam.global_transform
		w._reflection_camera.force_update_transform()
	w.force_update_transform()
	for g in w.get_children():
		(g as Node3D).force_update_transform()
		for c in g.get_children():
			(c as Node3D).force_update_transform()


static func _add(items: Array, seen: Dictionary, m: Material, env: String, kind: int, mesh: Mesh = null, shadow_mode := -1) -> void:
	if m == null:
		return
	var k := _mat_key(m) + ("i%d" % kind if kind != MESH else "")
	if k.is_empty(): return
	if mesh: k += ":v%d" % mesh.get_instance_id()
	k += ":shadow%d" % _shadow_mode(kind, shadow_mode)
	if seen.has(k):
		return
	seen[k] = true
	var key := k + "|" + env
	if _warmed.has(key):
		return
	items.append([key, m, kind, mesh, _shadow_mode(kind, shadow_mode)])


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
	k += ":mirror%d" % int(_warm_reflections())
	return k


static func _warm_reflections() -> bool:
	return WaterReflection.supported() and Gfx.on("gfx_water") and GameData.option("gfx_water_reflections") >= 2


func _make_reflection_view(source: Camera3D) -> void:
	_reflection_view = SubViewport.new()
	_reflection_view.name = "ReflectionShaderWarmup"
	WaterReflection.configure_viewport(_reflection_view,source.get_world_3d())
	_reflection_view.size = Vector2i(32,32)
	_reflection_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	# A sibling keeps the normal light groups unchanged. Only the collapsed
	# warm-up geometry uses this otherwise unassigned layer, so this view
	# never renders a second copy of the map while preparing each batch.
	source.add_child(_reflection_view)
	_reflection_camera = Camera3D.new()
	_reflection_camera.environment = WaterReflection.reflection_environment()
	_reflection_camera.cull_mask = REFLECTION_WARMUP_LAYER | WaterReflection.CAMERA_MARKER
	_reflection_camera.near = source.near
	_reflection_camera.far = source.far
	_reflection_camera.fov = source.fov
	_reflection_view.add_child(_reflection_camera)
	_reflection_camera.global_transform = source.global_transform
	_reflection_camera.current = true


## LocalLighting gives fire, spell and lava lights shadows with these options.
static func _shadowed_points() -> bool:
	return Gfx.on("gfx_firelight") or Gfx.on("gfx_lava_light")


static func _zone_materials(w: Node3D) -> Array:
	var out: Array = []
	var objects := {}
	var faded := {}   # Shader -> true
	if w is GameWorld and w.map:
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
	# Preserve custom-channel encodings as well as compression/bone flags.
	var flags := format & ~((1 << Mesh.ARRAY_MAX) - 1)
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
		VisionFog.material()]
	if Gfx.on("gfx_torch_glow"):
		out.append(Gfx.torch_halo_material(Color.WHITE))
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


static func _shadow_mode(kind: int, requested: int) -> int:
	if requested >= 0: return requested
	if kind == MESH: return GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED if kind == GRASS else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _show(m: Material, kind: int, source: Mesh = null, shadow_mode := -1) -> Array[Node]:
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
			gi = mmi
		gi.cast_shadow = _shadow_mode(kind, shadow_mode)
		gi.material_override = m
		gi.layers |= REFLECTION_WARMUP_LAYER
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
		mm.mesh = source if source else ParticleFx.quad_mesh() if kind == PARTICLE else _zero_quad()
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


static func _zero_lightning() -> ImmediateMesh:
	# Lightning writes only position, colour and UV. QuadMesh adds normals
	# and tangents, which leaves the real bolt's pipeline cold.
	if _lightning == null:
		_lightning = ImmediateMesh.new()
		_lightning.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in 3:
			_lightning.surface_set_color(Color.WHITE)
			_lightning.surface_set_uv(Vector2.ZERO)
			_lightning.surface_add_vertex(Vector3.ZERO)
		_lightning.surface_end()
	return _lightning


## The conversation frame's strips (DialogPanel._frame) are the first
## textured, vertex-coloured canvas polygons a zone draws; their pipeline
## cost ~20 ms as the first briefing opened. An invisible quad builds it.
class CanvasPolygons extends Node2D:
	func _draw() -> void:
		draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(1, 0), Vector2.ONE, Vector2(0, 1)]),
			PackedColorArray([Color.TRANSPARENT, Color.TRANSPARENT, Color.TRANSPARENT, Color.TRANSPARENT]),
			PackedVector2Array([Vector2.ZERO, Vector2(1, 0), Vector2.ONE, Vector2(0, 1)]), ShaderWarmup._stand_in())

	func free_after(frames: int) -> void:
		var tree := get_tree()
		if tree == null:
			queue_free()
			return
		for i in frames:
			await tree.process_frame
		queue_free()


func _free_after(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame
	queue_free()


## Autochess has a SubViewport and no campaign loading path. Prepare the
## same effect/mesh pipelines in small batches before its shared battle bell.
static func arena(field: ArenaPveField) -> void:
	if not active() or not is_instance_valid(field) or not field.is_inside_tree(): return
	var tree := field.get_tree()
	_progress_serial += 1
	var progress_owner := StringName("materials:arena:%d" % _progress_serial)
	var previous_update := field.view.render_target_update_mode
	var exited := _arena_end.bind(weakref(field.view), progress_owner, previous_update)
	field.tree_exiting.connect(exited, CONNECT_ONE_SHOT)
	var items := []; var seen := {}
	var env := "arena:"+str([field._environment.fog_enabled,field._environment.volumetric_fog_enabled,
		field._sun_light.shadow_enabled,Gfx.on("gfx_firelight"),GameData.option("q_msaa")])
	for additive in [false,true]:
		var material:=ShaderMaterial.new();material.shader=ParticleFx._shader(additive,false,false)
		var before := items.size()
		_add(items,seen,material,env,PARTICLE)
		if items.size() > before: await _arena_frame(tree)
		if not is_instance_valid(field) or not field.is_inside_tree() or field.is_queued_for_deletion():
			exited.call()
			return
	for make: Callable in [func():return FxLightning._strip_mat(false),FxLightning._glow_mat]:
		var material: Material = make.call()
		var before := items.size()
		_add(items,seen,material,env,MESH,_zero_lightning())
		if items.size() > before: await _arena_frame(tree)
		if not is_instance_valid(field) or not field.is_inside_tree() or field.is_queued_for_deletion():
			exited.call()
			return
	var before_projectile := items.size()
	_add(items,seen,Projectile.material(),env,MESH,_zero_format(Projectile.shaft_mesh()))
	if items.size() > before_projectile: await _arena_frame(tree)
	if not is_instance_valid(field) or not field.is_inside_tree() or field.is_queued_for_deletion():
		exited.call()
		return
	if Gfx.on("gfx_torch_glow"):
		# A temporary MeshInstance followed by immediate free synchronizes the
		# rendering worker. Warm its material without allocating an instance.
		var before := items.size()
		_add(items,seen,Gfx.torch_halo_material(Color.WHITE),env,MESH)
		if items.size() > before: await _arena_frame(tree)
		if not is_instance_valid(field) or not field.is_inside_tree() or field.is_queued_for_deletion():
			exited.call()
			return
	# Courtyards are independent branches. Collect a board per frame instead
	# of inspecting thousands of figure surfaces in a single transition frame.
	for branch: Node in field.stage.get_children():
		if is_instance_valid(branch) and branch is Node3D:
			var before := items.size()
			for variant: Array in _zone_materials(branch):
				_add(items,seen,variant[0],env,variant[1],variant[2])
			if items.size() > before: await _arena_frame(tree)
			if not is_instance_valid(field) or not field.is_inside_tree() or field.is_queued_for_deletion():
				exited.call()
				return
	if not items.is_empty():
		ShaderCompilationScreen.begin(tree, progress_owner, ShaderCompilationScreen.MATERIALS, 0, items.size())
		if is_instance_valid(field.view): field.view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		ShaderCompilationScreen.update(progress_owner, ShaderCompilationScreen.MATERIALS, 0, items.size())
		var warmer:=ShaderWarmup.new();field.camera.add_child(warmer)
		warmer._progress_owner = progress_owner
		warmer.position=Vector3(0,0,-maxf(DIST,field.camera.near*4))
		warmer._make_groups()
		var completed := 0
		for item: Array in items:
			var shown:=warmer._show(item[1],item[2],item[3],item[4])
			if item[1] is BaseMaterial3D: _keep.append(_shader_holder(item[1]))
			await _arena_frame(tree, field.view)
			if not is_instance_valid(field) or not field.is_inside_tree() or field.is_queued_for_deletion():
				exited.call()
				return
			# Only a completed ordinary draw admits a prepared material. This
			# also keeps the SubViewport's shader/pipeline work out of the bell.
			_warmed[item[0]]=true
			completed += 1
			ShaderCompilationScreen.update(progress_owner, ShaderCompilationScreen.MATERIALS, completed, items.size())
			for node: Node3D in shown: node.hide();node.queue_free()
		# Present the completed denominator before changing to final settling.
		await _arena_frame(tree)
		if is_instance_valid(warmer): warmer.queue_free()
	exited.call()
	if is_instance_valid(field) and field.tree_exiting.is_connected(exited): field.tree_exiting.disconnect(exited)
	# prepare_battle_presentation keeps its existing _warming/picking gate;
	# do not let the shared bell start behind the screen's final draw fence.
	while ShaderCompilationScreen.active():
		await _arena_frame(tree)
		if not is_instance_valid(field) or not field.is_inside_tree() or field.is_queued_for_deletion(): return


static func _arena_frame(tree: SceneTree, view: SubViewport = null) -> void:
	await tree.process_frame
	while true:
		await RenderingServer.frame_pre_draw
		if not is_instance_valid(view) or not view.is_inside_tree(): break
		# A different preparation owner can present only the canvas. That
		# must not admit this batch before its arena viewport actually draws.
		if not view.disable_3d and view.render_target_update_mode != SubViewport.UPDATE_DISABLED: break
	# On Separate, frame_post_draw is deferred and may belong to an older
	# draw. Queue this fence after the observed draw has been submitted, and
	# resume only after its rendering command has finished on either model.
	var fence := ArenaDrawFence.new()
	ArenaDrawFence.submit.call_deferred(fence)
	await fence.completed


class ArenaDrawFence extends RefCounted:
	signal completed
	static func submit(fence: ArenaDrawFence) -> void:
		RenderingServer.call_on_render_thread(recorded.bind(fence))
	static func recorded(fence: ArenaDrawFence) -> void:
		finish.call_deferred(fence)
	static func finish(fence: ArenaDrawFence) -> void:
		fence.completed.emit()


static func _arena_end(view_reference: WeakRef, owner: StringName, update_mode: int) -> void:
	# The exit signal owns only a weak viewport reference and a unique token;
	# an abandoned arena cannot retain its viewport or close a successor's hold.
	var view := view_reference.get_ref() as SubViewport
	if is_instance_valid(view): view.render_target_update_mode = update_mode
	ShaderCompilationScreen.end(owner)
