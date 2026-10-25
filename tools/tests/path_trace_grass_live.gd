extends RefCounted
## Same authored first-person view with one lighting component changed at a
## time. Called by the live-location harness after its ordinary scene setup.
func run(a: Node) -> void:
	a.previous_position=a.h.pos
	await a.stage("arrival-held",90)
	a.s.set_physics_process(false); a.s.world.set_physics_process(false); a.s.world.set_process(false)
	for unit: GameUnit in a.s.world.units.values(): unit.process_mode=Node.PROCESS_MODE_DISABLED
	a.g.set_process(false); a.g._update_daylight(false)
	var details: TerrainDetails=a.t.details
	a.previous_position=a.h.pos; a.total_distance=0.0
	details.set_process(false)
	if OS.get_cmdline_user_args().has("--pt-darkness-audit"):
		await darkness_audit(a); return
	if OS.get_cmdline_user_args().has("--pt-grass-contact"):
		await contact_audit(a,details); return
	if OS.get_cmdline_user_args().has("--pt-character-audit"):
		await character_audit(a); return
	if OS.get_cmdline_user_args().has("--pt-scenery-audit"):
		await scenery_audit(a); return
	if OS.get_cmdline_user_args().has("--pt-ground-audit"):
		await ground_audit(a); return
	var materials: Array[ShaderMaterial]=[]
	for material: ShaderMaterial in [details._material,details._cover_material,details._far_grass._material]:
		if material: materials.append(material)
	var original: Array[Shader]=[]
	for material in materials: original.append(material.shader)
	await capture(a,"grass-baseline")
	RenderingServer.global_shader_parameter_set(&"ei_pt_grass_shadows",0.0)
	await capture(a,"grass-shadow-disabled")
	RenderingServer.global_shader_parameter_set(&"ei_pt_grass_shadows",1.0)
	var casters := []
	for node: Node in details.find_children("*","GeometryInstance3D",true,false):
		if node is GeometryInstance3D and node.cast_shadow!=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			casters.append([node,node.cast_shadow]); node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	await capture(a,"grass-casters-disabled")
	for caster: Array in casters: caster[0].cast_shadow=caster[1]
	var sun: DirectionalLight3D=a.g._sun
	print("GRASS_SUN ",sun.light_specular," ",sun.shadow_normal_bias," ",sun.global_transform," nodes=",casters.size())
	sun.shadow_enabled=false
	await capture(a,"grass-all-raster-shadows-disabled")
	sun.shadow_enabled=true
	var marker := sun.light_specular
	sun.light_specular=Gfx.SUN_MARK
	await capture(a,"grass-marked-sun")
	sun.shadow_enabled=false
	await capture(a,"grass-marked-sun-unshadowed")
	sun.shadow_enabled=true
	sun.light_specular=marker
	for mode: String in ["valid","total","sun","indirect"]:
		for i in materials.size():
			var shader := Shader.new()
			var result: String = "vec3(valid ? 0.0 : 1.0,valid ? 1.0 : 0.0,0.0)" if mode=="valid" else {"total":"gi","sun":"v0.rgb","indirect":"max(gi-v0.rgb,vec3(0.0))"}[mode]
			shader.code=Gfx._function_tail(original[i].code.replace("render_mode ","render_mode unshaded, fog_disabled, "),"fragment",
				"\n vec3 gi;vec4 v0,v1;bool valid=ei_rt_ground_sample(gi,v0,v1);ALBEDO="+result+";EMISSION=vec3(0.0);FOG=vec4(0.0);\n")
			materials[i].shader=shader
		await capture(a,"grass-debug-"+mode)
	for i in materials.size(): materials[i].shader=original[i]
	a.check(is_equal_approx(sun.light_specular,Gfx.SUN_MARK),"production desktop sun carries the shader sunlight marker")
	a.check(a.rt.stats.get("active",false),"grass comparison keeps PT active")
	await a.receiver_coverage()
	var land: ShaderMaterial=a.t._land_mat
	var land_shader := land.shader
	var debug_land := Shader.new()
	debug_land.code=Gfx._function_tail(land_shader.code.replace("render_mode ","render_mode unshaded, fog_disabled, "),"fragment","\n EMISSION=vec3(0.0);FOG=vec4(0.0);\n")
	land.shader=debug_land
	await capture(a,"ground-albedo")
	land.shader=land_shader
	GameData.options.pt_mode=0
	await capture(a,"ground-conventional")
	a.check(a.rt.device==null,"conventional lighting restores after the grass comparison")
	FileAccess.open(a.out.path_join("grass-view.json"),FileAccess.WRITE).store_string(JSON.stringify({"camera":str(a.camera.global_transform),"position":str(a.h.pos),"sun":str(sun.global_transform),"grass_casters":casters.size(),"stats":a.rt.stats},"\t"))

func darkness_audit(a: Node) -> void:
	a.h.model.act("walk",1,0);a.h.model.player.pause();a.h.model.player.seek(0.3,true);a.h.model.flush_pending_pose()
	a.g.direct._set_view_mode(3);a.g.direct.tilt=-1.1;a.g.direct.apply_camera()
	a.g.get_node("LocalLighting").set_process(false)
	a.s.world.get_node("ParticleFx").set_process(false);a.t.set_process(false)
	await capture(a,"darkness-pt")
	var rows: Array=a.h.model._view_shadows.duplicate()
	a.h.model._view_shadows.clear()
	for row: Dictionary in rows:row.shadow.hide()
	await capture(a,"darkness-no-body-shadow")
	for row: Dictionary in rows:row.shadow.show();row.reflection.hide()
	await capture(a,"darkness-no-body-gi")
	for row: Dictionary in rows:row.shadow.hide()
	await capture(a,"darkness-no-body-copies")
	a.h.model._view_shadows.assign(rows);a.h.model._update_first_person_shadows()
	GameData.options.pt_mode=0
	await capture(a,"darkness-conventional")
	FileAccess.open(a.out.path_join("darkness-inputs.json"),FileAccess.WRITE).store_string(JSON.stringify({"cave":a.g._sky_cave,"ambient":str(Gfx.ambient),"sun":str(Gfx.sun),"sky":str(Gfx.fog_sky),"body_shift":str(a.h.model._view_shift),"lights":a.rt.stats.get("lights",0)},"\t"))
	GameData.options.pt_mode=1;await a.ready_scene(a.rt)

func capture(a: Node,label: String) -> void:
	await a.frames(30); await RenderingServer.frame_post_draw
	await a.shot(label)
	FileAccess.open(a.out.path_join(label+"-stats.json"),FileAccess.WRITE).store_string(JSON.stringify(a.rt.stats,"\t"))
	print("GRASS_CAPTURE ",label)

func contact_audit(a: Node,details: TerrainDetails) -> void:
	a.g.direct._set_view_mode(3);a.g.direct.tilt=-0.9;a.g.direct.apply_camera()
	a.g.get_node("LocalLighting").set_process(false)
	a.s.world.get_node("ParticleFx").set_process(false);a.t.set_process(false)
	for material: ShaderMaterial in [details._material,details._cover_material,details._far_grass._material]:
		if material:material.set_shader_parameter("breeze",0.0)
	await capture(a,"grass-contact-shadow")
	var casters:=[]
	for node: Node in details.find_children("*","GeometryInstance3D",true,false):
		if node is GeometryInstance3D and node.cast_shadow!=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			casters.append([node,node.cast_shadow]);node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	await capture(a,"grass-contact-without-casters")
	for row: Array in casters:row[0].cast_shadow=row[1]
	await capture(a,"grass-contact-restored")
	a.check(not casters.is_empty(),"authored location contains procedural grass shadow casters")
	a.check(a.rt.stats.get("active",false) and a.rt.device.nrd_active,"grass contact comparison keeps PT and NRD active")

func character_audit(a: Node) -> void:
	a.g.direct._set_view_mode(2)
	if OS.get_cmdline_user_args().has("--pt-character-reference"):
		a.g.direct.zoom=1.8
	a.h.model.act("idle",1,0)
	a.h.model.player.advance(0.1);a.h.model.flush_pending_pose()
	var heading: float=a.h.facing
	for face: String in (["front"] if OS.get_cmdline_user_args().has("--pt-character-reference") else ["back","front"]):
		a.g.direct.heading=heading+(PI if face=="front" else 0.0)
		a.g.direct.tilt=-0.12;a.g.direct.apply_camera()
		await a.ready_scene(a.rt)
		await capture(a,"character-"+face+"-pt")
		if OS.get_cmdline_user_args().has("--pt-character-reference"):
			a.g.get_node("LocalLighting").set_process(false)
			a.s.world.get_node("ParticleFx").set_process(false)
			a.t.set_process(false)
			await capture(a,"character-"+face+"-steady-light")
			GameData.options.q_rt_lighting=2;GameData.options.pt_accumulation=1
			await a.ready_scene(a.rt);await a.frames(120)
			await capture(a,"character-"+face+"-reference")
			a.check(a.rt.stats.get("accumulation_frames",0)>=64,"frozen character reference converges without lighting resets")
			GameData.options.q_rt_lighting=0;GameData.options.pt_accumulation=0
			await a.ready_scene(a.rt)
		var saved := []
		var shaders := {}
		for mesh: MeshInstance3D in a.h.model.find_children("*","MeshInstance3D",true,false):
			if not mesh.is_visible_in_tree() or (mesh.layers&a.camera.cull_mask)==0 or mesh.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY: continue
			var original := mesh.get_active_material(0) as ShaderMaterial
			if original==null or not original.shader.code.contains("ei_pt_blend"): continue
			var material := original.duplicate() as ShaderMaterial
			var key := original.shader.get_instance_id()
			if not shaders.has(key):
				var shader := Shader.new()
				shader.code=Gfx._function_tail(original.shader.code.replace("render_mode ","render_mode unshaded, fog_disabled, "),"fragment","\nALBEDO=vec3(1.0-ei_pt_blend,ei_pt_blend,1.0-ei_pt_blend);EMISSION=vec3(0);FOG=vec4(0);\n")
				shaders[key]=shader
			material.shader=shaders[key];saved.append([mesh,mesh.material_override,original]);mesh.material_override=material
		await capture(a,"character-"+face+"-coverage")
		for row: Array in saved: row[0].material_override=row[1]
		GameData.options.pt_mode=0
		await capture(a,"character-"+face+"-conventional")
		GameData.options.pt_mode=1
		await a.ready_scene(a.rt)
	a.check(a.rt.stats.get("active",false),"character comparison restores PT")

func scenery_audit(a: Node) -> void:
	await capture(a,"scenery-baseline")
	if OS.get_cmdline_user_args().has("--pt-scenery-state"):
		var meshes := []
		for root: Node3D in a.s.world.objects.values():
			for mesh: MeshInstance3D in root.find_children("*","MeshInstance3D",true,false):
				if mesh.global_position.distance_to(a.camera.global_position)<80: meshes.append(mesh)
		for mesh: MeshInstance3D in meshes: RenderingServer.instance_set_visible(mesh.get_instance(),true)
		await capture(a,"scenery-visible-only")
		for mesh: MeshInstance3D in meshes: RenderingServer.instance_set_transform(mesh.get_instance(),mesh.global_transform)
		await capture(a,"scenery-transform-only")
		await a.receiver_coverage()
		return
	var saved := []
	var rows := []
	var shaders := {}
	var white := StandardMaterial3D.new()
	white.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	white.albedo_color=Color(0.8,0.6,0.2)
	white.cull_mode=BaseMaterial3D.CULL_DISABLED
	for root: Node3D in a.s.world.objects.values():
		for mesh: MeshInstance3D in root.find_children("*","MeshInstance3D",true,false):
			if mesh.global_position.distance_to(a.camera.global_position)>80: continue
			var mat := mesh.get_active_material(0)
			var params := {}
			if mat is ShaderMaterial:
				for key: String in ["albedo_tex","ei_material_diffuse","cam_fade","surface_profile"]: params[key]=str(mat.get_shader_parameter(key))
				if not shaders.has(mat.shader.get_instance_id()):
					shaders[mat.shader.get_instance_id()]=true
					FileAccess.open(a.out.path_join("scenery-shader-%s.txt"%mat.shader.get_instance_id()),FileAccess.WRITE).store_string(mat.shader.code)
			rows.append({"path":str(mesh.get_path()),"object":root.get_meta("ei",{}),"visible":mesh.is_visible_in_tree(),"layers":mesh.layers,"transform":str(mesh.global_transform),"aabb":str(mesh.get_aabb()),"params":params,"shader":mat.shader.get_instance_id() if mat is ShaderMaterial else 0,"shadow":mesh.cast_shadow})
			saved.append([mesh,mesh.material_override]);mesh.material_override=white
	FileAccess.open(a.out.path_join("scenery.json"),FileAccess.WRITE).store_string(JSON.stringify({"camera_mask":a.camera.cull_mask,"rows":rows},"\t"))
	await capture(a,"scenery-basic-material")
	for row: Array in saved: row[0].material_override=row[1]
	for row: Array in saved:
		var mesh: MeshInstance3D=row[0]
		mesh.physics_interpolation_mode=Node.PHYSICS_INTERPOLATION_MODE_OFF
		mesh.reset_physics_interpolation();mesh.force_update_transform()
	await capture(a,"scenery-force-transform")
	for row: Array in saved:
		var mesh: MeshInstance3D=row[0]
		RenderingServer.instance_set_transform(mesh.get_instance(),mesh.global_transform)
		RenderingServer.instance_set_visible(mesh.get_instance(),true)
	await capture(a,"scenery-force-rs-visible")
	for row: Array in saved:
		var mesh: MeshInstance3D=row[0]
		mesh.custom_aabb=AABB(Vector3(-500,-500,-500),Vector3(1000,1000,1000))
		mesh.ignore_occlusion_culling=true
	await capture(a,"scenery-force-bounds")
	for row: Array in saved:
		var mesh: MeshInstance3D=row[0]
		var replacement := ArrayMesh.new()
		for surface in mesh.mesh.get_surface_count(): replacement.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,mesh.mesh.surface_get_arrays(surface))
		mesh.mesh=replacement
	await capture(a,"scenery-rebuilt-meshes")
	a.g.direct._set_view_mode(2);a.g.direct.apply_camera()
	await capture(a,"scenery-third-person")

func ground_audit(a: Node) -> void:
	await capture(a,"ground-baseline")
	var guide: Image=a.rt.device.guide.get_image()
	FileAccess.open(a.out.path_join("ground-guide.bin"),FileAccess.WRITE).store_buffer(guide.get_data())
	FileAccess.open(a.out.path_join("ground-vertices.bin"),FileAccess.WRITE).store_buffer(a.rt._scene.vertices.to_byte_array())
	var projection: Projection=a.camera.get_camera_projection()
	var transform: Transform3D=a.camera.get_camera_transform()
	var matrices := []
	for matrix: Projection in [projection,Projection(transform)]:
		var cols := []
		for col in 4: cols.append([matrix[col].x,matrix[col].y,matrix[col].z,matrix[col].w])
		matrices.append(cols)
	var geometries := []
	for geo: Dictionary in a.rt._scene.geometries:
		if geo.terrain: geometries.append({"offset":geo.offset,"count":geo.count})
	FileAccess.open(a.out.path_join("ground-guide.json"),FileAccess.WRITE).store_string(JSON.stringify({"format":guide.get_format(),"width":guide.get_width(),"height":guide.get_height(),"matrices":matrices,"geometries":geometries,"eye":str(transform),"center":str(a.rt._center),"stats":a.rt.stats}))
	var saved := []
	for sector: Node in a.t.get_children():
		if not sector is EITerrainSector: continue
		for mesh: MeshInstance3D in sector._parts:
			var material := mesh.get_active_material(0) as ShaderMaterial
			if material: saved.append([mesh,mesh.get_surface_override_material(0),material])
	for mode: String in ["original","no-geometry","reason","deltas","albedo"]:
		var shaders := {}
		for row: Array in saved:
			var material: ShaderMaterial=row[2].duplicate()
			var key := material.shader.get_instance_id()
			if not shaders.has(key):
				var shader := Shader.new()
				var code := material.shader.code.replace("render_mode ","render_mode unshaded, fog_disabled, ")
				if mode=="no-geometry":
					code=code.replace("||dot(normal,guide.xyz)<0.45","")
					code=code.replace("abs(dot(delta,plane))>max(0.025,depth*0.00075)","false")
					code=code.replace("length(delta)>max(0.1,footprint*2.5)","false").replace("length(delta)>max(0.1,footprint*3.5)","false")
				var ending := "\nEMISSION=vec3(0.0);FOG=vec4(0.0);\n"
				if mode!="albedo": ending+="ALBEDO=ei_pt_blend>0.9?vec3(0,1,0):vec3(1,0,0);\n"
				if mode in ["reason","deltas"]: ending+="""
    vec3 pworld=(INV_VIEW_MATRIX*vec4(VERTEX,1)).xyz;
    vec4 pclip=ei_rt_view_projection*vec4(pworld,1);
    vec2 puv=vec2(pclip.x,-pclip.y)/pclip.w*0.5+0.5;
    ivec2 psize=textureSize(ei_rt_guide,0);
    ivec2 pp=clamp(ivec2(puv*vec2(psize)),ivec2(0),psize-1);
    vec4 pguide=texelFetch(ei_rt_guide,pp,0);
    vec3 pdelta=ei_rt_position(pp,pguide.w,psize)-pworld;
    ALBEDO=ei_pt_blend>0.9?vec3(0,1,0):vec3(min(length(pdelta),1.0),0,0);
    if(pguide.w<=0.0)ALBEDO=vec3(0,1,1);
    if(distance(pworld,ei_rt_center.xyz)>=ei_rt_state.w)ALBEDO=vec3(1,1,0);
    if(any(lessThan(puv,vec2(0)))||any(greaterThanEqual(puv,vec2(1))))ALBEDO=vec3(0,0,1);
"""
				if mode=="deltas":
					ending+="ALBEDO=clamp(pdelta*0.05+vec3(0.5),vec3(0),vec3(1));\n"
				shader.code=Gfx._function_tail(code,"fragment",ending)
				shaders[key]=shader
			material.shader=shaders[key]
			row[0].set_surface_override_material(0,material)
		await capture(a,"ground-"+mode)
	for row: Array in saved: row[0].set_surface_override_material(0,row[1])
