extends "res://tools/tests/path_trace_device.gd"
## Controlled, native RR/NRD comparison of unchanged production detail meshes.
## Run through the ordinary isolated native launcher, with --ei-pt-tuning.
## Raised surfaces outside binary16 uncertainty and opposing raster normals
## must not borrow traced floor material. Quantization-ambiguous roots are
## reported separately. Readbacks invalidate all timing measurements.
const PathRR=preload("res://src/game/fx/path_trace_rr.gd")
const Geometry=preload("res://src/game/fx/biome_cover_mesh.gd")
const Audit=preload("res://tools/tests/path_trace_rr_detail_audit.gd")
const FLOOR:=Color(.15,.25,.35,1)
const EXTENT:=Vector2i(1600,900)
var audit
var rr
var details: Array[MeshInstance3D]=[]
var detail_rows: Array[Dictionary]=[]
var samples: Array[Dictionary]=[]
var mode:="nrd"
var floor_height_error:=0.0
var floor_measured:=false
var floor_guides_valid:=false
var floor_plane_error:=0.0
var pending_changes: Dictionary={}
var eye:=Vector3(0,14.4421356,14.1421356)

func native_status() -> Dictionary:
	return RtxGraphics.bridge().call("get_status") if RtxGraphics.bridge()!=null else {}

func frame(history:=true,gi:=true,shadows:=true) -> PackedByteArray:
	var bytes:=super.frame(history,gi,shadows)
	bytes.encode_float(145*4,8.0);bytes.encode_float(77*4,1.0)
	# The reusable device fixture was authored for an orthographic camera and
	# hard-codes this bit. This perspective scene must trace perspective rays.
	bytes.encode_float(80*4,float(camera.projection==Camera3D.PROJECTION_ORTHOGONAL))
	return bytes

func publish() -> void:
	var vp:=camera.get_camera_projection()*Projection(camera.global_transform.affine_inverse())
	RenderingServer.global_shader_parameter_set(&"ei_rt_view_projection",vp)
	RenderingServer.global_shader_parameter_set(&"ei_rt_inverse_view_projection",vp.inverse())
	RenderingServer.global_shader_parameter_set(&"ei_rt_view",Projection(camera.global_transform.affine_inverse()))
	RenderingServer.global_shader_parameter_set(&"ei_rt_eye",camera.global_position)
	RenderingServer.global_shader_parameter_set(&"ei_rt_state",Vector4(1,1,1,72))
	RenderingServer.global_shader_parameter_set(&"ei_rt_center",Vector4.ZERO)
	RenderingServer.global_shader_parameter_set(&"ei_pt_active",1.0)
	RenderingServer.global_shader_parameter_set(&"ei_pt_rr_active",float(mode=="rr"))
	RenderingServer.global_shader_parameter_set(&"ei_rt_gi",device.output)
	RenderingServer.global_shader_parameter_set(&"ei_rt_guide",device.guide)
	RenderingServer.global_shader_parameter_set(&"ei_rt_shadow0",device.shadow0)
	RenderingServer.global_shader_parameter_set(&"ei_rt_shadow1",device.shadow1)
	RenderingServer.global_shader_parameter_set(&"ei_pt_direct_sun",device.direct_sun)
	for node in details:node.material_override.set_shader_parameter("view_position",camera.global_position)

func step(count: int,reset:=false) -> void:
	for i in count:
		publish()
		var changes:=pending_changes.duplicate(true);pending_changes.clear()
		if mode=="rr":
			RenderingServer.call_on_render_thread(rr.queue_frame.bind(device,size,frame(not (reset and i==0)),changes,4,-1,reset and i==0))
		else:
			changes.merge({"ray_reconstruction":false,"nrd_directional":false},true)
			RenderingServer.call_on_render_thread(device.render.bind(size,frame(not (reset and i==0)),changes,4))
		await RenderingServer.frame_post_draw

func add_details() -> void:
	for family: String in ["grass","stone","mushroom"]:
		var column: int=["grass","stone","mushroom"].find(family)
		for row in 3:
			var factor: float=[.2,.45,1.0][row]
			var node:=MeshInstance3D.new()
			var material:=ShaderMaterial.new()
			if family=="grass":
				node.mesh=TerrainDetails.blade_mesh(true)
				node.scale=Vector3.ONE*factor;node.position.y=.008
				material.shader=Gfx.make_shader(TerrainDetails.GRASS_SHADER,true,true)
			else:
				var record: Dictionary={"p":Vector2.ZERO,"height":0.0,"seed":.25,"angle":.0,"scale":factor,
					"normal":Vector3.UP,"colour":Color(.36,.65,.18),"kind":5 if family=="stone" else 22}
				var records: Array[Dictionary]=[record]
				var geometry:=Geometry.new();var arrays:=geometry.build(records,Vector2i.ZERO)
				var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[],{},Geometry.FORMAT)
				node.mesh=mesh;material.shader=Geometry.shader(false,false)
			node.position.x=(column-1)*1.8;node.position.z=(row-1)*1.8
			material.set_shader_parameter("breeze",0.0);node.material_override=material
			node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(node);details.append(node)
			detail_rows.append({"family":family,"scale":factor,"index":details.size()-1,
				"mesh_id":node.mesh.get_instance_id(),"material_id":material.get_instance_id(),
				"shader_sha256":material.shader.code.sha256_text(),"root":str(node.position)})

func object_bounds(node: MeshInstance3D) -> AABB:
	var box: AABB=node.global_transform*node.mesh.get_aabb()
	# Grass has additional per-blade shader shaping even with zero wind.
	return box.grow(.12*node.scale.x if node.material_override.shader.code.contains("varying vec3 blade_colour;") else .015)

func object_roi(node: MeshInstance3D) -> Rect2i:
	var box:=object_bounds(node)
	var rect:=Rect2(camera.unproject_position(box.position),Vector2.ZERO)
	for i in 8:rect=rect.expand(camera.unproject_position(box.get_endpoint(i)))
	var mapping:=Vector2(size)/get_viewport().get_visible_rect().size
	return Rect2i(Vector2i(rect.position*mapping),Vector2i(rect.size*mapping)).intersection(Rect2i(Vector2i.ZERO,size))

func capture(label: String) -> void:
	# Subscribe immediately; awaiting a separate frame first can miss the
	# render thread's deferred completion signal.
	audit.armed=true;await audit.inspected
	check(audit.error.is_empty() and audit.result!=null,label+" reads actual raster/PT guide data")
	if audit.result==null:
		var error_row:={"label":label,"mode":mode,"error":audit.error,"native":native_status(),
			"window_size":str(get_window().size),"viewport_size":str(get_viewport().get_visible_rect().size),
			"raster_size":str(audit.raster_size),"pt_size":str(device._size),"scale":get_window().scaling_3d_scale,
			"rr_failed":rr.failed if rr!=null else false,"rr_frames":rr.submitted_frames if rr!=null else 0}
		samples.append(error_row)
		print("RASTER_DETAIL_ERROR ",JSON.stringify(error_row))
		FileAccess.open(out.path_join("raster-detail-progress.json"),FileAccess.WRITE).store_string(JSON.stringify({"samples":samples,"geometry":detail_rows},"\t"))
		return
	var image: Image=audit.result
	var picture:=get_viewport().get_texture().get_image()
	var picture_scale:=Vector2(picture.get_size())/Vector2(size)
	var guide_bytes: PackedByteArray=audit.raw_guide.get_data()
	var inverse: Projection=audit.projection.inverse()
	var row: Dictionary={"label":label,"mode":mode,"native":native_status(),"nrd_active":device.nrd_active,"details":[]}
	if label.begins_with("bare-floor"):
		floor_height_error=0.0
		var max_plane:=0.0;var max_depth:=0.0;var matched_floor:=0;var floor_pixels:=0
		for y in range(16,size.y-16):
			for x in range(16,size.x-16):
				var pixel:=image.get_pixel(x,y)
				if pixel.r< -998.0:continue
				floor_height_error=maxf(floor_height_error,absf(pixel.r));max_plane=maxf(max_plane,pixel.b);max_depth=maxf(max_depth,absf(pixel.g))
				floor_pixels+=1
				if audit.diffuse!=null:
					var diffuse: Color=audit.diffuse.get_pixel(x,y);var albedo: Color=audit.raw_albedo.get_pixel(x,y)
					if Vector3(diffuse.r-albedo.r,diffuse.g-albedo.g,diffuse.b-albedo.b).length()<.001:matched_floor+=1
		row["floor_max_world_height_error"]=floor_height_error;row["floor_max_plane_error"]=max_plane;row["floor_max_depth_error"]=max_depth
		floor_plane_error=max_plane
		row["matched_floor"]=matched_floor;row["floor_pixels"]=floor_pixels
		floor_measured=floor_pixels>1000
		floor_guides_valid=floor_pixels>1000 and matched_floor>=floor_pixels*.995
		check(floor_guides_valid,"bare traced floor keeps matching material guides")
	else:
		for info in detail_rows:
			var node: MeshInstance3D=details[info.index]
			var rect:=object_roi(node);var count:=0;var borrowed:=0;var count_low:=0;var visible_colour:=0
			var definite:=0;var ambiguous:=0;var wrong_definite:=0;var wrong_ambiguous:=0;var opposite:=0
			var sum_height:=0.0;var max_height:=0.0;var min_plane:=INF;var max_plane:=0.0;var worst_normal:=1.0
			for y in range(rect.position.y,rect.end.y):
				for x in range(rect.position.x,rect.end.x):
					var pixel:=image.get_pixel(x,y)
					if pixel.r<=maxf(.003,floor_height_error*4.0):continue
					count+=1;sum_height+=pixel.r;max_height=maxf(max_height,pixel.r)
					var color:=picture.get_pixelv(Vector2i((Vector2(x,y)+Vector2(.5,.5))*picture_scale))
					if maxf(color.r,maxf(color.g,color.b))>.01:visible_colour+=1
					min_plane=minf(min_plane,pixel.b);max_plane=maxf(max_plane,pixel.b);worst_normal=minf(worst_normal,pixel.a)
					if pixel.r<.06:count_low+=1
					# The storage format is the oracle, not the production match
					# formula. Decode binary16's exponent directly from real bytes.
					var exponent: int=(guide_bytes.decode_u16((y*size.x+x)*8+6)>>10)&31
					var spacing:=pow(2.0,maxi(exponent,1)-25)
					var uv:=(Vector2(x,y)+Vector2(.5,.5))/Vector2(size)
					var ray:=inverse*Vector4(uv.x*2-1,1-uv.y*2,-1,1);ray/=ray.w
					var per_depth:=Vector3(ray.x,ray.y,ray.z)/(-ray.z)
					var world_step: Vector3=audit.camera_world.basis*per_depth
					var normal:=Vector3(audit.plane.x,audit.plane.y,audit.plane.z)
					var quantization:=spacing*absf(world_step.dot(normal))
					# A true height beyond two storage intervals cannot be
					# mistaken for this plane even at opposite quantization ends.
					# Also retain the independently measured raster roundoff.
					var distinct_height:=pixel.r>2.0*maxf(quantization,floor_plane_error)+4.0*floor_height_error
					var distinct_normal:=pixel.a<0.0
					var unambiguous:=distinct_height or distinct_normal
					if unambiguous:definite+=1
					else:ambiguous+=1
					if distinct_normal:opposite+=1
					if mode=="rr" and audit.diffuse!=null:
						var diffuse: Color=audit.diffuse.get_pixel(x,y);var albedo: Color=audit.raw_albedo.get_pixel(x,y)
						if Vector3(diffuse.r-albedo.r,diffuse.g-albedo.g,diffuse.b-albedo.b).length()<.001:
							borrowed+=1
							if unambiguous:wrong_definite+=1
							else:wrong_ambiguous+=1
			row.details.append({"family":info.family,"scale":info.scale,"pixels":count,"low_pixels":count_low,
				"visible_colour_pixels":visible_colour,
				"unambiguous_pixels":definite,"ambiguous_root_pixels":ambiguous,"opposite_normal_pixels":opposite,
				"wrong_unambiguous_guides":wrong_definite,"borrowed_ambiguous_guides":wrong_ambiguous,
				"borrowed_floor_guides":borrowed,"mean_height":sum_height/maxi(count,1),"max_height":max_height,
				"min_plane_error":min_plane if count>0 else 0.0,"max_plane_error":max_plane,"min_normal_dot":worst_normal,
				"roi":[rect.position.x,rect.position.y,rect.size.x,rect.size.y]})
	picture.save_png(out.path_join(label+".png"))
	if label=="rr-held-0":
		image.save_exr(out.path_join("rr-diagnostic.exr"));audit.diffuse.save_exr(out.path_join("rr-diffuse-albedo.exr"))
		for detail: Dictionary in row.details:
			check(detail.pixels>=6 and detail.visible_colour_pixels>=6,"RR clearly frames and lights %s scale %.2f (%d raised / %d visible pixels)"%[detail.family,detail.scale,detail.pixels,detail.visible_colour_pixels])
	samples.append(row)
	FileAccess.open(out.path_join("raster-detail-progress.json"),FileAccess.WRITE).store_string(JSON.stringify({"samples":samples,"geometry":detail_rows},"\t"))
	print("RASTER_DETAIL_CAPTURE ",label)

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--audit-out="):out=arg.trim_prefix("--audit-out=")
	DirAccess.make_dir_recursive_absolute(out)
	check(PathDevice.supported() and RtxGraphics.facts().rr,"native path tracing and RR are available")
	if not PathDevice.supported() or not RtxGraphics.facts().rr:finish();return
	get_tree().root.get_node("RtxExperiment").set_process(false)
	get_tree().root.get_node("FsrExperiment").set_process(false)
	GameData.options.merge({"pt_mode":1,"pt_ray_reconstruction":0,"rtx_upscaling":2,"rtx_frame_generation":0,
		"fsr_upscaling":0,"fsr_frame_generation":0,"confine_mouse":0,"show_fps":1,
		"volume_sfx":0,"volume_stream":0,"volume_voice":0,"display_mode":0,"q_aa":0,"vsync":0,"auto_graphics":0},true)
	for option: Array in GameData.OPTIONS:
		if String(option[0]).begins_with("gfx_"):GameData.options[option[0]]=0
	GameData.resolution_size="1600x900"
	GameData.options.resolution=maxi(0,GameData.resolutions().find(EXTENT))
	GameData._window_state.clear();GameData._apply_window()
	await frames(18);GameData._window_gen+=1;get_window().mode=Window.MODE_WINDOWED;get_window().size=EXTENT
	RtxGraphics.apply_upscaling(get_window());Engine.max_fps=30
	get_window().set("frame_generation",false);RtxGraphics.bridge().call("set_parameter",0,0.0)
	Gfx.ensure_globals();Gfx.apply_surface_options();Gfx.scene_rt_gi_active=true;Gfx.path_trace_active=true
	RenderingServer.global_shader_parameter_set(&"ei_border",Vector4.ZERO)
	RenderingServer.global_shader_parameter_set(&"ei_fog",Vector3(500,1000,0))
	RenderingServer.global_shader_parameter_set(&"ei_ambient",Vector3.ONE*.2)
	RenderingServer.global_shader_parameter_set(&"ei_sun",Vector3.ZERO)
	RenderingServer.global_shader_parameter_set(&"ei_pt_grass_shadows",0.0)
	# The qualified engine only honors compositor normal/roughness requests
	# inside its valid-environment branch (as in the ordinary campaign view).
	var environment:=WorldEnvironment.new();environment.environment=Environment.new()
	environment.environment.background_mode=Environment.BG_COLOR
	environment.environment.background_color=Color(.025,.025,.025)
	add_child(environment)
	camera=Camera3D.new();add_child(camera);camera.fov=12;camera.position=eye;camera.look_at(Vector3(0,.3,0));camera.current=true
	size=Vector2i(Vector2(EXTENT)*get_window().scaling_3d_scale)
	sky_energy=1.0;sun_energy=0.0;bounces=2
	quad(mesh_data,[Vector3(-40,0,-40),Vector3(40,0,-40),Vector3(40,0,40),Vector3(-40,0,40)],Vector3.UP,Vector3.ZERO)
	for vertex in mesh_data.size()/16:
		mesh_data[vertex*16+8]=FLOOR.r;mesh_data[vertex*16+9]=FLOOR.g;mesh_data[vertex*16+10]=FLOOR.b
	geometries.append({"offset":0,"count":6,"standard":true,"opaque":true,"surface":Vector3(1,0,0)})
	placements.append({"geometry":0,"transform":Transform3D.IDENTITY,"mask":7})
	check(await build_fixture(),"trace scene contains only the analytic flat floor")
	if not device._ready:finish();return
	var ground:=MeshInstance3D.new();var plane:=PlaneMesh.new();plane.size=Vector2(80,80);ground.mesh=plane
	var material:=ShaderMaterial.new();material.shader=Gfx.make_shader("""
shader_type spatial;
#define EI_TERRAIN_LIGHT
render_mode cull_disabled, ambient_light_disabled;
varying vec3 ei_e;
varying float ei_k;
void vertex(){ei_e=vec3(0.0);ei_k=0.0;}
void fragment(){ALBEDO=vec3(.15,.25,.35);ROUGHNESS=1.0;SPECULAR=0.0;}
""",true,true)
	ground.material_override=material;add_child(ground)
	audit=Audit.new();audit.target=device
	var compositor:=Compositor.new();compositor.compositor_effects=[audit];camera.compositor=compositor
	# Query the renderer's actual internal extent after window/stretch setup.
	# A nominal window-size product can disagree with native DLSS rounding.
	var stable:=0;var last_size:=Vector2i.ZERO
	for i in 120:
		audit.armed=true;await audit.inspected
		if get_window().size==EXTENT and audit.raster_has_normal and audit.raster_size==last_size and last_size.x>0:
			stable+=1
		else:stable=0
		last_size=audit.raster_size
		if stable>=8:break
	check(stable>=8,"native viewport dimensions and normal/depth targets stabilize")
	if stable<8:
		print("RASTER_DETAIL_SETUP_ERROR window=",get_window().size," raster=",audit.raster_size," normal=",audit.raster_has_normal)
		camera.compositor=null;RenderingServer.call_on_render_thread(audit.dispose);RenderingServer.call_on_render_thread(device.dispose)
		await frames(4);finish();return
	size=audit.raster_size
	print("RASTER_DETAIL_EXTENT ",size," window=",get_window().size," viewport=",get_viewport().get_visible_rect().size," scale=",get_window().scaling_3d_scale)
	rr=PathRR.new();audit.rr=rr;mode="rr";compositor.compositor_effects=[rr,audit]
	await step(30,true);await capture("bare-floor")
	check(floor_measured and floor_height_error<.003,"measured analytic raster floor reconstructs within three millimetres")
	if not floor_measured or not floor_guides_valid or floor_height_error>=.003:
		camera.compositor=null;RenderingServer.call_on_render_thread(rr.dispose);RenderingServer.call_on_render_thread(audit.dispose)
		RenderingServer.call_on_render_thread(device.dispose);await frames(4);finish();return
	# Preserve matching traced material on real slopes, including the grazing
	# direction, before returning to the unchanged flat detail fixture.
	for angle: float in [35.0,-35.0,0.0]:
		ground.basis=Basis(Vector3.RIGHT,deg_to_rad(angle))
		var normal:=ground.basis*Vector3.UP;audit.plane=Vector4(normal.x,normal.y,normal.z,0)
		pending_changes={"instances":[{"index":0,"transform":ground.transform,"mask":7}]}
		await step(18,true);await capture("bare-floor-slope-%d"%int(angle))
		check(floor_measured and floor_guides_valid and floor_height_error<.003,"sloped floor keeps its traced material at %d degrees"%int(angle))
		if not floor_measured or not floor_guides_valid or floor_height_error>=.003:
			camera.compositor=null;RenderingServer.call_on_render_thread(rr.dispose);RenderingServer.call_on_render_thread(audit.dispose)
			RenderingServer.call_on_render_thread(device.dispose);await frames(4);finish();return
	add_details()
	check(details.size()==9 and detail_rows.all(func(row: Dictionary):return not row.shader_sha256.is_empty()),"three unchanged production mesh families at three sizes")
	check(details.all(func(node: MeshInstance3D):return node.material_override.shader.code.contains("ei_rt_ground=origin;")),"all details use the actual PT planted-root receiver")
	var framed:=true
	for node in details:
		var box:=object_bounds(node)
		for i in 8:
			var p:=box.get_endpoint(i)
			framed=framed and not camera.is_position_behind(p) and get_viewport().get_visible_rect().has_point(camera.unproject_position(p))
	check(framed,"all nine complete detail bounds lie inside the camera")
	for phase: String in ["nrd","rr","nrd-restored"]:
		mode="rr" if phase=="rr" else "nrd";camera.position=eye;camera.look_at(Vector3(0,.3,0))
		if mode=="rr":
			rr=PathRR.new();audit.rr=rr;compositor.compositor_effects=[rr,audit]
		else:
			compositor.compositor_effects=[audit];audit.rr=null
			if rr!=null:RenderingServer.call_on_render_thread(rr.dispose);rr=null
		var before:=native_status();await step(70,true)
		var after:=native_status()
		check(device.ray_reconstruction==(mode=="rr") and device.nrd_active==(mode!="rr"),phase+" selects the intended live reconstruction path")
		check(int(after.get("rr_evaluations",0) if mode=="rr" else after.get("dlss_evaluations",0))>int(before.get("rr_evaluations",0) if mode=="rr" else before.get("dlss_evaluations",0))+30,phase+" executes the intended native reconstruction")
		for i in 3:await step(8);await capture(phase+"-held-"+str(i))
		for i in 6:
			camera.position=eye+Vector3((i-2.5)*.006,0,0);camera.look_at(Vector3(0,.3,0))
			await step(4);await capture(phase+"-pan-"+str(i))
	check(detail_rows.all(func(row: Dictionary):return details[row.index].mesh.get_instance_id()==row.mesh_id and details[row.index].material_override.get_instance_id()==row.material_id),"RR and NRD use identical detail geometry and material objects")
	for family: String in ["grass","stone","mushroom"]:
		var visible:=0;var borrowed:=0;var distinct:=0;var ambiguous:=0
		for row in samples:
			if row.mode!="rr":continue
			for object: Dictionary in row.get("details",[]):
				if object.family==family:
					visible+=object.pixels;distinct+=object.unambiguous_pixels
					borrowed+=object.wrong_unambiguous_guides;ambiguous+=object.ambiguous_root_pixels
		check(visible>=10,family+" has measurable elevated raster pixels")
		check(distinct>=10 and borrowed==0,family+" unambiguously distinct pixels reject floor guides (wrong="+str(borrowed)+", roots within uncertainty="+str(ambiguous)+")")
	FileAccess.open(out.path_join("raster-detail-results.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,
		"geometry":detail_rows,"samples":samples,"floor_height_error":floor_height_error,"timing_valid":false},"\t"))
	camera.compositor=null;RenderingServer.call_on_render_thread(audit.dispose)
	RenderingServer.call_on_render_thread(device.dispose);await frames(8);finish()
