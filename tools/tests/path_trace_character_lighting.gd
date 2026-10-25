extends RefCounted
## Freeze the actual rainy traversal pose, then separate the original cloth
## texture, traced irradiance and glossy lobe from reconstruction artifacts.
var audit: Node
var materials := []
var original_poll := 0.0

func capture(label: String) -> void:
	await audit.frames(36);await RenderingServer.frame_post_draw
	await audit.shot(label)
	FileAccess.open(audit.out.path_join(label+"-stats.json"),FileAccess.WRITE).store_string(JSON.stringify(audit.rt.stats,"\t"))

func debug_material(mode: String) -> void:
	# Diagnostic overrides are not gameplay material edits. Do not invalidate
	# the scene under inspection (or continually cancel its replacement build).
	original_poll=audit.rt._poll;audit.rt._poll=1000000.0
	for row: Array in materials:
		var material: ShaderMaterial=row[1].duplicate()
		var shader:=Shader.new()
		var tail:="\nEMISSION=vec3(0.0);FOG=vec4(0.0);\n"
		if mode!="albedo":
			tail+="vec3 world=(INV_VIEW_MATRIX*vec4(VERTEX,1.0)).xyz;vec3 normal=normalize((INV_VIEW_MATRIX*vec4(NORMAL,0.0)).xyz);vec3 gi;vec4 a,b;bool matched=ei_rt_sample_surface(world,normal,ei_surface.yz,gi,a,b);\n"
			tail+="ALBEDO="+{"diffuse":"gi","glossy":"a.rgb","coverage":"vec3(0.0,1.0,0.0)"}[mode]+";if(!matched)ALBEDO=vec3(1.0,0.0,1.0);\n"
		shader.code=Gfx._function_tail(row[1].shader.code.replace("render_mode ","render_mode unshaded, fog_disabled, "),"fragment",tail)
		material.shader=shader;row[0].material_override=material

func restore_materials() -> void:
	for row: Array in materials:row[0].material_override=row[2]
	audit.rt._poll=original_poll

func coverage(label: String) -> void:
	debug_material("coverage");await capture(label)
	var image: Image=audit.get_viewport().get_texture().get_image()
	var matched:=0;var missing:=0
	var bounds:=Rect2()
	for row: Array in materials:
		var mesh: MeshInstance3D=row[0]
		var box:=mesh.get_aabb()
		for i in 8:
			var p: Vector2=audit.camera.unproject_position(mesh.global_transform*box.get_endpoint(i))
			bounds=Rect2(p,Vector2.ONE) if bounds.size==Vector2.ZERO else bounds.expand(p)
	var roi:=Rect2i(bounds.grow(2.0)).intersection(Rect2i(Vector2i.ZERO,image.get_size()))
	for y in range(roi.position.y,roi.end.y):
		for x in range(roi.position.x,roi.end.x):
			var p:=image.get_pixel(x,y)
			# The actual filmic colour grading mixes channels. Test dominant
			# diagnostic colour inside the projected actor, excluding HUD icons.
			if p.g>0.5 and p.g>p.r*1.25 and p.g>p.b*1.25:matched+=1
			if minf(p.r,p.b)>0.5 and p.r>p.g*1.25 and p.b>p.g*1.25:missing+=1
	audit.check(matched>200 and missing<matched*0.02,"rear character PT receiver coverage: %s matched=%s missing=%s"%[label,matched,missing])
	restore_materials()

func run(a: Node) -> void:
	audit=a
	a.s.set_physics_process(false);a.s.world.set_physics_process(false);a.s.world.set_process(false)
	for unit: GameUnit in a.s.world.units.values():unit.process_mode=Node.PROCESS_MODE_DISABLED
	a.g.set_process(false);a.g._update_daylight(false)
	a.g.get_node("LocalLighting").set_process(false)
	a.s.world.get_node("ParticleFx").set_process(false);a.t.set_process(false);a.t.details.set_process(false)
	await capture("back-live-low")
	var torso: MeshInstance3D=a.h.model._view_torso
	var receivers: Array=a.rt._scene.instances.filter(func(e):return e.node.get_ref()==torso and e.mesh==torso.mesh and (e.mask&1)!=0)
	a.check(receivers.size()==torso.mesh.get_surface_count(),"restored third-person torso receives PT before any pending world rebuild")
	a.check(await a.ready_scene(a.rt),"low-quality rear scene settles before diagnostic overrides")
	var metadata:=[]
	for mesh: MeshInstance3D in a.h.model.find_children("*","MeshInstance3D",true,false):
		if not mesh.is_visible_in_tree() or (mesh.layers&a.camera.cull_mask)==0 or mesh.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:continue
		var material:=mesh.get_active_material(0) as ShaderMaterial
		if material==null or not material.shader.code.contains("ei_pt_blend"):continue
		materials.append([mesh,material,mesh.material_override])
		metadata.append({"mesh":str(mesh.get_path()),"transform":str(mesh.global_transform),"surface":str(material.get_shader_parameter("ei_surface"))})
	a.check(not materials.is_empty(),"back audit finds original lit character materials")
	for mode: String in ["albedo","diffuse","glossy"]:
		debug_material(mode);await capture("back-low-"+mode);restore_materials()
	await coverage("back-low-coverage")
	GameData.options.q_rt_lighting=2;GameData.options.pt_accumulation=1
	await a.ready_scene(a.rt);await a.frames(160)
	await capture("back-reference")
	a.check(a.rt.stats.get("accumulation_frames",0)>=128,"back lighting reference converges in the frozen rainy scene")
	for mode: String in ["diffuse","glossy"]:
		debug_material(mode);await capture("back-reference-"+mode);restore_materials()
	await coverage("back-reference-coverage")
	GameData.options.pt_mode=0;await capture("back-conventional")
	FileAccess.open(a.out.path_join("back-lighting.json"),FileAccess.WRITE).store_string(JSON.stringify({"materials":metadata,"camera":str(a.camera.global_transform),"position":str(a.h.pos),"ambient":str(Gfx.ambient),"sun":str(Gfx.sun),"sky":str(Gfx.fog_sky)},"\t"))
	GameData.options.pt_mode=1;GameData.options.q_rt_lighting=0;GameData.options.pt_accumulation=0
	await a.ready_scene(a.rt)
	a.check(a.rt.stats.get("active",false) and a.rt.device.nrd_active,"back diagnostic restores ordinary PT and NRD")
