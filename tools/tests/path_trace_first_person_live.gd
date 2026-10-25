extends "res://tools/tests/path_trace_camera_routes.gd"
## Prepared authored-world visual route through the real first-person body
## and camera APIs. Animation/placement are deterministic; this is not an
## input or network test. path_trace_motion_route covers ordinary traversal.
var phase_rows := []
var capture_sequence := true
signal inspected_device(state: Dictionary)

func inspect_device(device: RefCounted) -> void:
	# This callback runs after queued rendering. nrd_active is a render-thread
	# working flag, briefly false inside reconstruct(); a main-thread read
	# alone cannot prove that a completed image lost denoising.
	inspected_device.emit.call_deferred({"nrd":device.nrd_active,"closed":device._closed,"renders":device.completed_renders})

func run() -> void:
	seed(7321)
	var dlss := OS.get_cmdline_user_args().has("--pt-dlss")
	var zone_id := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--pt-zone="): zone_id = arg.trim_prefix("--pt-zone=")
		if arg == "--pt-no-sequence": capture_sequence = false
	var context := await setup_route()
	if context.is_empty(): get_tree().quit(1); return
	var session: Session = context[0]
	var game: Game = context[1]
	if not zone_id.is_empty(): session._enter_zone(zone_id, 1, false)
	t = session.world.terrain
	session.set_physics_process(false); session.world.set_physics_process(false); session.world.set_process(false)
	session.world.vm.instances.clear()
	var hero: GameUnit = session.party_heroes()[0]
	for unit: GameUnit in session.world.units.values():
		unit.process_mode = Node.PROCESS_MODE_DISABLED
	GameData.options.merge({"gfx_sharp_units":1, "gfx_wind":1, "gfx_firelight":1,
		"gfx_torch_glow":1, "gfx_water":1, "gfx_water_reflections":2,
		"character_light":0, "rtx_upscaling":4 if dlss else 0, "render_scale":4}, true)
	game._apply_options()
	game.set_process(false); game.rig.set_process(false); game.direct.set_process(false)
	game.hud.hide(); game.hud.process_mode=Node.PROCESS_MODE_DISABLED
	var diagnostic := camera
	camera = game.rig.camera; camera.make_current(); diagnostic.queue_free()
	game.selected.assign([hero]); game.rig.release()
	hero.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var desired := hero.pos
	var target := desired + Vector2(10, 0)
	if map_name == "zone11" and zone_id.is_empty():
		desired = Vector2(138,174); target = Vector2(145,174)
	if zone_id == "gz14k":
		desired = Vector2(183.5,38.8); target = Vector2(179.9853,43.2999)
	var found := false
	for radius in range(0, 9):
		for angle in 16:
			var at := desired + Vector2.from_angle(float(angle)*TAU/16)*float(radius)*0.5
			if session.world.nav.cell_open(at, hero._classes[2]):
				desired = at; found = true; break
		if found: break
	check(found, "authored first-person site is walkable")
	hero.pos = desired; hero.resync_drawn(); hero._sync_transform(0)
	var end := desired
	var sites: Array[Vector2]=[desired]
	# The brazier's decorative platform can contain a walkable cell that has
	# no traversable exit. Find a nearby open corridor, not a stationary route.
	for radius: float in [2.0,4.0,6.0,8.0]:
		for angle in 16: sites.append(desired+Vector2.from_angle(float(angle)*TAU/16)*radius)
	for site: Vector2 in sites:
		if not session.world.nav.cell_open(site,hero._classes[2]): continue
		hero.pos=site; hero.resync_drawn(); hero._sync_transform(0)
		for distance: float in [6.0,4.0,2.0]:
			for angle in 16:
				var candidate:=site+Vector2.from_angle(float(angle)*TAU/16)*distance
				if session.world.nav.direct_line(hero,candidate): desired=site; end=candidate; break
			if end!=desired: break
		if end!=desired: break
	check(end.distance_to(desired)>1.0, "prepared route follows open authored navigation")
	var heading := (target-desired).angle()
	game.direct._set_view_mode(3); game.direct.heading=heading; game.direct.tilt=-0.85
	game.direct.apply_camera(); Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	get_window().content_scale_mode=Window.CONTENT_SCALE_MODE_VIEWPORT
	get_window().content_scale_size=resolution
	get_window().size=Vector2i(2560,1440)
	get_viewport().scaling_3d_scale=0.5
	if dlss:
		RtxGraphics.apply_upscaling(get_viewport())
		check(RtxGraphics.sr_active(), "DLSS Performance is active")
	var rt: Node=game.get_node("SceneRaytrace")
	check(await ready_scene(rt), "authored first-person scene prepares PT")
	check(rt.stats.get("size",[])==[resolution.x/4,resolution.y/4], "first-person trace matches low/Performance resolution")
	check(hero.model._view_active, "real first-person body and visibility are active")
	if not rt.stats.get("active",false): get_tree().quit(1); return
	var inactive:=0; var mismatch:=0; var max_error:=0.0; var shifted_frames:=0
	var mismatch_examples:=[]
	var inactive_examples:=[]; var in_flight_reads:=0
	var sdk_start:=int(RtxGraphics.bridge().call("get_status").get("dlss_evaluations",0)) if dlss else 0
	for phase: String in ["held-down", "walk-down", "turn-forward", "crouch", "third-person", "first-person-restored"]:
		game.direct._set_view_mode(2 if phase=="third-person" else 3)
		hero.stance=GameUnit.STANCE_KNEEL if phase=="crouch" else GameUnit.STANCE_NONE
		hero.model.act("walk" if phase=="walk-down" else "idle",1,0)
		var resets:=0
		for i in 90:
			if phase=="walk-down":
				hero.pos=desired.lerp(end,float(i)/89); hero.resync_drawn(); hero._sync_transform(0)
			hero.model.player.advance(1.0/30); hero.model.flush_pending_pose()
			game.direct.heading=heading+(float(i)*0.018 if phase=="turn-forward" else 0.0)
			game.direct.tilt=-0.85 if phase in ["held-down","walk-down","crouch"] else -0.12
			game.direct.apply_camera(1.0/30)
			await frames(1)
			# process_frame resumes before SceneRaytrace's priority-101 update.
			# Compare the completed render's scene and presentation, not a
			# previous scene snapshot against this iteration's advanced pose.
			await RenderingServer.frame_post_draw
			var active: bool=rt.stats.get("active",false) and rt.device!=null
			if active and not rt.device.nrd_active:
				var observed: RefCounted=rt.device
				RenderingServer.call_on_render_thread(inspect_device.bind(observed))
				var state: Dictionary=await inspected_device
				if state.closed and observed!=rt.device:
					RenderingServer.call_on_render_thread(inspect_device.bind(rt.device))
					state=await inspected_device
				active=state.nrd and not state.closed
				if active: in_flight_reads+=1
				else: inactive_examples.append({"phase":phase,"frame":i,"device":state,"stats":rt.stats.duplicate(true)})
			if not active: inactive+=1
			if not rt.stats.get("history_reused",false): resets+=1
			if i>=30 and hero.model._view_active and rt._scene!=null:
				var shift: Vector3=hero.model._view_shift
				if shift.length()>0.001: shifted_frames+=1
				for entry: Dictionary in rt._scene.instances:
					var node: Node3D=entry.node.get_ref()
					if is_instance_valid(node) and node is MeshInstance3D and node.layers==EIUnitModel.CLOSE_VIEW_LAYER and (entry.mask&1)!=0:
						var error: float=entry.transform.origin.distance_to(node.global_position+shift)
						max_error=maxf(max_error,error)
						if error>0.0001:
							mismatch+=1
							if mismatch_examples.size()<12:
								mismatch_examples.append({"phase":phase,"frame":i,"node":str(node.get_path()),"shifted":hero.model._view_meshes.has(node),"error":error,"shift":str(shift),"traced":str(entry.transform.origin),"node_position":str(node.global_position)})
			if capture_sequence and i>=40 and i<52:
				await RenderingServer.frame_post_draw
				var frame:=get_viewport().get_texture().get_image()
				frame.resize(1920,1080,Image.INTERPOLATE_LANCZOS)
				frame.save_png(out.path_join("sequence-%s-%02d.png"%[phase,i-40]))
		if phase=="walk-down": check(Vector2(hero.global_position.x,-hero.global_position.z).distance_to(end)<0.01,"animated first-person body traverses the prepared route")
		phase_rows.append({"phase":phase,"frames":90,"history_resets":resets,"stats":rt.stats.duplicate(true),"eye":str(camera.global_position),"body":str(hero.global_position),"shift":str(hero.model._view_shift)})
		await shot(phase)
		print("FIRST_PERSON_PHASE ",JSON.stringify(phase_rows.back()))
	check(inactive==0,"PT and NRD stay active through first-person motion and view transitions")
	check(shifted_frames>0,"motion exercises the visible body's camera-clearance shift")
	check(mismatch==0,"PT receivers follow the presented first-person body (max error %.6f m)"%max_error)
	check(Input.mouse_mode==Input.MOUSE_MODE_VISIBLE,"development cursor remains free")
	var status:Dictionary=RtxGraphics.bridge().call("get_status") if dlss else {}
	if dlss:
		check(int(status.get("dlss_evaluations",0))-sdk_start>=540 and int(status.get("last_error",-1))==0,"DLSS evaluates every motion phase without SDK errors")
	var coverage := {}
	if OS.get_cmdline_user_args().has("--pt-body-coverage"):
		coverage = await body_coverage(game,hero,rt)
	FileAccess.open(out.path_join("first-person-live.json"),FileAccess.WRITE).store_string(JSON.stringify({
		"checks":checks,"failures":failures,"zone":session.zone_id,"phases":phase_rows,"inactive_frames":inactive,"inactive_examples":inactive_examples,"in_flight_reads":in_flight_reads,
		"transform_mismatches":mismatch,"mismatch_examples":mismatch_examples,"max_transform_error":max_error,"shifted_frames":shifted_frames,"dlss":status,"body_coverage":coverage,
		"route_from":str(desired),"route_to":str(end),"route_metres":desired.distance_to(end),
		"note":"Prepared authored-world movement; not a frame-time benchmark or network/input test."
	},"\t"))
	game.queue_free();session.queue_free();await frames(16);TexUpscale.shutdown()
	get_tree().quit(0 if failures.is_empty() else 1)

func body_coverage(game: Game, hero: GameUnit, rt: Node) -> Dictionary:
	game.direct._set_view_mode(3); game.direct.heading=hero.facing; game.direct.tilt=-1.25
	game.direct.apply_camera(); hero.model.player.pause()
	var saved:=[]; var shaders:={}
	for mesh: MeshInstance3D in hero.model._view_meshes:
		var material:=mesh.get_active_material(0) as ShaderMaterial
		if material==null or not material.shader.code.contains("ei_pt_blend"): continue
		var copy:=material.duplicate() as ShaderMaterial
		var key:=material.shader.get_instance_id()
		if not shaders.has(key):
			var shader:=Shader.new()
			shader.code=Gfx._function_tail(material.shader.code.replace("render_mode ","render_mode unshaded, fog_disabled, "),"fragment","ALBEDO=vec3(1.0-ei_pt_blend,ei_pt_blend,1.0-ei_pt_blend);EMISSION=vec3(0);FOG=vec4(0);")
			shaders[key]=shader
		copy.shader=shaders[key]; saved.append([mesh,mesh.material_override]); mesh.material_override=copy
	rt._poll=0; await ready_scene(rt); await frames(30)
	var coverage:=[]
	for i in 4:
		hero.model.player.advance(1.0/30); hero.model.flush_pending_pose()
		game.direct.apply_camera(1.0/30); await frames(2); await RenderingServer.frame_post_draw
		var screen:=get_viewport().get_texture().get_image()
		var matched:=0; var missed:=0
		for y in range(screen.get_height()/3,screen.get_height(),3):
			for x in range(0,screen.get_width(),3):
				var c:=screen.get_pixel(x,y)
				if c.g>c.r+0.15 and c.g>c.b+0.15: matched+=1
				if c.r>c.g+0.15 and c.b>c.g+0.15: missed+=1
		coverage.append({"matched":matched,"missed":missed,"rejected_fraction":float(missed)/maxi(matched+missed,1)})
		if i==3: screen.save_png(out.path_join("first-person-body-coverage.png"))
	for row: Array in saved: row[0].material_override=row[1]
	check(coverage.all(func(row:Dictionary):return row.matched>100 and row.rejected_fraction<0.01),"visible first-person body consistently receives PT lighting")
	return {"frames":coverage}
