extends "ground_contact_relief_scene.gd"
## Original mesh/placement, dry shoreline bridge edge with nonzero native k.
## The bridge is above the liquid plane; this is not an underwater crossing.
var original_materials := true
func camera_span() -> float:
	return 2.4
func upper_mask_offset() -> float:
	# The unchanged authored bridge is only 0.59m tall. Keep its established
	# close framing separate from the taller house and snow-barrack cases.
	return 0.22
func run_scene() -> void:
	original_materials=not OS.get_cmdline_user_args().has("--shore-enhanced")
	GameData.options.gfx_materials=int(not original_materials)
	Gfx.apply_surface_options()
	await super.run_scene()
func root_anchor(object: Node3D,terrain: EITerrain) -> Vector3:
	var edge_a := Vector3(145.353057861328,5.96470022201538,-87.2312850952148)
	var edge_b := Vector3(143.701278686523,5.96470022201538,-86.6945953369141)
	var found := false; var closest := {}; var nearest := INF
	for mesh in target_meshes(object):
		# get_faces() goes through Godot's 0.0001m snapped TriangleMesh.
		# The census and rendered mesh use the original indexed vertex data.
		var data := mesh.mesh.surface_get_arrays(0)
		var positions: PackedVector3Array=data[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array=data[Mesh.ARRAY_INDEX]
		for i in range(0,indices.size(),3):
			for j in 3:
				var a := mesh.global_transform*positions[indices[i+j]]
				var b := mesh.global_transform*positions[indices[i+(j+1)%3]]
				var error := minf(maxf(a.distance_to(edge_a),b.distance_to(edge_b)),maxf(a.distance_to(edge_b),b.distance_to(edge_a)))
				if error<nearest:
					nearest=error;closest={"a":[a.x,a.y,a.z],"b":[b.x,b.y,b.z],"triangle":i/3,"edge":j,"mesh":str(mesh.name),"error":error}
				if error<1e-5:found=true
	check(found,"selected original bridge edge is unchanged")
	print("SHORELINE_EDGE ",JSON.stringify(closest))
	if OS.get_cmdline_user_args().has("--shore-edge-only"):
		FileAccess.open("user://shoreline-edge.json",FileAccess.WRITE).store_string(JSON.stringify(closest,"\t")+"\n")
		return Vector3.INF
	var sector := terrain.get_node("Sector_4_2") as EITerrainSector
	check(sector!=null and sector._parts.size()==1,"selected original shoreline sector")
	if sector==null:return Vector3.INF
	var arrays := sector._parts[0].mesh.surface_get_arrays(0)
	var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
	var verts: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	var colors: PackedColorArray=arrays[Mesh.ARRAY_COLOR]
	var t := [];var cs := []
	for i in 3:
		var id := indices[1473*3+i];t.append(sector._parts[0].global_transform*verts[id]);cs.append(colors[id])
	check(roundi(cs[0].a*255)==49 and cs[1].a==0.0 and roundi(cs[2].a*255)==7,"native shoreline alpha bytes 49,0,7")
	var point: Variant=Geometry3D.segment_intersects_triangle(edge_a,edge_b,t[0],t[1],t[2])
	check(point is Vector3,"original bridge edge intersects selected land triangle")
	if not point is Vector3:return Vector3.INF
	check(point.distance_to(Vector3(144.260238647461,5.96470022201538,-86.8762130737305))<1e-5,"selected original contact position matches census")
	var margin: float=point.y-terrain.water_at(point.x,-point.z)
	check(margin>0.10,"shoreline contact is dry and survives native water gate")
	anchor_witness={"native_triangle":1473,"sector":[4,2],"original_materials":original_materials,"margin_over_cell_water":margin,"alpha_bytes":[49,0,7],"native_interpolated_k":0.1101310700178148,"E":[0,0,0],"liquid_plane_crossing":false}
	anchor_witness["packed_point_offset"]="(0.35, 2.2, 0.4)"
	return point
func lights(mode: String,sun: DirectionalLight3D,point: OmniLight3D,anchor: Vector3) -> void:
	sun.rotation_degrees=Vector3(-50,55,0)
	super.lights(mode,sun,point,anchor)
	# A near-overhead point makes the native vertical water-edge attenuation
	# visible in Enhanced mode. The earlier oblique fixture is retained.
	if mode=="packed-point":point.position=anchor+Vector3(0.35,2.2,0.4)
	Gfx.update_pass_lights(get_tree(),anchor)
func light_case(mode: String,view: SubViewport,object: Node3D,owner: GroundContact,sun: DirectionalLight3D,point: OmniLight3D,anchor: Vector3) -> void:
	await super.light_case(mode,view,object,owner,sun,point,anchor)
	GameData.options.gfx_ground_contact=1;owner.refresh()
	var on := await capture(view,"shore-inputs-"+mode+"-on")
	var saved := {};var zero: Texture
	var parameter := "contact_data" if target_meshes(object)[0].material_override.get_shader_parameter("contact_data") != null else "query_light_inputs"
	for mesh in target_meshes(object):
		var material := mesh.material_override as ShaderMaterial
		if saved.has(material):continue
		var texture := material.get_shader_parameter(parameter) as Texture
		check(texture!=null,"shore contact binds native baked vertex inputs")
		if texture==null:continue
		if zero==null:
			if texture is Texture2DArray:
				# GLES layer readback clamps floats into RGBA8. Recreate from
				# retained CPU sources so normals/heights keep all their bits.
				var images: Dictionary = owner.surface.call("_metadata_images", owner.terrain)
				images.query_light_inputs.fill(Color(0,0,0,0))
				var pool: RefCounted = load("res://src/game/fx/ground_contact_data.gd").new()
				pool.build(images); zero=pool.texture
			else:
				var pixels := Image.create(texture.get_width(),texture.get_height(),false,Image.FORMAT_RGBA8)
				pixels.fill(Color(0,0,0,0));zero=ImageTexture.create_from_image(pixels)
		saved[material]=texture;material.set_shader_parameter(parameter,zero)
	var control := await capture(view,"shore-inputs-"+mode+"-disabled")
	var band := difference(on,control,"band");var outside := difference(on,control,"outside_band")
	if mode!="local-light":check(band.over_two_bytes>8,mode+" native shoreline inputs visibly affect bridge band "+str(band))
	check(outside.changed_pixels==0,mode+" shoreline inputs change only the contact band")
	for material: ShaderMaterial in saved:material.set_shader_parameter(parameter,saved[material])
	check(difference(on,await capture(view,"shore-inputs-"+mode+"-restored")).changed_pixels==0,mode+" shoreline input restoration exact")
	rows.append({"light":"shore-inputs-"+mode,"band":band,"outside_band":outside,"scope":"Ablates only copied-ground packed vertex E/k; native object/terrain data and all shader code unchanged."})
	GameData.options.gfx_ground_contact=0;owner.refresh()
