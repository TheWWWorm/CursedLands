extends "res://tools/tests/path_trace_emitters.gd"
## Raw native lighting at thin contacts, finite light segments and transformed
## surfaces. Analytic lit/dark references bypass the reconstruction filter.
var contact_baseline:=false
var lamp_position:=Vector3.ZERO
var lamp_enabled:=false

func frame(history:=true,gi:=true,shadows:=true) -> PackedByteArray:
	var bytes:=super.frame(history,gi,shadows)
	bytes.encode_float(71*4,0.0)
	if lamp_enabled:
		for i in 3:bytes.encode_float((88+i)*4,lamp_position[i])
		bytes.encode_float(91*4,10.0)
		for i in 3:bytes.encode_float((116+i)*4,1.0)
	return bytes

func contact_fixture(height: float,transform:=Transform3D.IDENTITY,mode:="sun",half:=true,local_center:=Vector3.ZERO) -> bool:
	if device!=null:RenderingServer.call_on_render_thread(device.dispose);await frames(4)
	mesh_data=PackedFloat32Array();geometries=[];placements=[]
	var floor_points: Array[Vector3]=[Vector3(-5,0,-5),Vector3(5,0,-5),Vector3(5,0,5),Vector3(-5,0,5)]
	for i in 4:floor_points[i]+=local_center
	quad(mesh_data,floor_points,Vector3.UP,Vector3.ZERO)
	geometries.append({"offset":0,"count":6,"standard":true,"opaque":true,"surface":Vector3(0.08,1,0.5) if mode=="glossy" else Vector3(1,0,0)})
	placements.append({"geometry":0,"transform":transform,"mask":7})
	if height>0:
		var right:=0.0 if half else 5.0
		var roof_points: Array[Vector3]=[Vector3(-5,height,-5),Vector3(right,height,-5),Vector3(right,height,5),Vector3(-5,height,5)]
		for i in 4:roof_points[i]+=local_center
		quad(mesh_data,roof_points,Vector3.DOWN,Vector3.ONE if mode=="glossy" else Vector3.ZERO)
		# A black plate isolates occlusion from reflected direct illumination.
		for i in range(6,12):
			for channel in 3:mesh_data[i*16+8+channel]=0.0
		geometries.append({"offset":6,"count":6,"standard":true,"opaque":true,"surface":Vector3(1,0,0)})
		placements.append({"geometry":1,"transform":transform,"mask":6})
	if mode=="emitter":
		quad(mesh_data,[Vector3(-5,2,-5),Vector3(5,2,-5),Vector3(5,2,5),Vector3(-5,2,5)],Vector3.DOWN,Vector3.ONE)
		geometries.append({"offset":12,"count":6,"standard":true,"opaque":true,"surface":Vector3(1,0,0)})
		placements.append({"geometry":2,"transform":transform,"mask":4})
	var centre:=transform*local_center
	var normal: Vector3=(transform.basis.inverse().transposed()*Vector3.UP).normalized()
	var tangent:=transform.basis.x.normalized()
	camera.position=centre+normal*2.0;camera.look_at(centre,-tangent.cross(normal).normalized())
	sun_direction=normal;sun_energy=1.0 if mode=="sun" else 0.0
	sky_energy=1.0 if mode=="sky" else 0.0
	lamp_enabled=mode=="lamp";lamp_position=centre+normal
	var white:=Image.create(2,2,false,Image.FORMAT_RGBA8);white.fill(Color.WHITE)
	var images: Array[Image]=[white]
	device=PathDevice.new();RenderingServer.call_on_render_thread(device.build.bind(mesh_data.to_byte_array(),images,geometries,placements))
	return await device.prepared

func half_means(image: Image) -> Array:
	var sums: Array=[0.0,0.0];var counts: Array=[0,0]
	# Ignore the contact edge and viewport margins; no blur is involved.
	for y in range(size.y/4,size.y*3/4):
		for x in range(size.x/8,size.x*7/8):
			if absi(x-size.x/2)<size.x/8:continue
			var side:=0 if x<size.x/2 else 1
			sums[side]+=image.get_pixel(x,y).r;counts[side]+=1
	return [sums[0]/counts[0],sums[1]/counts[1]]

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--audit-out="):out=arg.trim_prefix("--audit-out=")
		if arg=="--contact-baseline":contact_baseline=true
	DirAccess.make_dir_recursive_absolute(out)
	check(PathDevice.supported(),"qualified native contact-lighting device")
	if not PathDevice.supported():finish();return
	camera=Camera3D.new();add_child(camera);camera.current=true;camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=0.8
	size=Vector2i(256,144);spp=4;bounces=1
	for height in [0.005,0.0005]:
		var label:="sun-contact-"+str(height)
		check(await contact_fixture(height),"build "+label)
		var row:=await capture(label);row["halves"]=half_means(raw)
		check(row.halves[1]>0.99,label+": uncovered floor remains lit")
		if not contact_baseline:check(row.halves[0]<0.001,label+": thin plate keeps its contact shadow")
	check(await contact_fixture(0.005,Transform3D.IDENTITY,"sky",false),"build thin indirect-light blocker")
	var sky:=await capture("sky-contact")
	if not contact_baseline:check(sky.mean[0]<0.001,"thin plate blocks sky paths without light leaks")
	check(await contact_fixture(0.005,Transform3D.IDENTITY,"emitter",false),"build thin blocker below sampled emissive area")
	var emission:=await capture("emitter-contact")
	if not contact_baseline:check(emission.mean[0]<0.001,"thin plate blocks both sampled emissive and BSDF paths")
	check(await contact_fixture(0.005,Transform3D.IDENTITY,"glossy",false),"build nearby emissive reflection")
	var glossy:=await capture("glossy-contact",{},false,2)
	if not contact_baseline:check(glossy.mean[0]>0.98 and glossy.mean[0]<1.02,"glossy rays retain nearby emissive surfaces")
	# Analytic point light at y=1: a plate 5 mm before it blocks the segment;
	# the same plate 5 mm beyond it must not cast a shadow.
	for height in [0.995,1.005]:
		var label:="point-endpoint-"+str(height)
		check(await contact_fixture(height,Transform3D.IDENTITY,"lamp",false),"build "+label)
		var row:=await capture(label)
		if height>1.0:check(row.mean[0]>0.85,label+": geometry beyond the light stays unshadowed")
		elif not contact_baseline:check(row.mean[0]<0.001,label+": geometry just before the light occludes it")
	var rotated:=Basis.from_euler(Vector3(0.4,-0.7,0.3)).scaled(Vector3(0.4,2.0,1.3))
	var sheared:=Basis(Vector3(1,0.4,0),Vector3(0.2,2,0.3),Vector3(0.3,0,0.6))
	var cases: Array=[
		{"name":"origin","transform":Transform3D.IDENTITY,"local":Vector3.ZERO},
		{"name":"translated","transform":Transform3D(Basis.IDENTITY,Vector3(2048,-512,1024)),"local":Vector3.ZERO},
		{"name":"scaled-rotated","transform":Transform3D(rotated,Vector3(-2048,512,-1024)),"local":Vector3.ZERO},
		{"name":"sheared","transform":Transform3D(sheared,Vector3(512,128,-2048)),"local":Vector3.ZERO},
		{"name":"mirrored","transform":Transform3D(rotated.scaled(Vector3(-1,1,1)),Vector3(1024,-128,256)),"local":Vector3.ZERO},
		{"name":"remote-vertices","transform":Transform3D(Basis.IDENTITY,Vector3(-32768,32768,-16384)),"local":Vector3(32768,-32768,16384)}]
	for test: Dictionary in cases:
		check(await contact_fixture(0,test.transform,"sun",true,test.local),"build self-intersection case "+test.name)
		var normal:=sun_direction
		for grazing: bool in [false,true]:
			var label: String=test.name+("-grazing" if grazing else "-normal")
			if grazing:sun_direction=(normal*0.05+test.transform.basis.x.normalized()*sqrt(1.0-0.05*0.05)).normalized()
			var expected:=normal.dot(sun_direction)*(1.0-pow(1.0-normal.dot((normal+sun_direction).normalized()),5))
			var row:=await capture(label);row["reference"]=expected
			check(absf(row.mean[0]-expected)<expected*0.01,label+": no self-shadowing energy loss")
			check(row.dark_fraction<0.001,label+": no black self-intersection speckles")
		if test.name in ["translated","scaled-rotated","sheared","mirrored"]:
			check(await contact_fixture(0.005,test.transform),"build transformed contact "+test.name)
			var row:=await capture(test.name+"-contact");row["halves"]=half_means(raw)
			check(row.halves[1]>0.98,test.name+": transformed uncovered surface remains lit")
			if not contact_baseline:check(row.halves[0]<0.001,test.name+": transformed thin plate keeps its contact shadow")
	RenderingServer.call_on_render_thread(device.dispose);await frames(8)
	FileAccess.open(out.path_join("path-contacts.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"baseline":contact_baseline,"metrics":report},"\t"))
	camera.queue_free();finish()
