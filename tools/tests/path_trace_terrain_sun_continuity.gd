extends "res://tools/tests/path_trace_contacts.gd"
## Actual adjoining cliff facets still had a hard sunlight jump after the
## bounded local-exit correction. Normalize raw sunlight against the exact
## same receivers without casters; neither RR nor NRD can hide the boundary.
const FIXTURE := "res://tools/tests/fixtures/path_trace_terrain_sun_continuity.json"
var cliff_fixture := {}
var reference_image: Image
var case_images := {}
var fixture_projection := Projection()
var fixture_view_projection := Projection()
var camera_base := Transform3D.IDENTITY
var receiver_transform := Transform3D.IDENTITY
var wall_instance := -1

func vector(values: Array) -> Vector3:
	return Vector3(float(values[0]),float(values[1]),float(values[2]))

func point(face: int, weights: Vector3) -> Vector3:
	var positions: PackedVector3Array=cliff_fixture.receivers[face].positions
	return receiver_transform*(positions[0]*weights.x+positions[1]*weights.y+positions[2]*weights.z)

func frame(history:=true,gi:=true,shadows:=true) -> PackedByteArray:
	var bytes:=super.frame(history,gi,shadows)
	# Freeze the analytic camera independently of the startup window resize.
	# All normalized captures and their sample pixels must use one projection.
	for entry in [[0,fixture_projection.inverse()],[32,fixture_view_projection],[148,fixture_view_projection.inverse()]]:
		var offset: int=entry[0]
		if offset*4+64>bytes.size():continue
		var matrix: Projection=entry[1]
		for axis in 4:
			for channel in 4:bytes.encode_float((offset+axis*4+channel)*4,matrix[axis][channel])
	# A point sun makes the continuity test deterministic and excludes solar
	# disk noise as a reason to blur or tolerate the original discontinuity.
	bytes.encode_float(71*4,0.0)
	return bytes

func append_triangles(records: Array, mask: int, terrain: bool, displacement:=Vector3.ZERO) -> void:
	var offset:=mesh_data.size()/16
	for record: Dictionary in records:
		for i in 3:
			var p: Vector3=record.positions[i]+displacement
			var n: Vector3=record.normals[i]
			mesh_data.append_array(PackedFloat32Array([p.x,p.y,p.z,0.5,n.x,n.y,n.z,0.5,1,1,1,1,0,0,0,0]))
	geometries.append({"offset":offset,"count":records.size()*3,"standard":true,"opaque":true,
		"terrain":terrain,"surface":Vector3(1,0,0)})
	placements.append({"geometry":geometries.size()-1,"transform":Transform3D.IDENTITY,"mask":mask})

func wall_triangles(distance: float) -> Array:
	var center: Vector3=(cliff_fixture.receivers[0].positions[0]+cliff_fixture.receivers[0].positions[1])*0.5+sun_direction*distance
	var u:=sun_direction.cross(Vector3.UP).normalized()*4.0
	var v:=sun_direction.cross(u).normalized()*4.0
	var a:=center-u-v;var b:=center-u+v;var c:=center+u+v;var d:=center+u-v
	var normals:=PackedVector3Array([-sun_direction,-sun_direction,-sun_direction])
	# Clockwise exterior facing the receiver, matching real terrain winding.
	return [{"positions":PackedVector3Array([a,c,b]),"normals":normals},
		{"positions":PackedVector3Array([a,d,c]),"normals":normals}]

func set_receiver_transform(transform: Transform3D) -> void:
	receiver_transform=transform
	camera.global_transform=transform*camera_base
	fixture_view_projection=fixture_projection*Projection(camera.global_transform.affine_inverse())

func geometry_pose(index: int, transform: Transform3D) -> PackedByteArray:
	var description: Dictionary=geometries[index]
	var values:=mesh_data.slice(description.offset*16,(description.offset+description.count)*16)
	var normal_transform:=transform.basis.inverse().transposed()
	for vertex: int in int(description.count):
		var at: int=vertex*16
		var p:=transform*Vector3(values[at],values[at+1],values[at+2])
		var n: Vector3=normal_transform*Vector3(values[at+4],values[at+5],values[at+6])
		for channel in 3:values[at+channel]=p[channel];values[at+4+channel]=n[channel]
	return values.to_byte_array()

func build_case(shadows: bool, object_distance:=0.0, terrain_wall:=false, extra: Dictionary={}) -> bool:
	if device!=null:RenderingServer.call_on_render_thread(device.dispose);await frames(4)
	mesh_data=PackedFloat32Array();geometries=[];placements=[]
	wall_instance=-1
	set_receiver_transform(extra.get("receiver_initial_transform",Transform3D.IDENTITY))
	append_triangles(cliff_fixture.receivers,7 if shadows else 1,true)
	var blockers: Array=cliff_fixture.blockers.duplicate(true)
	if extra.get("mixed_wall",false):
		blockers.append_array(wall_triangles(1.6));wall_instance=placements.size()
	append_triangles(blockers,6 if shadows else 0,true)
	if object_distance>0.0:
		# This extra plate is not terrain: smoothing terrain sunlight must not
		# move the exact object-shadow receiver past this 0.5 mm contact.
		append_triangles(cliff_fixture.receivers,6,false,sun_direction*object_distance)
	if terrain_wall or extra.get("foreign_wall",false):
		wall_instance=placements.size()
		append_triangles(wall_triangles(6.0 if terrain_wall else 1.6),6,true)
	for index in int(extra.get("decoys",0)):
		append_triangles(cliff_fixture.receivers,6,true,Vector3(40.0+index*10.0,0.0,40.0))
	var white:=Image.create(2,2,false,Image.FORMAT_RGBA8);white.fill(Color.WHITE)
	var images: Array[Image]=[white]
	device=PathDevice.new()
	if receiver_transform!=Transform3D.IDENTITY:
		device.initial_poses=[{"geometry":0,"data":geometry_pose(0,receiver_transform)}]
	RenderingServer.call_on_render_thread(device.build.bind(mesh_data.to_byte_array(),images,geometries,placements))
	return await device.prepared

func pixel_at(position: Vector3) -> Vector2i:
	var clip:=fixture_view_projection*Vector4(position.x,position.y,position.z,1.0)
	var uv:=Vector2(clip.x/clip.w*0.5+0.5,0.5-clip.y/clip.w*0.5)
	return Vector2i(clampi(int(uv.x*size.x),0,size.x-1),clampi(int(uv.y*size.y),0,size.y-1))

func visibility_at(image: Image, face: int, weights: Vector3) -> float:
	var p:=pixel_at(point(face,weights))
	return image.get_pixelv(p).r/maxf(reference_image.get_pixelv(p).r,0.00001)

func capture_sun(label: String, changes: Dictionary={}) -> Image:
	await capture(label,changes,false,6)
	var image:=raw.duplicate()
	image.save_exr(out.path_join(label+"-sun.exr"))
	case_images[label]=image
	return image

func edge_measurement(image: Image) -> Dictionary:
	var left:=0.0;var right:=0.0;var jump:=0.0;var worst:=0.0;var count:=0
	var pixels:={};var minimum_reference:=INF;var minimum_pixel_separation:=INF
	# Both facets reverse their first two shared vertices. Match the same
	# physical point along that edge, 2% inside each face, with many samples.
	for i in 32:
		var t:=lerpf(0.2,0.8,(i+0.5)/32.0)
		var a:=Vector3((1.0-t)*0.98,t*0.98,0.02)
		var b:=Vector3(t*0.98,(1.0-t)*0.98,0.02)
		var pa:=pixel_at(point(0,a));var pb:=pixel_at(point(1,b))
		pixels[pa]=true;pixels[pb]=true
		minimum_pixel_separation=minf(minimum_pixel_separation,Vector2(pa).distance_to(Vector2(pb)))
		minimum_reference=minf(minimum_reference,minf(reference_image.get_pixelv(pa).r,reference_image.get_pixelv(pb).r))
		var x:=visibility_at(image,0,a);var y:=visibility_at(image,1,b)
		left+=x;right+=y;jump+=absf(x-y);worst=maxf(worst,absf(x-y));count+=1
	return {"left":left/count,"right":right/count,"mean_jump":jump/count,"max_jump":worst,
		"unique_pixels":pixels.size(),"minimum_pixel_separation":minimum_pixel_separation,"minimum_reference":minimum_reference,
		"lit_anchor_reference":reference_image.get_pixelv(pixel_at(point(1,Vector3(0.05,0.05,0.9)))).r,
		"dark_anchor_reference":reference_image.get_pixelv(pixel_at(point(0,Vector3(0.05,0.05,0.9)))).r,
		"lit_anchor":visibility_at(image,1,Vector3(0.05,0.05,0.9)),
		"dark_anchor":visibility_at(image,0,Vector3(0.05,0.05,0.9))}

func blocked(row: Dictionary) -> bool:
	return maxf(maxf(row.left,row.right),maxf(row.lit_anchor,row.dark_anchor))<0.001

func unoccluded(row: Dictionary) -> bool:
	return minf(minf(row.left,row.right),minf(row.lit_anchor,row.dark_anchor))>0.9

func matches_field(row: Dictionary, expected: Dictionary) -> bool:
	for key: String in ["left","right","lit_anchor","dark_anchor"]:
		if absf(row[key]-expected[key])>0.03:return false
	return true

func measured(label: String, changes: Dictionary={}) -> Dictionary:
	var row:=edge_measurement(await capture_sun(label,changes));report[label+"-visibility"]=row
	return row

func live_component_checks(original: Dictionary) -> void:
	check(await build_case(true,0.0,false,{"foreign_wall":true,"decoys":3}),"build five disconnected terrain components")
	check(blocked(await measured("five-components")),"foreign terrain shadows stay exact with more than three components")
	var away:=Transform3D(Basis.IDENTITY,sun_direction.cross(Vector3.UP).normalized()*20.0)
	var changes:={"instances":[{"index":wall_instance,"transform":away,"mask":6}]}
	check(matches_field(await measured("foreign-wall-moved",changes),original),"moving a foreign terrain wall clears its exact shadow")
	changes={"instances":[{"index":wall_instance,"transform":Transform3D.IDENTITY,"mask":0}]}
	check(matches_field(await measured("foreign-wall-hidden-move",changes),original),"a masked foreign wall can move back without casting a shadow")
	changes={"instances":[{"index":wall_instance,"transform":Transform3D.IDENTITY,"mask":6}]}
	check(blocked(await measured("foreign-wall-shown",changes)),"showing the foreign wall restores its exact shadow immediately")
	changes={"instances":[{"index":wall_instance,"transform":Transform3D.IDENTITY,"mask":0}]}
	check(matches_field(await measured("foreign-wall-hidden",changes),original),"hiding the foreign wall removes its shadow immediately")
	check(await build_case(true,0.0,false,{"mixed_wall":true,"decoys":3}),"build self and foreign terrain components inside one placement")
	check(blocked(await measured("mixed-components")),"component filtering distinguishes foreign and self primitives within one placement")
	var original_sun:=sun_direction;var original_reference:=reference_image
	sun_direction=-vector(cliff_fixture.view_ray).normalized()
	check(await build_case(false),"build independent sunlight reference for the changed sun direction")
	var changed_reference:=await capture_sun("changed-sun-reference")
	reference_image=changed_reference
	var reference_row:=edge_measurement(changed_reference)
	check(minf(reference_row.minimum_reference,minf(reference_row.lit_anchor_reference,reference_row.dark_anchor_reference))>0.08,
		"changed-sun reference covers both facets and both anchors")
	sun_direction=original_sun;reference_image=original_reference
	check(await build_case(true),"build terrain for a live sunlight direction change")
	check(matches_field(await measured("live-sun-original"),original),"initial sun direction restores the same terrain visibility field")
	sun_direction=-vector(cliff_fixture.view_ray).normalized();reference_image=changed_reference
	check(unoccluded(await measured("live-sun-changed")),"changing the sun invalidates terrain visibility and lights the previously occluded corner")
	sun_direction=original_sun;reference_image=original_reference
	check(matches_field(await measured("live-sun-restored"),original),"restoring the sun restores the original terrain shadow field")
	# Initial poses reach the native vertex buffer before BLAS construction.
	# Posing the RECEIVERS requires the cache's first sample positions and
	# connectivity to use posed bytes too; moving only a foreign wall would
	# exercise the independent exact shadow query without testing this cache.
	# Rotate both the receivers and camera so the original world sun equals
	# the already measured changed-sun reference in their local coordinates.
	var local_sun: Vector3=-vector(cliff_fixture.view_ray).normalized()
	var rotation:=Basis(local_sun.cross(sun_direction).normalized(),acos(clampf(local_sun.dot(sun_direction),-1.0,1.0)))
	var center: Vector3=(cliff_fixture.receivers[0].positions[0]+cliff_fixture.receivers[0].positions[1])*0.5
	var displacement:=sun_direction.cross(Vector3.UP).normalized()*20.0
	var posed:=Transform3D(rotation,center+displacement-rotation*center)
	reference_image=changed_reference
	check(await build_case(true,0.0,false,{"receiver_initial_transform":posed}),"build initially posed receivers facing the sun away from their original blockers")
	check(unoccluded(await measured("initial-receiver-pose")),"the first sunlight cache uses initial receiver pose positions and connectivity")
	set_receiver_transform(Transform3D.IDENTITY);reference_image=original_reference
	check(matches_field(await measured("live-receiver-pose",{"poses":[{"geometry":0,"data":geometry_pose(0,Transform3D.IDENTITY)}]}),original),
		"a live receiver pose restores the original terrain visibility field")

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--audit-out="):out=arg.trim_prefix("--audit-out=")
	DirAccess.make_dir_recursive_absolute(out)
	cliff_fixture=JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	for key: String in ["receivers","blockers"]:
		for record: Dictionary in cliff_fixture[key]:
			for channel: String in ["positions","normals"]:
				var values:=PackedVector3Array()
				for item: Array in record[channel]:values.append(vector(item))
				record[channel]=values
	check(PathDevice.supported(),"qualified native terrain sunlight continuity device")
	if not PathDevice.supported():finish();return
	camera=Camera3D.new();add_child(camera);camera.current=true
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	var edge_a: Vector3=cliff_fixture.receivers[0].positions[0]
	var edge_b: Vector3=cliff_fixture.receivers[0].positions[1]
	var center: Vector3=(edge_a+edge_b)*0.5
	camera.position=center-vector(cliff_fixture.view_ray)*5.0
	camera.look_at(center,(edge_b-edge_a).normalized())
	camera_base=camera.global_transform
	# Use a tight view of the physical seam while retaining both opposite
	# corners for independent lit/shadowed controls.
	var half_y:=0.0;var half_x:=0.0
	for record: Dictionary in cliff_fixture.receivers:
		for p: Vector3 in record.positions:
			var delta:=p-center
			half_y=maxf(half_y,absf(delta.dot(camera.global_basis.y)))
			half_x=maxf(half_x,absf(delta.dot(camera.global_basis.x)))
	size=Vector2i(512,384);spp=1;bounces=1;sky_energy=0.0;sun_energy=1.0
	var aspect:=float(size.x)/size.y
	camera.size=maxf(half_y,half_x/aspect)*2.4
	var half_height:=camera.size*0.5
	fixture_projection=Projection.create_orthogonal(-half_height*aspect,half_height*aspect,-half_height,half_height,camera.near,camera.far)
	fixture_view_projection=fixture_projection*Projection(camera.global_transform.affine_inverse())
	sun_direction=vector(cliff_fixture.sun_direction).normalized()
	check(await build_case(false),"build identical receivers without shadow casters")
	if not device._ready:finish();return
	reference_image=await capture_sun("unoccluded")
	check(await build_case(true),"build captured adjoining cliff facets and two terrain blockers")
	var lit:=await capture_sun("terrain")
	var edge:=edge_measurement(lit);report["continuity"]=edge
	check(edge.unique_pixels>=48 and edge.minimum_pixel_separation>=2.0,"continuity samples cover distinct pixels on both physical facets")
	check(minf(edge.minimum_reference,minf(edge.lit_anchor_reference,edge.dark_anchor_reference))>0.08,
		"both seam sides and both anchors have usable unoccluded sunlight")
	check(edge.mean_jump<0.12,"raw terrain sun visibility is continuous across the shared edge: "+str(edge))
	check(edge.max_jump<0.25,"no narrow hard sunlight strip survives along the shared edge")
	check(minf(edge.left,edge.right)>0.25,"continuous terrain visibility retains a nonblack shared edge")
	check(edge.lit_anchor>0.7,"the visible corner remains sunlit")
	check(edge.dark_anchor<0.2,"the real occluded corner stays shadowed")
	check(await build_case(true,0.0005),"build a 0.5 mm non-terrain contact over both receivers")
	var contact:=edge_measurement(await capture_sun("object-contact"));report["contact"]=contact
	check(maxf(contact.left,contact.right)<0.001 and contact.lit_anchor<0.001,"exact per-pixel object visibility preserves the thin contact shadow")
	check(await build_case(true,0.0,true),"build a separate distant terrain wall")
	var distant:=edge_measurement(await capture_sun("distant-terrain"));report["distant"]=distant
	check(maxf(distant.left,distant.right)<0.001 and distant.lit_anchor<0.001,"distant terrain still blocks the continuous sunlight field")
	await live_component_checks(edge)
	FileAccess.open(out.path_join("terrain-sun-continuity.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"measurements":report},"\t"))
	RenderingServer.call_on_render_thread(device.dispose);await frames(4)
	camera.queue_free();await frames();finish()
