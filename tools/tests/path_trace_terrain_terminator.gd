extends "res://tools/tests/path_trace_contacts.gd"
## A shared smooth lighting field crosses two coarse terrain facets whose
## geometric sun hemispheres differ. Inspect raw light, before any denoiser.
const RIDGE_SLOPE := 0.06
const LIGHTING_NORMAL := Vector3(0.45,0,0.89302855)
const SUN_DIRECTION := Vector3(1,0,0.02)

# Minimal FP32 geometry from the actual north-cliff same-triangle self-hits.
# Provenance: native DX12 diagnostic 3c5ede9bbfba4c8c, shader SHA-256
# 2d08c399b758042b538c6e21de4b5fe8eddca36c1c4b3454456664e5ee52e610.
# Full captures: local/validation/pt-terrain-shadow-fix-20261028/
# terminator-hit-diagnostic; source fixture: diagnostics/failing-triangles.json.
# A positive smooth-normal lift still re-intersects these source primitives.
const NATIVE_SELF_HITS := [
	{"name":"native-11-198","vertices":[Vector3(49.91666793823242,14.2247896194458,-161.17559814453125),Vector3(49.66666793823242,13.51664924621582,-161.47817993164062),Vector3(49.94444274902344,14.353421211242676,-161.4503936767578)],
		"normals":[Vector3(-0.6590672731399536,0.30905935168266296,-0.6856476068496704),Vector3(-0.4952945113182068,0.4503357410430908,-0.742887020111084),Vector3(-0.5919986367225647,0.3290173411369324,-0.7357208728790283)],
		"weights":Vector3(0.35139191354491073,0.4997108532453649,0.1488972332097244),"view_ray":Vector3(0.5239559665309987,-0.8398457255228371,-0.1418777729511793),
		"sun":Vector3(0.5197539624575495,0.7866933316167265,-0.3331207296153323)},
	{"name":"native-7-4331","vertices":[Vector3(51.869049072265625,17.487464904785156,-156.86904907226562),Vector3(51.0,17.375581741333008,-158.0),Vector3(52.0,18.82234764099121,-158.0)],
		"normals":[Vector3(-0.5377019047737122,0.7235988974571228,0.4327601194381714),Vector3(-0.7001036405563354,0.6981033682823181,0.1500222235918045),Vector3(-0.5729822516441345,0.7019782662391663,0.4229868948459625)],
		"weights":Vector3(0.450246186953391,0.39086455613524385,0.15888925691136513),"view_ray":Vector3(0.5736683900603523,-0.8145712913702486,-0.08589638828826769),
		"sun":Vector3(0.5206456780049267,0.7844551457495799,-0.3369839792657734)},
	{"name":"native-7-4031","vertices":[Vector3(53.85714340209961,17.388980865478516,-154.86904907226562),Vector3(52.869049072265625,17.361848831176758,-155.86904907226562),Vector3(54.10714340209961,19.2343692779541,-156.14682006835938)],
		"normals":[Vector3(-0.6536843180656433,0.7526365518569946,-0.07896187156438828),Vector3(-0.4141317307949066,0.7682443261146545,0.4881552755832672),Vector3(-0.5741283297538757,0.6991562843322754,0.42609524726867676)],
		"weights":Vector3(0.1275617149320453,0.6437842969286377,0.228653988139317),"view_ray":Vector3(0.5938857889493652,-0.802436099380649,-0.0582750040305384),
		"sun":Vector3(0.5185678521053054,0.7866459769092554,-0.3350753493997627)}
]

var ridge_transform := Transform3D.IDENTITY
var lighting_normal_world := LIGHTING_NORMAL
var sun_image: Image
var normal_image: Image

func ridge_point(x: float,y: float) -> Vector3:
	return Vector3(x,y,-absf(x)*RIDGE_SLOPE)

func clockwise_terrain_triangles(offset: int, count: int) -> void:
	# Godot terrain uses clockwise front faces, as do the captured native
	# triangles below. The shared quad helper emits counterclockwise faces.
	# Correct only this fixture's generated terrain format; positions, authored
	# normals, and all ordinary nonterrain control geometry remain unchanged.
	for vertex in range(offset,offset+count,3):
		for channel in 16:
			var value:=mesh_data[(vertex+1)*16+channel]
			mesh_data[(vertex+1)*16+channel]=mesh_data[(vertex+2)*16+channel]
			mesh_data[(vertex+2)*16+channel]=value

func ridge_fixture(terrain: bool, blocker_distance:=0.0, metal:=false, transform:=Transform3D.IDENTITY,
		distant_terrain:=false, terrain_wall_distance:=6.0, terrain_wall_backface:=false) -> bool:
	if device!=null:RenderingServer.call_on_render_thread(device.dispose);await frames(4)
	mesh_data=PackedFloat32Array();geometries=[];placements=[]
	ridge_transform=transform
	lighting_normal_world=(transform.basis.inverse().transposed()*LIGHTING_NORMAL).normalized()
	sun_direction=(transform.basis*SUN_DIRECTION).normalized()
	camera.position=transform*Vector3(0,0,5)
	camera.look_at(transform.origin,transform.basis.y.normalized())
	camera.size=3.0*maxf(transform.basis.x.length(),transform.basis.y.length())
	for side in 2:
		var x0:=-2.0 if side==0 else 0.0
		var x1:=0.0 if side==0 else 2.0
		quad(mesh_data,[ridge_point(x0,-2),ridge_point(x1,-2),ridge_point(x1,2),ridge_point(x0,2)],LIGHTING_NORMAL,Vector3.ZERO)
	if terrain:clockwise_terrain_triangles(0,12)
	# One terrain placement owns both adjoining facets, as a gathered terrain
	# patch does. Its shared vertex normals are deliberately independent of Ng.
	geometries.append({"offset":0,"count":12,"standard":true,"opaque":true,"terrain":terrain,
		"surface":Vector3(0.4,1,0.5) if metal else Vector3(1,0,0)})
	placements.append({"geometry":0,"transform":transform,"mask":7})
	if blocker_distance>0:
		var displacement:=(transform.basis.inverse()*sun_direction)*blocker_distance
		for side in 2:
			var x0:=-2.0 if side==0 else 0.0
			var x1:=0.0 if side==0 else 2.0
			quad(mesh_data,[ridge_point(x0,-2)+displacement,ridge_point(x1,-2)+displacement,
				ridge_point(x1,2)+displacement,ridge_point(x0,2)+displacement],-LIGHTING_NORMAL,Vector3.ZERO)
		for vertex in range(12,24):
			for channel in 3:mesh_data[vertex*16+8+channel]=0.0
		# Real nearby geometry remains in the shadow BVH, even though it is
		# hidden from the primary camera. Moving a ray origin must not skip it.
		geometries.append({"offset":12,"count":12,"standard":true,"opaque":true,"surface":Vector3(1,0,0)})
		placements.append({"geometry":1,"transform":transform,"mask":6})
	if distant_terrain:
		var offset:=mesh_data.size()/16
		var direction:=SUN_DIRECTION.normalized()
		var centre:=direction*terrain_wall_distance
		var u:=Vector3.UP*4.0;var v:=direction.cross(Vector3.UP).normalized()*4.0
		# A separate terrain placement is a real hill/wall occluder, not the
		# receiver's own coarse facet. Exercise both front and back faces.
		if terrain_wall_backface:
			quad(mesh_data,[centre-u-v,centre+u-v,centre+u+v,centre-u+v],direction,Vector3.ZERO)
		else:
			quad(mesh_data,[centre-u-v,centre-u+v,centre+u+v,centre+u-v],-direction,Vector3.ZERO)
		clockwise_terrain_triangles(offset,6)
		for vertex in range(offset,offset+6):
			for channel in 3:mesh_data[vertex*16+8+channel]=0.0
		geometries.append({"offset":offset,"count":6,"standard":true,"opaque":true,"terrain":true,"surface":Vector3(1,0,0)})
		placements.append({"geometry":geometries.size()-1,"transform":transform,"mask":6})
	var white:=Image.create(2,2,false,Image.FORMAT_RGBA8);white.fill(Color.WHITE)
	var images: Array[Image]=[white]
	device=PathDevice.new()
	RenderingServer.call_on_render_thread(device.build.bind(mesh_data.to_byte_array(),images,geometries,placements))
	return await device.prepared

func patch_statistics(image: Image, side: int) -> Dictionary:
	var total:=0.0;var minimum:=INF;var maximum:=0.0;var dark:=0;var count:=0
	# Sample face interiors, excluding silhouettes, the ridge and the quad's
	# outer edges. World-space points make this independent of viewport size.
	for iy in 24:
		for ix in 24:
			var x:=lerpf(-1.6,-0.4,(ix+0.5)/24.0) if side==0 else lerpf(0.4,1.6,(ix+0.5)/24.0)
			var y:=lerpf(-0.8,0.8,(iy+0.5)/24.0)
			var uv:=camera.unproject_position(ridge_transform*ridge_point(x,y))/get_viewport().get_visible_rect().size
			var p:=Vector2i(clampi(int(uv.x*size.x),0,size.x-1),clampi(int(uv.y*size.y),0,size.y-1))
			var value:=image.get_pixelv(p).r
			total+=value;minimum=minf(minimum,value);maximum=maxf(maximum,value)
			if value<0.001:dark+=1
			count+=1
	return {"mean":total/count,"min":minimum,"max":maximum,"dark_fraction":float(dark)/count,"samples":count}

func ridge_capture(label: String) -> Dictionary:
	await capture(label,{},false,6)
	sun_image=raw.duplicate()
	normal_image=device.guide.get_image()
	var row:={"left":patch_statistics(sun_image,0),"right":patch_statistics(sun_image,1)}
	var a:=sample(device.guide,ridge_transform*ridge_point(-1,0));var b:=sample(device.guide,ridge_transform*ridge_point(1,0))
	var left_normal:=Vector3(a.r,a.g,a.b);var right_normal:=Vector3(b.r,b.g,b.b)
	row["normals"]=[[a.r,a.g,a.b],[b.r,b.g,b.b]]
	row["normal_distance"]=left_normal.distance_to(right_normal)
	check(a.a>0 and b.a>0,label+": both facet interiors are visible receivers")
	check(left_normal.is_finite() and right_normal.is_finite() and left_normal.dot(lighting_normal_world)>0.999 and right_normal.dot(lighting_normal_world)>0.999,
		label+": adjoining facets retain the same authored smooth lighting normal")
	report[label]=row
	sun_image.save_exr(out.path_join(label+"-sun.exr"))
	return row


func native_point(test: Dictionary, weights: Vector3) -> Vector3:
	return test.vertices[0]*weights.x+test.vertices[1]*weights.y+test.vertices[2]*weights.z

func native_normal(test: Dictionary, weights: Vector3) -> Vector3:
	return (test.normals[0]*weights.x+test.normals[1]*weights.y+test.normals[2]*weights.z).normalized()

func native_triangle_fixture(test: Dictionary, blocker_distance:=0.0) -> bool:
	if device!=null:RenderingServer.call_on_render_thread(device.dispose);await frames(4)
	mesh_data=PackedFloat32Array();geometries=[];placements=[]
	sun_direction=test.sun.normalized()
	var centre:=native_point(test,test.weights)
	camera.position=centre-test.view_ray*5.0
	camera.look_at(centre,Vector3.UP)
	var extent:=0.0
	for i in 3:extent=maxf(extent,test.vertices[i].distance_to(test.vertices[(i+1)%3]))
	camera.size=extent*0.3
	for surface in (2 if blocker_distance>0 else 1):
		for i in 3:
			var p: Vector3=test.vertices[i]+sun_direction*blocker_distance*surface
			var n: Vector3=test.normals[i] if surface==0 else -test.normals[i]
			var colour:=1.0 if surface==0 else 0.0
			mesh_data.append_array(PackedFloat32Array([p.x,p.y,p.z,0.5,n.x,n.y,n.z,0.5,
				colour,colour,colour,1,0,0,0,0]))
		geometries.append({"offset":surface*3,"count":3,"standard":true,"opaque":true,
			"terrain":surface==0,"surface":Vector3(1,0,0)})
		placements.append({"geometry":surface,"transform":Transform3D.IDENTITY,"mask":7 if surface==0 else 6})
	var white:=Image.create(2,2,false,Image.FORMAT_RGBA8);white.fill(Color.WHITE)
	var images: Array[Image]=[white]
	device=PathDevice.new()
	RenderingServer.call_on_render_thread(device.build.bind(mesh_data.to_byte_array(),images,geometries,placements))
	return await device.prepared

func native_triangle_capture(test: Dictionary, label: String) -> Dictionary:
	await capture(label,{},false,6)
	var guide:=device.guide.get_image()
	var pixels:={};var total:=0.0;var relative_total:=0.0
	var minimum:=INF;var maximum:=0.0;var dark:=0;var visible:=0;var normal_match:=1.0
	# A bounded barycentric patch around the recorded failing pixel excludes
	# every triangle edge. Deduplicate projected pixels so many world samples
	# cannot disguise a fixture that covers only one pixel.
	for iy in 24:
		for ix in 24:
			var weights: Vector3=test.weights
			weights.y+=lerpf(-0.04,0.04,(ix+0.5)/24.0)
			weights.z+=lerpf(-0.04,0.04,(iy+0.5)/24.0)
			weights.x=1.0-weights.y-weights.z
			var uv:=camera.unproject_position(native_point(test,weights))/get_viewport().get_visible_rect().size
			var p:=Vector2i(int(uv.x*size.x),int(uv.y*size.y))
			if p.x<0 or p.y<0 or p.x>=size.x or p.y>=size.y or pixels.has(p):continue
			pixels[p]=true
			var value:=raw.get_pixelv(p).r;var g:=guide.get_pixelv(p)
			var n:=Vector3(g.r,g.g,g.b)
			var nsl:=n.dot(sun_direction)
			if g.a>0.0 and n.is_finite() and nsl>0.05:visible+=1
			normal_match=minf(normal_match,n.dot(native_normal(test,weights)))
			total+=value;relative_total+=value/maxf(nsl,0.001)
			minimum=minf(minimum,value);maximum=maxf(maximum,value)
			if value<0.001:dark+=1
	var count:=pixels.size()
	var row:={"samples":count,"visible":visible,"mean":total/maxi(count,1),
		"mean_relative_nsl":relative_total/maxi(count,1),"min":minimum,"max":maximum,
		"dark_fraction":float(dark)/maxi(count,1),"minimum_normal_match":normal_match}
	check(count>=48 and visible==count,label+": barycentric patch contains visible sun-facing receiver pixels")
	check(normal_match>0.995,label+": guides retain captured authored vertex normals")
	report[label]=row
	raw.save_exr(out.path_join(label+"-sun.exr"));guide.save_exr(out.path_join(label+"-guide.exr"))
	return row

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--audit-out="):out=arg.trim_prefix("--audit-out=")
	DirAccess.make_dir_recursive_absolute(out)
	check(PathDevice.supported(),"qualified native terrain terminator device")
	if not PathDevice.supported():finish();return
	camera=Camera3D.new();add_child(camera);camera.current=true
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=3
	camera.position=Vector3(0,0,5);camera.look_at(Vector3.ZERO)
	size=Vector2i(256,144);spp=1;bounces=1;sky_energy=0;sun_energy=1
	sun_direction=SUN_DIRECTION.normalized()
	var face_left:=Vector3(-RIDGE_SLOPE,0,1).normalized()
	var face_right:=Vector3(RIDGE_SLOPE,0,1).normalized()
	check(face_left.dot(sun_direction)<-0.03 and face_right.dot(sun_direction)>0.07 and LIGHTING_NORMAL.dot(sun_direction)>0.45,
		"fixture crosses geometric light hemisphere while its smooth lighting field remains sunlit")
	check(await ridge_fixture(true),"build adjoining terrain facets with shared authored normals")
	var lit:=await ridge_capture("terrain-lit")
	check(lit.left.mean>0.15 and lit.right.mean>0.15,"both smooth terrain facets receive sunlight at the geometric terminator")
	check(minf(lit.left.mean,lit.right.mean)>maxf(lit.left.mean,lit.right.mean)*0.8,
		"crossing an internal facet boundary does not create a dark wedge")
	check(lit.left.dark_fraction<0.01 and lit.right.dark_fraction<0.01,"unoccluded terrain light has no black facet interiors")
	# Duplicate black plates sit along the actual light segments. A broad
	# terrain ray bias that removes real nearby contacts must fail this test.
	for distance in [0.0005,0.005]:
		var label:="terrain-contact-"+str(distance)
		check(await ridge_fixture(true,distance),"build "+label)
		var contact:=await ridge_capture(label)
		check(contact.left.max<0.001 and contact.right.max<0.001,label+": separate thin geometry still blocks both terrain facets")
	check(await ridge_fixture(true,0.0,false,Transform3D.IDENTITY,true),"build distant terrain occluder")
	var terrain_shadow:=await ridge_capture("terrain-distant-occluder")
	check(terrain_shadow.left.max<0.001 and terrain_shadow.right.max<0.001,
		"a distant terrain wall still shadows both receiver facets")
	# A bounded local exit correction may bypass a nearby terrain back face,
	# but must still stop at a near front face and a distant back face. These
	# distances cover every sample in patch_statistics, not just its centre.
	for wall in [{"name":"terrain-near-front-occluder","distance":1.6,"backface":false},
		{"name":"terrain-distant-back-occluder","distance":6.0,"backface":true}]:
		var direction:=SUN_DIRECTION.normalized()
		var distances:=[wall.distance-direction.dot(ridge_point(-1.575,0)),
			wall.distance-direction.dot(ridge_point(1.575,0))]
		var nearest: float=minf(distances[0],distances[1]);var farthest: float=maxf(distances[0],distances[1])
		check(nearest>3.2 if wall.backface else nearest>0 and farthest<3.2,
			wall.name+": sampled shadow segments lie on the intended side of the local exit limit")
		check(await ridge_fixture(true,0.0,false,Transform3D.IDENTITY,true,wall.distance,wall.backface),"build "+wall.name)
		var blocked_wall:=await ridge_capture(wall.name)
		blocked_wall["segment_range"]=[nearest,farthest]
		check(blocked_wall.left.max<0.001 and blocked_wall.right.max<0.001,
			wall.name+": real terrain still occludes both receiver facets")
	check(await ridge_fixture(true),"build terrain facing away from the sun")
	sun_direction=-lighting_normal_world
	var backlit:=await ridge_capture("terrain-below-shading-horizon")
	check(backlit.left.max<0.001 and backlit.right.max<0.001,
		"terrain receives no sunlight below its authored shading hemisphere")
	# The correction follows world-space geometry, including orientation,
	# nonuniform scale and a mirrored placement, rather than a fixed up axis.
	var rotated:=Basis.from_euler(Vector3(0.25,-0.4,0.15)).scaled(Vector3(-1.4,0.7,0.9))
	for test in [{"name":"translated","transform":Transform3D(Basis.IDENTITY,Vector3(64,-16,32))},
		{"name":"rotated-scaled-mirrored","transform":Transform3D(rotated,Vector3(-23,11,-7))}]:
		var label: String="terrain-"+test.name
		check(await ridge_fixture(true,0.0,false,test.transform),"build "+label)
		var transformed:=await ridge_capture(label)
		var expected:=lighting_normal_world.dot(sun_direction)
		check(expected>0.1 and minf(transformed.left.mean,transformed.right.mean)>expected*0.3,
			label+": both transformed facets retain nonzero smooth sunlight")
		check(minf(transformed.left.mean,transformed.right.mean)>maxf(transformed.left.mean,transformed.right.mean)*0.8,
			label+": transformed facet boundary remains continuous")
		check(await ridge_fixture(true,0.0,false,test.transform,true),"build "+label+" distant terrain blocker")
		var blocked:=await ridge_capture(label+"-occluded")
		check(blocked.left.max<0.001 and blocked.right.max<0.001,
			label+": transformed distant terrain still occludes real sunlight")
	# A terrain-specific correction must not turn ordinary one-sided diffuse
	# or metallic surfaces into emitters on their geometric back hemisphere.
	for metal in [false,true]:
		var label:="nonterrain-metal" if metal else "nonterrain-diffuse"
		check(await ridge_fixture(false,0.0,metal),"build "+label)
		var ordinary:=await ridge_capture(label)
		check(ordinary.left.max<0.001,label+": geometric back hemisphere remains dark")
		if metal:
			check(ordinary.right.max<0.001,"metal retains no diffuse sunlight lobe")
			RenderingServer.call_on_render_thread(read_raw.bind(2));await captured
			var left_specular:=patch_statistics(raw,0);var right_specular:=patch_statistics(raw,1)
			ordinary["specular"]={"left":left_specular,"right":right_specular}
			check(left_specular.max<0.001 and right_specular.mean>0.001,"ordinary metal keeps one-sided glossy transport")
		else:check(ordinary.right.mean>0.15,"ordinary front hemisphere remains illuminated")
	# These real terrain triangles expose same-primitive self-hits that a
	# two-facet constant-normal synthetic ridge does not cover.
	for test: Dictionary in NATIVE_SELF_HITS:
		var label: String=test.name
		var geometric: Vector3=(test.vertices[1]-test.vertices[0]).cross(test.vertices[2]-test.vertices[0]).normalized()
		if geometric.dot(-test.view_ray)<0:geometric=-geometric
		check(geometric.dot(test.sun)<-0.1 and native_normal(test,test.weights).dot(test.sun)>0.1,
			label+": captured geometric and authored sun hemispheres disagree")
		check(await native_triangle_fixture(test),"build captured terrain triangle "+label)
		var lit_triangle:=await native_triangle_capture(test,label+"-lit")
		check(lit_triangle.mean_relative_nsl>0.5,label+": unoccluded raw sunlight follows authored normal incidence")
		check(lit_triangle.dark_fraction<0.01,label+": no black interior from source-triangle self-intersection")
		check(await native_triangle_fixture(test,0.005),"build captured triangle with 5 mm nonterrain blocker "+label)
		var blocked_triangle:=await native_triangle_capture(test,label+"-contact")
		check(blocked_triangle.max<0.001,label+": nearby nonterrain geometry retains its contact shadow")
	RenderingServer.call_on_render_thread(device.dispose);await frames(8)
	FileAccess.open(out.path_join("terrain-terminator.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"metrics":report},"\t"))
	camera.queue_free();finish()
