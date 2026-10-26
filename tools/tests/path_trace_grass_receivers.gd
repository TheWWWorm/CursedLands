extends "res://tools/tests/scene_raytrace_device.gd"
const Receiver=preload("res://src/game/fx/scene_raytrace_shader.gd")
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--audit-out="):out=arg.trim_prefix("--audit-out=")
	DirAccess.make_dir_recursive_absolute(out)
	GameData.resolution_size="1280x720";GameData.options.display_mode=0
	get_window().borderless=true;get_window().size=Vector2i(1280,720)
	Gfx.ensure_globals();GameData.options.pt_mode=1;GameData.options.gfx_cloud_shadows=0
	camera=Camera3D.new();add_child(camera);camera.position=Vector3(0,3,6);camera.look_at(Vector3(0,0.6,0));camera.current=true
	await frames(12)
	get_window().size=Vector2i(1280,720);Gfx.apply_quality(get_viewport());await frames(4)
	check(get_viewport().get_visible_rect().size==Vector2(1280,720),"grass fixture uses calibrated resolution")
	var vp:=camera.get_camera_projection()*Projection(camera.global_transform.affine_inverse())
	RenderingServer.global_shader_parameter_set(&"ei_rt_view_projection",vp)
	RenderingServer.global_shader_parameter_set(&"ei_rt_inverse_view_projection",vp.inverse())
	RenderingServer.global_shader_parameter_set(&"ei_rt_view",Projection(camera.global_transform.affine_inverse()))
	RenderingServer.global_shader_parameter_set(&"ei_rt_eye",camera.position)
	RenderingServer.global_shader_parameter_set(&"ei_rt_center",Vector4.ZERO)
	RenderingServer.global_shader_parameter_set(&"ei_rt_state",Vector4(1,1,1,72))
	RenderingServer.global_shader_parameter_set(&"ei_pt_active",1.0)
	var guide:=Image.create(640,360,false,Image.FORMAT_RGBAF)
	var light:=Image.create(640,360,false,Image.FORMAT_RGBAF)
	for y in 360:
		for x in 640:
			var uv:=Vector2(x+0.5,y+0.5)*2
			var ray:=camera.project_ray_normal(uv);var eye:=camera.project_ray_origin(uv)
			if ray.y>=-0.001:continue
			var hit:=eye+ray*(-eye.y/ray.y);var depth:=-(camera.global_transform.affine_inverse()*hit).z
			guide.set_pixel(x,y,Color(0,1,0,depth));light.set_pixel(x,y,Color(0.02,0.02,0.02,1) if hit.x<0 else Color(0.8,0.8,0.8,1))
	var guide_texture:=ImageTexture.create_from_image(guide);var light_texture:=ImageTexture.create_from_image(light)
	RenderingServer.global_shader_parameter_set(&"ei_rt_guide",guide_texture)
	for key in [&"ei_rt_gi",&"ei_rt_shadow0",&"ei_rt_shadow1"]:RenderingServer.global_shader_parameter_set(key,light_texture)
	var arrays:=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3(-0.3,0,0),Vector3(0.3,1.2,0),Vector3(0.3,0,0),Vector3(-0.3,0,0),Vector3(-0.3,1.2,0),Vector3(0.3,1.2,0)])
	var normals:=PackedVector3Array();var colours:=PackedColorArray();var uvs:=PackedVector2Array()
	for v: Vector3 in arrays[Mesh.ARRAY_VERTEX]:normals.append(Vector3.BACK);colours.append(Color.WHITE);uvs.append(Vector2(0,v.y/1.2))
	arrays[Mesh.ARRAY_NORMAL]=normals;arrays[Mesh.ARRAY_COLOR]=colours;arrays[Mesh.ARRAY_TEX_UV]=uvs
	var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var objects:=[]
	var shader:=Gfx.make_shader(TerrainDetails.GRASS_SHADER)
	for x in [-1,1]:
		var node:=MeshInstance3D.new();node.mesh=mesh;node.position.x=x
		var material:=ShaderMaterial.new();material.shader=shader;node.material_override=material;add_child(node);objects.append(node)
	await frames(20);await RenderingServer.frame_post_draw
	var capture:=get_viewport().get_texture().get_image();capture.save_png(out.path_join("grass-traced-shadow.png"))
	var dark:=capture.get_pixelv(Vector2i(camera.unproject_position(Vector3(-1,0.6,0))))
	var bright:=capture.get_pixelv(Vector2i(camera.unproject_position(Vector3(1,0.6,0))))
	check(bright.r>dark.r+0.25,"raised grass inherits the traced dark and lit ground roots")
	# Separate traced indirect light from direct sun, then let the existing
	# local shadow map shade only that sun component on raised blades.
	light.fill(Color(0.8,0.8,0.8,1));light_texture.update(light)
	var direct_image:=Image.create(640,360,false,Image.FORMAT_RGBAF);direct_image.fill(Color(0.6,0.6,0.6,1))
	var direct_texture:=ImageTexture.create_from_image(direct_image)
	RenderingServer.global_shader_parameter_set(&"ei_pt_direct_sun",direct_texture)
	# Use production setup: manually marking a synthetic light concealed the
	# desktop sun's missing identity while this same receiver test passed.
	var game:=Game.new();game._setup_env()
	var sun: DirectionalLight3D=game._sun
	game.remove_child(sun);game.free()
	# The synthetic pair is centred on the origin, outside a campaign map.
	# Environment setup refreshes campaign border fog; remove that fixture fog.
	RenderingServer.global_shader_parameter_set(&"ei_border",Vector4.ZERO)
	check(is_equal_approx(sun.light_specular,Gfx.SUN_MARK),"production sunlight is identified on the desktop renderer")
	sun.rotation_degrees=Vector3(-90,0,0)
	sun.shadow_enabled=true;sun.directional_shadow_max_distance=30;add_child(sun)
	var canopy:=MeshInstance3D.new();var canopy_mesh:=QuadMesh.new();canopy_mesh.size=Vector2(1.6,1.6)
	canopy.mesh=canopy_mesh;canopy.rotation_degrees.x=-90;canopy.position=Vector3(-1,2,0)
	canopy.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY;add_child(canopy)
	await frames(20);await RenderingServer.frame_post_draw
	capture=get_viewport().get_texture().get_image();capture.save_png(out.path_join("grass-local-sun-shadow.png"))
	dark=capture.get_pixelv(Vector2i(camera.unproject_position(Vector3(-1,0.6,0))))
	bright=capture.get_pixelv(Vector2i(camera.unproject_position(Vector3(1,0.6,0))))
	check(bright.r>dark.r+0.15,"nearby grass receives additional local sun occlusion")
	check(dark.r>0.1,"local grass shadow preserves traced indirect illumination")
	RenderingServer.global_shader_parameter_set(&"ei_pt_grass_shadows",0.0)
	await frames(12);await RenderingServer.frame_post_draw
	var disabled:=get_viewport().get_texture().get_image()
	var unshadowed:=disabled.get_pixelv(Vector2i(camera.unproject_position(Vector3(-1,0.6,0))))
	check(unshadowed.r>dark.r+0.15,"bounded grass shadow path changes the occluded blade")
	# Production's softer cascades can partially cover the second blade too.
	# Measure unit visibility explicitly instead of assuming that sample is 1.
	RenderingServer.global_shader_parameter_set(&"ei_pt_grass_shadows",1.0)
	sun.shadow_enabled=false
	await frames(12);await RenderingServer.frame_post_draw
	var clear:=get_viewport().get_texture().get_image().get_pixelv(Vector2i(camera.unproject_position(Vector3(-1,0.6,0))))
	check(absf(unshadowed.r-clear.r)<0.02,"unoccluded grass retains its original traced lighting")
	# A blade must cast onto the terrain, not just receive another caster's
	# shadow. Use a white terrain receiver with a known indirect-light floor.
	canopy.hide();sun.shadow_enabled=true;sun.rotation_degrees=Vector3(-45,0,0)
	for node: MeshInstance3D in objects:node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	var ground:=MeshInstance3D.new();var plane:=PlaneMesh.new();plane.size=Vector2(8,6);ground.mesh=plane
	ground.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material:=ShaderMaterial.new();material.shader=Gfx.make_shader("""
shader_type spatial;
#define EI_TERRAIN_LIGHT
render_mode cull_disabled, ambient_light_disabled;
varying vec3 ei_e;
varying float ei_k;
void vertex(){ei_e=vec3(0.0);ei_k=0.0;}
void fragment(){ALBEDO=vec3(1.0);}
""")
	ground.material_override=material;add_child(ground)
	var black:=Image.create(640,360,false,Image.FORMAT_RGBAF);black.fill(Color(0,0,0,1))
	var black_texture:=ImageTexture.create_from_image(black)
	RenderingServer.global_shader_parameter_set(&"ei_rt_shadow0",black_texture)
	RenderingServer.global_shader_parameter_set(&"ei_rt_shadow1",black_texture)
	await frames(20);await RenderingServer.frame_post_draw
	var ground_pixel:=Vector2i.ZERO
	var ground_picture:=get_viewport().get_texture().get_image()
	ground_picture.save_png(out.path_join("grass-casts-on-terrain.png"))
	RenderingServer.global_shader_parameter_set(&"ei_pt_grass_shadows",0.0)
	await frames(12);await RenderingServer.frame_post_draw
	var clear_picture:=get_viewport().get_texture().get_image()
	var shadow_pixels:=0;var largest_delta:=0.0
	# Procedural vertex shaping changes the exact silhouette. With the blades
	# hidden from the camera, only their ground shadows can change this ROI.
	for y in range(320,620):
		for x in range(100,1180):
			var delta:=clear_picture.get_pixel(x,y).r-ground_picture.get_pixel(x,y).r
			if delta>0.12:shadow_pixels+=1
			if delta>largest_delta:largest_delta=delta;ground_pixel=Vector2i(x,y)
	var ground_shadow:=ground_picture.get_pixelv(ground_pixel)
	var ground_clear:=clear_picture.get_pixelv(ground_pixel)
	check(shadow_pixels>=20,"a procedural blade casts a visible shadow on PT terrain")
	check(ground_shadow.r>0.1,"blade shadow on terrain preserves indirect illumination")
	# No direct sun means no grass-shadow subtraction from sky/bounce light.
	direct_image.fill(Color(0,0,0,1));direct_texture.update(direct_image)
	RenderingServer.global_shader_parameter_set(&"ei_pt_grass_shadows",1.0)
	await frames(12);await RenderingServer.frame_post_draw
	var indirect_only:=get_viewport().get_texture().get_image().get_pixelv(ground_pixel)
	check(absf(indirect_only.r-ground_clear.r)<0.02,"grass shadows do not darken a purely indirect terrain signal")
	print("GRASS_GROUND_SHADOW pixels=",shadow_pixels," peak=",largest_delta," sample=",ground_pixel)
	for node: MeshInstance3D in objects:node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
	ground.queue_free()
	FileAccess.open(out.path_join("grass-local-shadow.json"),FileAccess.WRITE).store_string(JSON.stringify({"shadowed":dark,"lit":bright,"disabled":unshadowed}))
	RenderingServer.global_shader_parameter_set(&"ei_pt_grass_shadows",1.0)
	RenderingServer.global_shader_parameter_set(&"ei_pt_direct_sun",null)
	canopy.queue_free();sun.queue_free();await frames(4)
	# Production lookup must reject a vertical foreground face at the root.
	var debug:=Shader.new();debug.code=Gfx._function_tail(shader.code.replace("render_mode ","render_mode unshaded, fog_disabled, "),"fragment","\n vec3 audit_light;vec4 audit_a,audit_b;bool valid=ei_rt_ground_sample(ei_rt_view_projection,ei_rt_inverse_view_projection,audit_light,audit_a,audit_b);ALBEDO=valid?vec3(0,1,0):vec3(1,0,0);EMISSION=vec3(0);\n")
	for node: MeshInstance3D in objects:node.material_override.shader=debug
	await frames(12);await RenderingServer.frame_post_draw
	capture=get_viewport().get_texture().get_image()
	check(capture.get_pixelv(Vector2i(camera.unproject_position(Vector3(-1,0.6,0)))).g>0.9,"ground root is a valid receiver")
	guide.fill(Color(0,0,1,6));guide_texture.update(guide)
	await frames(12);await RenderingServer.frame_post_draw
	capture=get_viewport().get_texture().get_image()
	check(capture.get_pixelv(Vector2i(camera.unproject_position(Vector3(-1,0.6,0)))).r>0.9,"grass rejects unrelated foreground walls")
	RenderingServer.global_shader_parameter_set(&"ei_rt_state",Vector4.ZERO)
	for key in [&"ei_rt_guide",&"ei_rt_gi",&"ei_rt_shadow0",&"ei_rt_shadow1"]:RenderingServer.global_shader_parameter_set(key,null)
	for node: MeshInstance3D in objects:node.queue_free()
	camera.queue_free();await frames(6);finish()
