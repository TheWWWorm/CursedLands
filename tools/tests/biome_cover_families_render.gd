extends Node
## Same authored scene before/after the family masks; all scenery is loaded.
const Cover = preload("res://src/game/fx/biome_cover.gd")
const Geometry = preload("res://src/game/fx/biome_cover_mesh.gd")
var checks := 0
var failures := 0
var rows := []

func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1; printerr("FAIL ",label)

func frames(n := 40) -> void:
	for i in n: await RenderingServer.frame_post_draw; await get_tree().process_frame

func delta(a: Image,b: Image) -> int:
	a.convert(Image.FORMAT_RGBA8); b.convert(Image.FORMAT_RGBA8)
	var aa:=a.get_data();var bb:=b.get_data();var count:=0
	for i in range(0,aa.size(),4): count+=int(aa[i]!=bb[i] or aa[i+1]!=bb[i+1] or aa[i+2]!=bb[i+2])
	return count

func camera_clear(d: TerrainDetails,focus: Vector3,offset: Vector3) -> bool:
	var from:=focus+Vector3(0,0.4,0);var to:=focus+offset
	for i in 20:
		var point:=from.lerp(to,float(i)/19.0);var p:=Vector2(point.x,-point.z);var hit:=d.surface_sample(p)
		if hit.is_empty() or float(hit.height)>point.y-0.15:return false
		for record: Dictionary in d._scenery.get(Vector2i((p/8).floor()),[]):
			var inverse: Transform3D=record.inverse
			if (record.box as AABB).intersects_segment(inverse*from,inverse*to)!=null:return false
	return true

func choose(d: TerrainDetails,kind: int,added: bool) -> Dictionary:
	var field: Variant=d._cover_field; var metadata: Dictionary=field.families
	var candidates := [Vector2(244.2584,10.97599),Vector2(212.2899,36.26086)] if not added else [Vector2(241.9519,71.57383),Vector2(422.1096,159.4134),Vector2(424.4344,155.8115),Vector2(411.3942,169.1389)]
	for p: Vector2 in candidates:
		var key:=Vector2i((p/8).floor());var boxes: Array=d._scenery.get(key,[]);var trees: Array=d._trees.get(key,[])
		field.families={};var before: Array=field.records(key,boxes,trees)
		field.families=metadata;var after: Array=field.records(key,boxes,trees)
		for r: Dictionary in (after if added else before):
			if int(r.kind)!=kind or r.p.distance_to(p)>0.002 or r in (before if added else after):continue
			for offset: Vector3 in [Vector3(2.7,2.8,3.5),Vector3(-2.7,2.8,3.5),Vector3(2.7,2.8,-3.5),Vector3(-2.7,2.8,-3.5)]:
				if camera_clear(d,Vector3(r.p.x,r.height,-r.p.y),offset):
					r=r.duplicate();r["camera_offset"]=offset;return r
	return {}

func build(d: TerrainDetails,p: Vector2,kind: int,metadata: bool) -> int:
	d._clear_grass();d.prepare_grass();d.set_process(false)
	if not metadata:d._cover_field.families.clear()
	var focus:=Vector2i((p/8).floor());d._focus=focus;var count:=0
	for y in range(focus.y-1,focus.y+2):
		for x in range(focus.x-1,focus.x+2):
			var key:=Vector2i(x,y);var data:=d.instances(key)
			data.cover.records=data.cover.records.filter(func(r: Dictionary):return int(r.kind)==kind)
			data.cover.arrays=Geometry.new().build(data.cover.records,key,d._cover_field.sea if not d._cover_field.sea.tiles.is_empty() else null)
			count+=data.cover.records.size();d._install_chunk(key,data)
	var at:=Vector3(p.x,d.terrain.height_at(p.x,p.y),-p.y)
	d._material.set_shader_parameter("view_position",at);d._cover_material.set_shader_parameter("view_position",at)
	return count

func scene(id: String,kind: int,added: bool) -> void:
	var view:=SubViewport.new();view.size=Vector2i(800,600);view.own_world_3d=true;view.physics_interpolation_mode=Node.PHYSICS_INTERPOLATION_MODE_OFF;view.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(view)
	var world:=GameWorld.new();view.add_child(world);world.set_process(false);world.set_physics_process(false);world.zone=CampaignMap.load_from(GameData.texts).zone(id)
	var map:=EIMapScene.load_map(world.zone.mpr,world.zone.get("mob",""),false);world.add_child(map);world.map=map;world.terrain=map.terrain
	var t:=map.terrain;t.set_process(false);var d:=t.details;d.set_process(false);d.prepare_grass()
	var chosen:=choose(d,kind,added);check(not chosen.is_empty(),"changed placement survives actual scenery exclusions "+id)
	if chosen.is_empty():view.free();return
	var p: Vector2=chosen.p;var focus:=Vector3(p.x,chosen.height,-p.y)
	var camera:=Camera3D.new();view.add_child(camera);camera.position=focus+chosen.camera_offset;camera.look_at(focus);camera.current=true
	var env:=WorldEnvironment.new();env.environment=Environment.new();Gfx.setup_original_env(env.environment);env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color(0.13,0.20,0.28);view.add_child(env)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-40,-35,0);sun.shadow_enabled=true;view.add_child(sun)
	Gfx.set_light(Color(0.5,0.5,0.5),Color(0.75,0.75,0.75));Gfx.set_foliage_wind(false)
	RenderingServer.global_shader_parameter_set(&"ei_sun_dir",sun.global_basis.z.normalized());RenderingServer.global_shader_parameter_set(&"ei_border",Vector4.ZERO);RenderingServer.global_shader_parameter_set(&"ei_fog",Vector3(100,180,0))
	var before_count:=build(d,p,kind,false);await frames(160);var before:=view.get_texture().get_image();before.save_png("user://families-"+id+"-before.png")
	var after_count:=build(d,p,kind,true);await frames(160);var after:=view.get_texture().get_image();after.save_png("user://families-"+id+"-after.png")
	var changed:=delta(before,after);check(changed>0,"metadata changes visible authored cover "+id)
	check(after_count>before_count if added else after_count<before_count,"expected direction of placement change "+id)
	build(d,p,kind,false);await frames(160);var restored:=view.get_texture().get_image();restored.save_png("user://families-"+id+"-restored.png")
	check(delta(before,restored)==0,"removing family rules exactly restores the same scene "+id)
	rows.append({"case":"render","zone":id,"kind":kind,"chosen":chosen,"before_records":before_count,"after_records":after_count,"changed_pixels":changed,"restoration_pixels":delta(before,restored)})
	view.free();await frames()

func _ready() -> void:
	for option in ["gfx_hd_textures","gfx_terrain","gfx_soft_ground","gfx_ground_contact","gfx_grass","gfx_vegetation_interaction","gfx_wind","gfx_water","gfx_water_interaction","gfx_water_caustics","gfx_volumetric","gfx_ssao","gfx_bloom","confine_mouse","vsync"]:GameData.options[option]=0
	GameData.options["gfx_biome_cover"]=1;Gfx.ensure_globals();Engine.time_scale=0;Engine.max_fps=120;DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true);Input.mouse_mode=Input.MOUSE_MODE_VISIBLE;RenderingServer.set_render_loop_enabled(true)
	await scene("gz1g",Cover.Kind.FLOWER,false);await scene("gz7g",Cover.Kind.SHELL,true)
	TexUpscale.shutdown();await frames();FileAccess.open("user://biome-cover-families-render.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"rows":rows},"\t"));print("COVER_FAMILIES_RENDER checks=",checks," failures=",failures);get_tree().quit(1 if failures else 0)
