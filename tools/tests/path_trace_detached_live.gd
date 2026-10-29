extends "res://tools/tests/scene_raytrace_live.gd"
## Real campaign combat geometry: the ordinary severing entry point copies an
## original figure. Native primary-hit identities prove those copies are traced.
signal identity_ready
var identity_counts := {}

func _read_identity(device: RefCounted) -> void:
	# Read the placement identity the ray programs write every frame (the
	# alpha half of the raw diffuse image). The custom filter's identity
	# auxiliary is only refreshed when NRD is unavailable, so it would report
	# stale geometry under the production denoiser.
	identity_counts.clear()
	var source: RID=device.ray_targets()[0] if device.has_method("ray_targets") else device._raw[0]
	var bytes: PackedByteArray=device._rd.texture_get_data(source,0)
	for offset in range(6,bytes.size(),8):
		var bits:=bytes.decode_u16(offset)
		if bits>=0x3c00 and bits<0x3c00+4096:
			var index:=bits-0x3c00
			identity_counts[index]=int(identity_counts.get(index,0))+1
	identity_ready.emit.call_deferred()

func traced_pixels(rt: Node,indices: Array) -> int:
	await RenderingServer.frame_post_draw
	RenderingServer.call_on_render_thread(_read_identity.bind(rt.device));await identity_ready
	var count:=0
	for index: int in indices:count+=int(identity_counts.get(index,0))
	return count

func owned_indices(scene: RefCounted,root: Node3D) -> Array:
	var result:=[]
	for i in scene.instances.size():
		var mesh: Node=scene.instances[i].node.get_ref()
		if mesh!=null and root.is_ancestor_of(mesh):result.append(i)
	return result

func replacement(rt: Node,previous: RefCounted) -> bool:
	var deadline:=Time.get_ticks_usec()+60000000
	while Time.get_ticks_usec()<deadline:
		await frames(1)
		if rt.stats.get("active",false) and rt._scene!=previous:
			await frames(12);return true
		if rt._failed:return false
	return false

func finish(context: Array,rt: Node) -> void:
	FileAccess.open(out.path_join("path-detached-live.json"),FileAccess.WRITE).store_string(JSON.stringify({
		"checks":checks,"failures":failures,"observations":rows,"stats":rt.stats},"\t"))
	context[1].queue_free();context[0].queue_free();await frames(16);TexUpscale.shutdown()
	print("PATH_DETACHED_LIVE ",checks," checks ",failures.size()," failures")
	get_tree().quit(1 if not failures.is_empty() else 0)

func run() -> void:
	var context:=await setup();var session: Session=context[0];var game: Game=context[1]
	GameData.options.merge({"gfx_water_reflections":0,"gfx_severed_limbs":1,"gfx_materials":1,
		"pt_mode":1,"pt_accumulation":0,"q_rt_lighting":1},true)
	t.apply_gfx();Gfx.apply_env(game._env)
	var rt: Node=game.get_node("SceneRaytrace")
	var source:=GameUnit.new()
	var loaded:=source.setup(session.world,{"prototype":"Human Hero","nid":990001,"player":0})
	check(loaded,"original human figure loads in the campaign")
	if not loaded:source.free();await finish(context,rt);return
	session.world.add_child(source);session.world.set_unit(990001,source);source.set_process(false)
	var tree: Node3D=session.world.objects[4442]
	var focus:=tree.global_position+Vector3(6,0,3)
	focus.y=t.height_at(focus.x,-focus.z)
	source.global_position=focus
	if source.model.player:
		source.model.player.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		source.model.act("idle",1,0.0);source.model.player.seek(0.3,true);source.model.player.speed_scale=0
	source.model.flush_pending_pose()
	camera.global_position=focus+Vector3(3,2,4);camera.look_at(focus+Vector3.UP)
	check(await ready_scene(rt),"campaign prepares before combat detachment")
	if not rt.stats.get("active",false):await finish(context,rt);return
	var previous: RefCounted=rt._scene
	source._show_severed(1<<3,true)
	var limb: SeveredLimb
	for node: Node in get_tree().get_nodes_in_group(GameWorld.RAYTRACE_GEOMETRY_GROUP):
		if node is SeveredLimb and session.world.is_ancestor_of(node):limb=node
	check(limb!=null,"ordinary combat severing registers an original detached arm")
	if limb==null:await finish(context,rt);return
	limb.set_process(false);source.hide()
	# Hold the real copied part in clear view, isolating collection/AS updates
	# from its separately tested ballistic simulation and ground contacts.
	limb.global_position=focus+Vector3(0,1.7,0)
	camera.global_position=limb.global_position+Vector3(1.6,0.7,2.2)
	camera.look_at(limb.global_position);camera.fov=45
	rt._poll=0.0
	check(await replacement(rt,previous),"combat geometry reaches a replacement campaign snapshot")
	if not rt.stats.get("active",false):await finish(context,rt);return
	var scene: RefCounted=rt._scene;var device: RefCounted=rt.device
	var indices:=owned_indices(scene,limb)
	check(not indices.is_empty(),"native scene retains original detached figure placements")
	var materials:=true
	for index: int in indices:
		var entry: Dictionary=scene.instances[index]
		var mesh: MeshInstance3D=entry.node.get_ref()
		materials=materials and mesh.material_override is ShaderMaterial and entry.mask==7
	check(materials,"detached original shader materials keep receiver, shadow and indirect masks")
	await frames(32)
	var pixels:=await traced_pixels(rt,indices)
	check(pixels>20,"native primary rays hit detached original mesh pixels: "+str(pixels))
	await capture("campaign-detached-visible")
	for turn in 4:
		limb.position.x+=0.04;limb.rotate_y(0.08);await frames(4)
		var exact:=true
		for index: int in indices:
			var entry: Dictionary=scene.instances[index]
			exact=exact and entry.transform==(entry.node.get_ref() as Node3D).global_transform
		var moving_pixels:=await traced_pixels(rt,indices)
		check(rt._scene==scene and rt.device==device and exact and moving_pixels>20,"moving detached native geometry stays current without rebuilding: "+str(turn))
		rows.append({"turn":turn,"traced_pixels":moving_pixels,"instances":indices.size()})
	await capture("campaign-detached-moving")
	limb.hide();await frames(4)
	check(rt._scene==scene and await traced_pixels(rt,indices)==0,"hidden detached geometry disappears from native primary rays")
	limb.show();await frames(8)
	check(rt._scene==scene and await traced_pixels(rt,indices)>20,"revealed detached geometry returns without rebuilding")
	limb.queue_free();await frames(2);rt._poll=0.0
	check(await replacement(rt,scene),"expired detached geometry is removed by a replacement snapshot")
	check(get_tree().get_nodes_in_group(GameWorld.RAYTRACE_GEOMETRY_GROUP).is_empty(),"expiry releases the campaign's dynamic geometry registry")
	await capture("campaign-detached-expired")
	await finish(context,rt)
