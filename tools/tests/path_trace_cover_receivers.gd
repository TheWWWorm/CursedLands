extends "res://tools/tests/scene_raytrace_device.gd"
## Production grass, pebble, mushroom and fern geometry beside a thin wall edge.
## Controlled guide images isolate receiver lookup from PT sampling and RR.
const Receiver = preload("res://src/game/fx/scene_raytrace_shader.gd")
const Cover = preload("res://src/game/fx/biome_cover.gd")
const Geometry = preload("res://src/game/fx/biome_cover_mesh.gd")
const Regions = preload("res://src/game/fx/biome_cover_regions.gd")
const OUTPUT_SIZE := Vector2i(1280,720)
const TRACE_SIZE := Vector2i(640,360)
const ROOT := Vector3(0,0.008,0)
var guide_texture: ImageTexture
var light_texture: ImageTexture
var original_guide: Image
var receiver_material: ShaderMaterial
var receiver_mask := PackedVector2Array()
var observations := []
var geometry_cases := []

func picture() -> Image:
	await frames(8);await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image()

func lookup_delta(a: Image,b: Image) -> Dictionary:
	var peak:=0.0;var rejected:=0
	for p: Vector2 in receiver_mask:
		var x:=Vector2i(p);var aa:=a.get_pixelv(x);var bb:=b.get_pixelv(x)
		peak=maxf(peak,maxf(absf(aa.r-bb.r),maxf(absf(aa.g-bb.g),absf(aa.b-bb.b))))
		if bb.r>0.7 and bb.b>0.7 and bb.g<0.1:rejected+=1
	return {"peak":peak,"rejected":rejected,"pixels":receiver_mask.size()}

func set_guides(guide: Image,colour: Color) -> void:
	guide_texture.update(guide)
	var light:=Image.create(TRACE_SIZE.x,TRACE_SIZE.y,false,Image.FORMAT_RGBAF)
	light.fill(colour);light_texture.update(light)

func projected_root() -> Vector2:
	return camera.unproject_position(ROOT)/Vector2(OUTPUT_SIZE)*Vector2(TRACE_SIZE)-Vector2(0.5,0.5)

func blocked_root(shift: int) -> Image:
	var guide: Image=original_guide.duplicate()
	var base:=Vector2i(projected_root().floor())
	# Five rejected taps around the four bilinear taps model a wall's edge
	# moving by one trace texel. Every retained ring sample is actual ground.
	for y in range(-1,2):
		for x in range(-1+shift,2+shift):
			guide.set_pixelv(base+Vector2i(x,y),Color(0,0,1,1.0))
	return guide

func make_case(family: String) -> GeometryInstance3D:
	if family=="grass":
		# Grass uses a real MultiMesh instance origin, not the cover UV root.
		var mesh:=TerrainDetails.blade_mesh()
		var arrays:=mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		check(vertices.size()==TerrainDetails.BLADES*TerrainDetails.BLADE_ROWS*2,"fixture uses every production curved grass blade")
		var multi:=MultiMesh.new();multi.transform_format=MultiMesh.TRANSFORM_3D
		multi.use_colors=true;multi.use_custom_data=true;multi.mesh=mesh;multi.instance_count=1
		multi.set_instance_transform(0,Transform3D(Basis.IDENTITY,ROOT))
		multi.set_instance_color(0,Color.WHITE);multi.set_instance_custom_data(0,Color(.25,14,.08,1))
		var tallest:=0.0
		for p: Vector3 in vertices:tallest=maxf(tallest,p.y)
		check(multi.get_instance_transform(0).origin==ROOT and tallest>.5,"grass has its real planted instance root below raised blade tips")
		var object:=MultiMeshInstance3D.new();object.multimesh=multi;object.material_override=receiver_material
		geometry_cases.append({"family":family,"vertices":vertices.size(),"root_layout":"instance origin","height":tallest})
		return object
	var kind: int={"mushroom":Regions.Kind.MUSHROOM,"stone":Cover.Kind.STONE,"fern":Regions.Kind.FERN}[family]
	var records: Array[Dictionary]=[{"kind":kind,"p":Vector2.ZERO,"height":0.0,
		"normal":Vector3.UP,"colour":Color.WHITE,"angle":0.4,"scale":0.8,"seed":0.25,"regional_material":3 if family=="mushroom" else 0}]
	var geometry:=Geometry.new();var arrays:=geometry.build(records,Vector2i.ZERO,null,RefCounted.new())
	var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	var colours: PackedColorArray=arrays[Mesh.ARRAY_COLOR]
	if family=="mushroom":
		check(vertices.size()>200,"fixture uses production mushroom stems and caps")
		check(geometry.lods().is_empty() and colours[0].a==0.0,"mushroom geometry is rigid and has no thinning LOD")
	elif family=="stone":
		var art: PackedFloat32Array=arrays[Mesh.ARRAY_CUSTOM2]
		check(geometry.has_stones and vertices.size()>100 and art.size()==vertices.size()*4 and art[3]<-.5,"fixture uses production textured pebble geometry")
		check(not geometry.lods().is_empty() and colours[0].a==0.0,"stone geometry is rigid and retains its production curvature LOD")
	else:
		check(vertices.size()>100 and colours[0].a==1.0,"fixture uses production flexible fern stems and leaves")
		var roots: PackedVector2Array=arrays[Mesh.ARRAY_TEX_UV2]
		var uv: PackedVector2Array=arrays[Mesh.ARRAY_TEX_UV]
		var planted:=true
		for i in vertices.size():planted=planted and roots[i]==Vector2.ZERO and is_equal_approx(uv[i].x,ROOT.y)
		check(planted,"raised fern leaves retain the cover family's planted-root attributes")
	var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[],geometry.lods(),Geometry.FORMAT)
	var object:=MeshInstance3D.new();object.mesh=mesh;object.material_override=receiver_material
	geometry_cases.append({"family":family,"vertices":vertices.size(),"root_layout":"UV height and UV2 XZ","lods":geometry.lods().size()})
	return object

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--audit-out="):out=arg.trim_prefix("--audit-out=")
	DirAccess.make_dir_recursive_absolute(out);Gfx.ensure_globals()
	GameData.options.merge({"rtx_upscaling":0,"fsr_upscaling":0,"q_aa":0,"render_scale":4,"gfx_cloud_shadows":0},true)
	GameData.resolution_size="1280x720";GameData.options.display_mode=0
	GameData.options.resolution=GameData.resolutions().find(OUTPUT_SIZE)
	GameData._apply_window();GameData._window_gen+=1
	get_window().borderless=true;get_window().size=OUTPUT_SIZE
	var env:=WorldEnvironment.new();env.environment=Environment.new()
	env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color.BLACK
	env.environment.tonemap_mode=Environment.TONE_MAPPER_LINEAR;add_child(env)
	camera=Camera3D.new();add_child(camera);camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=0.65;camera.position=Vector3(0,1.2,2);camera.look_at(Vector3(0,0.10,0));camera.current=true
	receiver_material=ShaderMaterial.new();receiver_material.shader=Shader.new()
	receiver_material.shader.code="shader_type spatial;\n#define EI_GRASS_LIGHT\nrender_mode unshaded,cull_disabled,fog_disabled;\nconst vec3 ei_ambient=vec3(0.0);\nvec3 ei_lin(vec3 c){return c;}\n"+Receiver.COMMON+"""
uniform bool coverage=false;
uniform bool grass_root=false;
void vertex(){
    vec3 root=grass_root?vec3(0.0):vec3(UV2.x,UV.x,UV2.y);
    ei_rt_ground=(MODEL_MATRIX*vec4(root,1.0)).xyz;
}
void fragment(){
    vec3 gi;vec4 a,b;
    bool valid=ei_rt_ground_sample(ei_rt_view_projection,ei_rt_inverse_view_projection,gi,a,b);
    ALBEDO=coverage?vec3(1.0):(valid?gi:vec3(1.0,0.0,1.0));
}
"""
	await frames(12);get_window().size=OUTPUT_SIZE;await frames(4)
	check(get_viewport().get_visible_rect().size==Vector2(OUTPUT_SIZE) and not get_tree().root.use_taa \
		and is_equal_approx(get_tree().root.scaling_3d_scale,1.0),"receiver fixture uses calibrated native output")
	for family in ["mushroom","grass","stone","fern"]:await exercise_family(family)
	RenderingServer.global_shader_parameter_set(&"ei_rt_state",Vector4.ZERO)
	RenderingServer.global_shader_parameter_set(&"ei_pt_active",0.0)
	RenderingServer.global_shader_parameter_set(&"ei_pt_grass_shadows",1.0)
	for key in [&"ei_rt_gi",&"ei_rt_guide",&"ei_rt_shadow0",&"ei_rt_shadow1",&"ei_pt_direct_sun"]:
		RenderingServer.global_shader_parameter_set(key,null)
	FileAccess.open(out.path_join("path-cover-receivers.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"geometry":geometry_cases,"observations":observations,
		"scope":"Planted-root lookup shared by grass and all BiomeCover species. Real instance/UV layouts and representative rigid, textured and flexible meshes. Terrain mounds/contact decals and RR guide/composite matching have separate coverage."},"\t"))
	camera.queue_free();env.queue_free();await frames(8);finish()

func exercise_family(family: String) -> void:
	var object:=make_case(family);add_child(object)
	# Retain the original mushroom/stone view; the taller actual grass mesh
	# needs enough room for its complete curved blades, without scaling them.
	camera.size=1.1 if family=="grass" else .65
	camera.look_at(Vector3(0,.24 if family=="grass" else .10,0))
	receiver_material.set_shader_parameter("grass_root",family=="grass")
	var view:=Projection(camera.global_transform.affine_inverse());var vp:=camera.get_camera_projection()*view
	for row in [[&"ei_rt_inverse_view_projection",vp.inverse()],[&"ei_rt_view_projection",vp],[&"ei_rt_view",view],
		[&"ei_rt_eye",camera.position],[&"ei_rt_center",Vector4.ZERO],[&"ei_rt_state",Vector4(1,1,1,72)],
		[&"ei_pt_active",1.0],[&"ei_pt_rr_active",0.0],[&"ei_pt_grass_shadows",0.0]]:
		RenderingServer.global_shader_parameter_set(row[0],row[1])
	original_guide=Image.create(TRACE_SIZE.x,TRACE_SIZE.y,false,Image.FORMAT_RGBAF)
	for y in TRACE_SIZE.y:
		for x in TRACE_SIZE.x:
			var screen:=Vector2(x+0.5,y+0.5)*2
			var ray:=camera.project_ray_normal(screen);var eye:=camera.project_ray_origin(screen)
			var hit:=eye+ray*(-eye.y/ray.y);var depth:=-(camera.global_transform.affine_inverse()*hit).z
			original_guide.set_pixel(x,y,Color(0,1,0,depth))
	guide_texture=ImageTexture.create_from_image(original_guide)
	light_texture=ImageTexture.create_from_image(original_guide)
	RenderingServer.global_shader_parameter_set(&"ei_rt_guide",guide_texture)
	for key in [&"ei_rt_gi",&"ei_rt_shadow0",&"ei_rt_shadow1",&"ei_pt_direct_sun"]:
		RenderingServer.global_shader_parameter_set(key,light_texture)
	receiver_mask.clear()
	receiver_material.set_shader_parameter("coverage",true)
	var mask:=await picture()
	for y in OUTPUT_SIZE.y:
		for x in OUTPUT_SIZE.x:
			var c:=mask.get_pixel(x,y)
			if c.r>0.95 and c.g>0.95 and c.b>0.95:receiver_mask.append(Vector2(x,y))
	check(receiver_mask.size()>500,"visible "+family+" pixels define a nonempty comparison mask")
	receiver_material.set_shader_parameter("coverage",false)
	for colour: Color in [Color(0.04,0.6,0.08,1),Color(0.002,0.025,0.004,1)]:
		var label:="bright" if colour.g>0.1 else "dark"
		set_guides(original_guide,colour);var reference:=await picture()
		var clear:=lookup_delta(reference,reference)
		check(clear.rejected==0,label+" ground illuminates the complete "+family)
		var previous:=reference
		for shift in 2:
			set_guides(blocked_root(shift),colour);var current:=await picture()
			var delta:=lookup_delta(reference,current)
			var temporal:=lookup_delta(previous,current)
			check(delta.rejected==0 and delta.peak<0.02 and temporal.peak<0.02,
				"%s %s lighting survives wall-edge shift %d: %s"%[label,family,shift,delta])
			observations.append({"family":family,"case":label,"shift":shift,"delta":delta,"temporal":temporal})
			if shift==0:current.save_png(out.path_join(("cover" if family=="mushroom" else family)+"-wall-"+label+".png"))
			previous=current
		# A visible neighbor must still be physically compatible. An elevated
		# platform and a remote floor cannot provide light through a cave wall.
		for incompatible in ["wall","height","distance"]:
			var guide: Image=original_guide.duplicate()
			for y in TRACE_SIZE.y:
				for x in TRACE_SIZE.x:
					var value:=guide.get_pixel(x,y)
					if incompatible=="wall":value=Color(0,0,1,1.0)
					elif incompatible=="height":value.a+=0.3
					else:value.a+=2.0
					guide.set_pixel(x,y,value)
			set_guides(guide,colour);var current:=await picture()
			var delta:=lookup_delta(reference,current)
			check(delta.rejected==receiver_mask.size(),label+" "+family+" rejects incompatible "+incompatible+" guide")
			observations.append({"family":family,"case":label,"guard":incompatible,"delta":delta})
	set_guides(original_guide,Color(0.04,0.6,0.08,1));var restored:=await picture()
	check(lookup_delta(restored,restored).rejected==0,("receiver" if family=="mushroom" else family+" receiver")+" recovers after all incompatible guides are replaced")
	object.queue_free();await frames(2)
