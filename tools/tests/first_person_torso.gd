extends "third_person_kbm.gd"
## Native humanoid geometry and rendered local view; no save or network changes.
var variants := []

func geometry_cases() -> void:
	for prototype: String in ["Human Hero", "Human Mercenary Thief"]:
		for smooth: bool in [false, true]:
			for build: Vector3 in [Vector3(.5,.5,.5), Vector3(.1,.2,.8), Vector3(.9,.8,.2)]:
				var m := EIUnitModel.create({"prototype":prototype, "complexion":build, "smooth_joints":smooth})
				add_child(m)
				var label := "%s smooth=%s build=%s" % [prototype, smooth, build]
				check(m._view_torso != null, label + " has a body view")
				var original: ArrayMesh = m._view_torso.mesh
				var before := original.surface_get_arrays(m._view_neck.surface)
				m.set_first_person_view(true)
				var after := m._view_torso.mesh.surface_get_arrays(m._view_neck.surface)
				var old: PackedVector3Array = before[Mesh.ARRAY_VERTEX]
				var now: PackedVector3Array = after[Mesh.ARRAY_VERTEX]
				var changed := 0
				var intact := true
				for i in old.size():
					if old[i] == now[i]: continue
					changed += 1
					intact = intact and i >= m._view_neck.first and i < m._view_neck.first + m._view_neck.count \
						and old[i].y > m._view_neck.collar and is_equal_approx(now[i].y, m._view_neck.collar) \
						and is_equal_approx(old[i].x, now[i].x) and is_equal_approx(old[i].z, now[i].z)
				check(changed > 0 and intact, label + " only lowers the neck; chest and limbs keep original vertices")
				check(original.surface_get_arrays(m._view_neck.surface)[Mesh.ARRAY_VERTEX] == old, label + " preserves source mesh")
				check(_closed_rim(after, old.size(), m._view_neck.collar), label + " closes the neck opening from above")
				var cap_uv: Vector2 = after[Mesh.ARRAY_TEX_UV][-1]
				var cap_intact := true
				for i in range(old.size(), now.size(), 3):
					cap_intact = cap_intact and after[Mesh.ARRAY_TEX_UV][i] == cap_uv \
						and (now[i+1]-now[i]).cross(now[i+2]-now[i]).y < 0.0
				var texture: Texture2D = (m._view_torso.get_active_material(m._view_neck.surface) as ShaderMaterial).get_shader_parameter("albedo_tex")
				var pixels := texture.get_image()
				var sample := Vector2i((cap_uv * Vector2(pixels.get_size())).floor())
				check(cap_intact and pixels.get_pixelv(sample).a > 0.99, label + " cap faces up and samples an opaque atlas region")
				check(m._view_torso.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON, label + " closed torso also casts its own shadow")
				var cached := m._view_torso.mesh
				m.set_first_person_view(false)
				check(m._view_torso.mesh == original and not m._head_hidden, label + " restores third person")
				m.set_first_person_view(true)
				check(m._view_torso.mesh == cached, label + " reuses closed body without rebuilding")
				variants.append({"case":label,"lowered":changed,"added_vertices":now.size()-old.size()})
				m.free()

func _closed_rim(a: Array, original_count: int, collar: float) -> bool:
	var vertices: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	# Garment hems are intentionally open over the closed body. Ray-test the
	# actual neck opening instead of treating every clothing edge as a hole.
	if vertices.size() <= original_count: return false
	for i in range(original_count,vertices.size(),3):
		var mid:Vector3=(vertices[i]+vertices[i+1])*0.5
		for radius:float in [0.0,.25,.5,.9]:
			var from:=vertices[i+2].lerp(mid,radius)+Vector3.UP*.3
			var closed:=false
			for t in range(0,indices.size(),3):
				var hit=Geometry3D.ray_intersects_triangle(from,Vector3.DOWN,vertices[indices[t]],vertices[indices[t+1]],vertices[indices[t+2]])
				if hit!=null and absf(hit.y-collar)<.0001:closed=true;break
			if not closed:return false
	return true

func shot(label: String) -> void:
	await frames(3)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://"+label+".png")

func _ready() -> void:
	mode = "first-person torso"
	GameData.options.merge(GfxDetect.original_look_values(true,{},-1),true)
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0,
		"auto_graphics":0,"control_mode":3,"pad_enabled":0,"confine_mouse":0,"blood":0,"gfx_detailed_heads":1},true)
	geometry_cases()
	if DisplayServer.get_name() != "headless":
		RenderingServer.set_render_loop_enabled(true)
		PadInput.active="kbm";s=Session.new();add_child(s);g=Game.new();g.session=s;s.game=g;add_child(g)
		s.state=CampaignState.new();s.state.ensure_hero(0,"Human Mercenary Thief" if OS.get_cmdline_user_args().has("--female") else "Human Hero")
		await s.enter_zone("gz1g",1,false);await prepare()
		hero.set_process(false);hero.set_physics_process(false);hero.pos=Vector2(69.82051,128);hero.facing=0;hero._sync_transform(0);hero._anim_lock=0
		hero.direct_controlled=true;hero._direct_joints=true;hero.refresh_figure(true)
		g.direct.heading=0;GameData.options.control_mode=3
		hero.model.player.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		for act:String in ["idle","walk","run","attack","cast"]:
			hero.action=act;hero.model.act(act,1,0)
			var clip:=hero.model.player.get_animation(hero.model.player.current_animation)
			for sample:int in [0,2,4,6]:
				hero.model.player.seek(clip.length*sample/8.0,true);hero.model.flush_pending_pose()
				for tilt:float in [0.0,-1.15,-1.45]:
					g.direct.tilt=tilt
					for f in 40:g.direct.apply_camera(1.0/60)
					check(hero.model._view_torso.mesh == hero.model._view_body_closed and hero.model._head_hidden, "%s phase %d pitch %.2f keeps closed torso and hidden head" % [act,sample,tilt])
					if sample==2:await shot("torso-%s-%s" % [act, "level" if tilt==0 else "down" if tilt> -1.4 else "feet"])
		for gait:int in [1,0]:
			hero.restore_gait(gait);hero._anim_lock=0
			for act:String in ["idle","walk"]:
				hero.action=act;hero.model.act(act,1,0)
				var clip:=hero.model.player.get_animation(hero.model.player.current_animation)
				hero.model.player.seek(clip.length*.3,true);hero.model.flush_pending_pose()
				g.direct.tilt=-1.45
				for f in 120:g.direct.apply_camera(1.0/60)
				check(hero.model._view_torso.mesh==hero.model._view_body_closed,"low posture retains closed torso")
				await shot("torso-gait%d-%s" % [gait,act])
		GameData.options.control_mode=2;g.direct.tilt=-0.1;g.direct.apply_camera(1.0/60)
		check(hero.model._view_torso.mesh==hero.model._view_body_original,"switch restores original world torso")
		await shot("torso-third-person")
		g.queue_free();s.queue_free();await frames(10)
	print("FIRST_PERSON_TORSO ", JSON.stringify({"checks":checks,"failures":failures,"variants":variants}))
	TexUpscale.shutdown();get_tree().quit(0 if failures.is_empty() else 1)
