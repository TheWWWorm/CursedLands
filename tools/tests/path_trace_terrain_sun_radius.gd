extends "res://tools/tests/path_trace_contacts.gd"
## A connected floor and cliff cast a self-terrain shadow. Its penumbra must
## respond to the sun disk even though the central direction stays fixed.
## Dense Cartesian disk quadrature is independent of the cache's tap pattern;
## raw diffuse sunlight also verifies the ordinary BRDF and object samples.
signal cache_captured
const TEST_X := -0.9
const LARGE_RADIUS := 0.3
# Interior dark-control vertices avoid interpolating toward the exact floor/
# wall contact, whose shared endpoint itself has an open outgoing sun ray.
const FLOOR_X := [-3.0,-2.6,-2.0,-1.3,-1.02,-0.98,-0.92,-0.90,-0.88,-0.82,-0.5,-0.45,-0.35,-0.3,0.0]
const FLOOR_Z := [-2.5,-1.0,-0.5,0.5,1.0,2.5]
var angular_radius := 0.0
var fixed_projection := Projection()
var fixed_view_projection := Projection()
var cache_snapshot := {}
var cache_bytes := PackedByteArray()
var references := {}

func frame(history:=true,gi:=true,shadows:=true) -> PackedByteArray:
	var data:=super.frame(history,gi,shadows)
	data.encode_float(71*4,angular_radius)
	for entry in [[0,fixed_projection.inverse()],[32,fixed_view_projection],[148,fixed_view_projection.inverse()]]:
		var matrix: Projection=entry[1]
		for axis in 4:
			for channel in 4:data.encode_float((int(entry[0])+axis*4+channel)*4,matrix[axis][channel])
	return data

func surface(first: int, terrain: bool, mask: int) -> void:
	geometries.append({"offset":first,"count":mesh_data.size()/16-first,"standard":true,
		"opaque":true,"terrain":terrain,"surface":Vector3(1,0,0)})
	placements.append({"geometry":geometries.size()-1,"transform":Transform3D.IDENTITY,"mask":mask})

func radius_fixture(terrain_wall:=true,contact:=false) -> bool:
	if device!=null:RenderingServer.call_on_render_thread(device.dispose);await frames(4)
	mesh_data=PackedFloat32Array();geometries=[];placements=[]
	for x in FLOOR_X.size()-1:
		for z in FLOOR_Z.size()-1:
			# Godot's clockwise terrain fronts: cross(edge1,edge2) is -UP.
			quad(mesh_data,[Vector3(FLOOR_X[x],0,FLOOR_Z[z]),Vector3(FLOOR_X[x+1],0,FLOOR_Z[z]),
				Vector3(FLOOR_X[x+1],0,FLOOR_Z[z+1]),Vector3(FLOOR_X[x],0,FLOOR_Z[z+1])],Vector3.UP,Vector3.ZERO)
	surface(0,true,7)
	var first:=mesh_data.size()/16
	for z in FLOOR_Z.size()-1:
		# These exact bottom vertices are shared with the floor. The wall is
		# the SAME connected terrain component, not an exact foreign blocker.
		quad(mesh_data,[Vector3(0,0,FLOOR_Z[z]),Vector3(0,1,FLOOR_Z[z]),
			Vector3(0,1,FLOOR_Z[z+1]),Vector3(0,0,FLOOR_Z[z+1])],Vector3.LEFT,Vector3.ZERO)
	surface(first,terrain_wall,6)
	if contact:
		first=mesh_data.size()/16
		quad(mesh_data,[Vector3(-3,0.0005,-2.5),Vector3(0,0.0005,-2.5),
			Vector3(0,0.0005,2.5),Vector3(-3,0.0005,2.5)],Vector3.DOWN,Vector3.ZERO)
		surface(first,false,6)
	var white:=Image.create(2,2,false,Image.FORMAT_RGBA8);white.fill(Color.WHITE)
	var images: Array[Image]=[white]
	device=PathDevice.new()
	RenderingServer.call_on_render_thread(device.build.bind(mesh_data.to_byte_array(),images,geometries,placements))
	return await device.prepared

func read_cache() -> void:
	cache_snapshot={"present":false,"matches":0,"mean":-1.0,"minimum":-1.0,"maximum":-1.0,
		"refreshes":-1,"components":-1,"input_id":-1,"output_id":-1}
	cache_bytes=PackedByteArray()
	var helper: RefCounted=device.get("terrain_sun")
	if helper!=null and helper._input.is_valid() and helper._output.is_valid():
		var input: PackedByteArray=device._rd.buffer_get_data(helper._input)
		cache_bytes=device._rd.buffer_get_data(helper._output)
		var start:=input.decode_u32(8);var count:=input.decode_u32(12)
		var sum:=0.0;var minimum:=INF;var maximum:=-INF;var matches:=0
		for i in count:
			var at:=start+i*32
			var p:=Vector3(input.decode_float(at),input.decode_float(at+4),input.decode_float(at+8))
			if absf(p.x-TEST_X)>0.0001 or absf(p.y)>0.0001 or absf(p.z)>1.01:continue
			var value:=cache_bytes.decode_float(i*4)
			sum+=value;minimum=minf(minimum,value);maximum=maxf(maximum,value);matches+=1
		cache_snapshot={"present":true,"matches":matches,"mean":sum/maxi(matches,1),
			"minimum":minimum if matches>0 else -1.0,"maximum":maximum if matches>0 else -1.0,
			"refreshes":helper.refreshes,"components":input.decode_u32(16),
			"input_id":helper._input.get_id(),"output_id":helper._output.get_id()}
	cache_captured.emit.call_deferred()

func pixel(position: Vector3) -> Vector2i:
	var p:=fixed_view_projection*Vector4(position.x,position.y,position.z,1.0)
	return Vector2i(int((p.x/p.w*0.5+0.5)*size.x),int((0.5-p.y/p.w*0.5)*size.y))

func patch(image: Image, left: float, right: float) -> Dictionary:
	var a:=pixel(Vector3(left,0,-0.5));var b:=pixel(Vector3(right,0,0.5))
	var sum:=0.0;var count:=0;var minimum:=INF;var maximum:=-INF
	for y in range(maxi(0,mini(a.y,b.y)),mini(size.y,maxi(a.y,b.y))):
		for x in range(maxi(0,mini(a.x,b.x)),mini(size.x,maxi(a.x,b.x))):
			var value:=image.get_pixel(x,y).r
			sum+=value;minimum=minf(minimum,value);maximum=maxf(maximum,value);count+=1
	return {"mean":sum/maxi(count,1),"minimum":minimum,"maximum":maximum,"pixels":count}

func measure(label: String, changes: Dictionary={}) -> Dictionary:
	await capture(label,changes,false,6)
	raw.save_exr(out.path_join(label+"-sun.exr"))
	RenderingServer.call_on_render_thread(read_cache);await cache_captured
	var row:={"radius":angular_radius,"cache":cache_snapshot.duplicate(true),
		"edge":patch(raw,-0.915,-0.885),"clear":patch(raw,-2.5,-2.2),"dark":patch(raw,-0.45,-0.35)}
	report[label]=row
	return row

func disk_reference(radius: float) -> Dictionary:
	if references.has(radius):return references[radius]
	# Integrate a uniform disk with Cartesian cells, without using the shader's
	# polar sampler or the cached quadrature. For L=(1,1,0), the unit tangent
	# coordinates give L proportional to (1-u,1+u,sqrt(2)*v). A ray from
	# (TEST_X,0,0) clears the one-metre cliff exactly when -x*L.y/L.x>1.
	var visibility:=0.0;var clear_energy:=0.0;var object_energy:=0.0;var count:=0
	var extent:=192 if radius>0.0 else 1
	for y in extent:
		for x in extent:
			var u:=(2.0*(x+0.5)/extent-1.0);var v:=(2.0*(y+0.5)/extent-1.0)
			if u*u+v*v>1.0:continue
			var direction:=Vector3(1.0-radius*u,1.0+radius*u,sqrt(2.0)*radius*v).normalized()
			var visible:=direction.x<=0.0 or -TEST_X*direction.y/direction.x>1.0
			# White diffuse receiver, view/normal UP, dielectric F0=0. The
			# Schlick diffuse factor is evaluated independently in closed form.
			var energy:=maxf(direction.y,0.0)*(1.0-pow(1.0-sqrt((1.0+direction.y)*0.5),5.0))
			clear_energy+=energy;count+=1
			if visible:visibility+=1.0;object_energy+=energy
	var result:={"visibility":visibility/count,"clear_energy":clear_energy/count,"object_energy":object_energy/count}
	references[radius]=result
	return result

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--audit-out="):out=arg.trim_prefix("--audit-out=")
	DirAccess.make_dir_recursive_absolute(out)
	check(PathDevice.supported(),"qualified native sun-radius device")
	if not PathDevice.supported():finish();return
	camera=Camera3D.new();add_child(camera);camera.current=true;camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.position=Vector3(-1.5,6,0);camera.look_at(Vector3(-1.5,0,0),Vector3.FORWARD)
	size=Vector2i(384,256);spp=16;bounces=1;sun_energy=1.0;sky_energy=0.0
	sun_direction=Vector3(1,1,0).normalized();camera.size=2.8
	var half:=camera.size*0.5;var aspect:=float(size.x)/size.y
	fixed_projection=Projection.create_orthogonal(-half*aspect,half*aspect,-half,half,camera.near,camera.far)
	fixed_view_projection=fixed_projection*Projection(camera.global_transform.affine_inverse())
	var point_reference:=disk_reference(0.0);var soft_reference:=disk_reference(LARGE_RADIUS)
	check(await radius_fixture(),"build a floor welded to its occluding terrain cliff")
	if not device._ready:finish();return
	angular_radius=0.0
	var point:=await measure("terrain-point",{"ray_reconstruction":true,"rtxdi":false})
	check(point.cache.present and point.cache.components==1,"the floor and cliff use one self-terrain component")
	check(point.cache.matches>=2 and point.edge.pixels>=100,"cache and raw-light measurements cover the intended shadow strip")
	check(point.edge.maximum<0.001 and point.cache.maximum<0.0001,"the central point sun is occluded at the selected terrain boundary")
	check(point.clear.minimum>0.65 and point.dark.maximum<0.001,"independent lit and fully shadowed terrain controls are valid")
	check(absf(point.clear.mean-point_reference.clear_energy)<0.003,"point-sun diffuse energy matches the independent BRDF reference")
	angular_radius=0.04
	var small:=await measure("terrain-small-disk")
	check(small.cache.refreshes==point.cache.refreshes+1,"changing only angular radius refreshes self-terrain visibility")
	check(small.edge.maximum<0.001,"a disk that stays below the cliff edge preserves full occlusion")
	check(small.cache.maximum<0.0001,"the small disk retains a fully occluded cache sample")
	angular_radius=LARGE_RADIUS
	var soft:=await measure("terrain-large-disk")
	var soft_bytes:=cache_bytes.duplicate()
	check(soft.cache.refreshes==small.cache.refreshes+1,"enlarging the sun refreshes the cache again without changing direction")
	check(soft.cache.minimum>0.2 and soft.cache.maximum<0.8,"self-terrain vertex visibility becomes a partial shadow")
	check(absf(soft.cache.mean-soft_reference.visibility)<0.14,"cached partial shadow agrees with independent dense disk quadrature")
	var normalized: float=soft.edge.mean/soft.clear.mean
	check(normalized>0.2 and normalized<0.8,"the terrain penumbra is visible in raw diffuse sunlight")
	check(absf(normalized-soft_reference.visibility)<0.14,"raw terrain penumbra agrees with the independent angular visibility integral")
	check(absf(soft.clear.mean-soft_reference.clear_energy)<0.003,"unoccluded raw sunlight retains the ordinary disk-sampled diffuse BRDF")
	check(point.clear.mean-soft.clear.mean>0.007,"the BRDF responds to disk width instead of using only the central direction")
	check(soft.dark.maximum<0.001,"fully shadowed same-component terrain stays dark for the larger sun")
	check(soft.cache.input_id==point.cache.input_id and soft.cache.output_id==point.cache.output_id,
		"angular changes update stable cache buffers without replacing descriptors")
	var repeated:=await measure("terrain-large-disk-repeat")
	check(repeated.cache.refreshes==soft.cache.refreshes,"an unchanged disk reuses its cached terrain visibility")
	check(cache_bytes==soft_bytes,"unchanged sun-disk visibility remains deterministic across frames")
	# The campaign clock turns the sun about 0.005 degrees per frame. That
	# drift reuses the cached visibility; a larger turn still retraces it.
	var original_direction:=sun_direction
	sun_direction=original_direction.rotated(Vector3.FORWARD,0.0005)
	var drift:=await measure("terrain-large-disk-drift")
	check(drift.cache.refreshes==soft.cache.refreshes,"a 0.03 degree sun drift reuses the cached terrain visibility")
	check(cache_bytes==soft_bytes,"the drifting sun keeps the cached values unchanged")
	sun_direction=original_direction.rotated(Vector3.FORWARD,0.004)
	var turned:=await measure("terrain-large-disk-turned")
	check(turned.cache.refreshes==soft.cache.refreshes+1,"a 0.23 degree sun turn refreshes the cache")
	sun_direction=original_direction
	angular_radius=0.0
	var restored:=await measure("terrain-point-restored")
	check(restored.cache.refreshes==turned.cache.refreshes+1,"returning to a point sun refreshes the cache")
	check(restored.edge.maximum<0.001 and restored.cache.maximum<0.0001,"restoring zero radius removes the terrain penumbra immediately")
	check(absf(restored.clear.mean-point.clear.mean)<0.0001,"restored point sunlight retains its original diffuse energy")
	check(await radius_fixture(false),"build the same shadow boundary with an ordinary object wall")
	var object_point:=await measure("object-point",{"ray_reconstruction":true,"rtxdi":false})
	check(object_point.cache.minimum>0.999,"ordinary objects do not enter self-terrain visibility")
	check(object_point.edge.maximum<0.001 and object_point.clear.minimum>0.65,"the ordinary wall casts the correct point-sun shadow")
	angular_radius=LARGE_RADIUS
	var object_soft:=await measure("object-large-disk")
	check(object_soft.cache.minimum>0.999,"object penumbrae retain exact per-pixel visibility")
	check(object_soft.edge.mean>0.15 and object_soft.edge.mean<0.5,"the ordinary object shadow responds to angular radius")
	check(absf(object_soft.edge.mean-soft_reference.object_energy)<0.03,"object shadow and BRDF samples match the independent joint disk integral")
	check(absf(object_soft.clear.mean-soft_reference.clear_energy)<0.003,"ordinary object shadows preserve clear-surface disk BRDF energy")
	angular_radius=0.0
	check((await measure("object-point-restored")).edge.maximum<0.001,"ordinary point-sun shadows return immediately after reducing radius")
	check(await radius_fixture(true,true),"build a 0.5 mm nonterrain contact over the terrain")
	var contact_point:=await measure("contact-point",{"ray_reconstruction":true,"rtxdi":false})
	check(contact_point.clear.maximum<0.001 and contact_point.edge.maximum<0.001,"thin object contact blocks point sunlight")
	angular_radius=LARGE_RADIUS
	var contact_soft:=await measure("contact-large-disk")
	check(contact_soft.clear.maximum<0.001 and contact_soft.edge.maximum<0.001,"thin object contact also blocks every sampled sun-disk direction")
	check(contact_soft.cache.minimum>0.2 and contact_soft.cache.maximum<0.8,"exact object occlusion remains separate from partial self-terrain visibility")
	RenderingServer.call_on_render_thread(device.dispose);await frames(4)
	var helper: RefCounted=device.get("terrain_sun")
	check(helper!=null and not helper._output.is_valid() and helper._owned.is_empty() and device._owned.is_empty(),
		"sun-disk cache resources are released with their scene")
	FileAccess.open(out.path_join("terrain-sun-radius.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,
		"failures":failures,"references":references,"measurements":report},"\t"))
	camera.queue_free();await frames();finish()
