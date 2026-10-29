extends "res://tools/tests/path_trace_transmission.gd"
## The refraction pass finds dielectrics on their own ray mask and asks
## separately whether opaque geometry stands in front. Reused stationary frames
## skip pixels without a dielectric; any view or scene change traces them again.
func classification(image: Image,row: int) -> Dictionary:
	var left:=0;var right:=0;var edge:=-1
	for x in image.get_width():
		var dielectric:=image.get_pixel(x,row).a>.5
		if x<size.x/2-4 and dielectric:left+=1
		if x>size.x/2+4 and dielectric:right+=1
		if edge<0 and dielectric:edge=x
	return {"left":left,"right":right,"edge":edge}

func wall(mask: int,offset:=Vector3.ZERO) -> Dictionary:
	return {"index":2,"transform":Transform3D(Basis.IDENTITY,offset),"mask":mask}

## One frame that keeps the controller's history flag set, unlike the first
## frame of render_many, so only the view, the scene or the flag itself resets.
func render_one(changes:={},history:=true) -> void:
	RenderingServer.call_on_render_thread(device.render.bind(size,frame(history),changes))
	await frames(2);await RenderingServer.frame_post_draw

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--audit-out="):out=arg.trim_prefix("--audit-out=")
	DirAccess.make_dir_recursive_absolute(out);Gfx.ensure_globals()
	check(PathDevice.supported(),"qualified dielectric renderer")
	if not PathDevice.supported():finish();return
	camera=Camera3D.new();add_child(camera);camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=2;camera.position=Vector3(0,4,4);camera.look_at(Vector3.ZERO);camera.current=true
	size=Vector2i(160,90);sun_energy=0;sky_energy=0;bounces=1
	mesh_data=PackedFloat32Array();geometries=[];placements=[]
	quad(mesh_data,[Vector3(-20,-2,-20),Vector3(20,-2,-20),Vector3(20,-2,20),Vector3(-20,-2,20)],Vector3.UP,Vector3.ONE)
	for i in 6:
		for c in 3:mesh_data[i*16+8+c]=0.0
	quad(mesh_data,[Vector3(-20,0,-20),Vector3(20,0,-20),Vector3(20,0,20),Vector3(-20,0,20)],Vector3.UP,Vector3.ZERO)
	# An opaque wall in front of the left half of the water, between the camera and the surface.
	quad(mesh_data,[Vector3(-20,-20,1.5),Vector3(-20,20,1.5),Vector3(0,20,1.5),Vector3(0,-20,1.5)],Vector3.BACK,Vector3.ZERO)
	geometries=[{"offset":0,"count":6,"standard":true,"opaque":true},
		{"offset":6,"count":6,"standard":true,"opaque":true,"dielectric":PackedFloat32Array([.4,.1,.02,1.333,1,1,0,0])},
		{"offset":12,"count":6,"standard":true,"opaque":true}]
	placements=[{"geometry":0,"transform":Transform3D.IDENTITY,"mask":7},{"geometry":1,"transform":Transform3D.IDENTITY,"mask":5},
		{"geometry":2,"transform":Transform3D.IDENTITY,"mask":7}]
	check(await build_fixture(),"build water behind a half-width opaque wall")
	await render_many(4,{"transmission":true})
	if not device.transmission.active:
		check(false,"dielectric pass must initialize before readback")
		RenderingServer.call_on_render_thread(device.dispose);await frames(8);finish();return
	check(device._instances[2].mask==(7|16) and device._instances[1].mask==8,"the wall keeps the opaque camera mask and the water its dielectric mask")
	var row:=size.y/2
	var covered:=classification(device.transmission.colour.get_image(),row)
	observations.append({"stage":"wall","classification":covered})
	check(covered.left==0 and covered.right>=size.x/2-5,"water behind the opaque wall is not displayed while the open half is: "+str(covered))
	var open_colour: Color=device.transmission.colour.get_image().get_pixel(size.x*3/4,row)
	check(open_colour.r>0 and open_colour.b>open_colour.r and is_finite(open_colour.r+open_colour.g+open_colour.b),"the open half refracts the lit bed: "+str(open_colour))
	var depth: float=device.transmission.guide.get_image().get_pixel(size.x*3/4,row).a
	check(depth>0,"the open half publishes its water depth")
	# Reused frames keep the classification and the published depth exactly.
	await render_many(4)
	check(device.transmission.history>=3,"stationary refraction reuses its history")
	var still:=classification(device.transmission.colour.get_image(),row)
	check(still.left==covered.left and still.right==covered.right and still.edge==covered.edge,"reused frames keep the occlusion classification: "+str(still))
	check(device.transmission.guide.get_image().get_pixel(size.x*3/4,row).a==depth,"reused frames keep the published depth")
	check(device.transmission.guide.get_image().get_pixel(size.x/4,row).a==0 and device.transmission.colour.get_image().get_pixel(size.x/4,row).a==0,"occluded pixels stay empty across reused frames")
	# Removing the wall exposes the water at once; restoring it hides it again.
	await render_one({"instances":[wall(0)]})
	var exposed:=classification(device.transmission.colour.get_image(),row)
	observations.append({"stage":"wall hidden","classification":exposed})
	check(device.transmission.history==1 and exposed.left>=size.x/2-5 and exposed.right==still.right,"hiding the wall exposes the water behind it in the same frame: "+str(exposed))
	await render_one({"instances":[wall(7)]})
	var restored:=classification(device.transmission.colour.get_image(),row)
	check(restored.left==0 and restored.edge==covered.edge,"restoring the wall hides the water again: "+str(restored))
	# Moving the wall forward of the camera plane no longer blocks the view.
	await render_one({"instances":[wall(7,Vector3(0,0,20))]})
	check(classification(device.transmission.colour.get_image(),row).left>=size.x/2-5,"a wall behind the camera does not occlude")
	await render_one({"instances":[wall(7)]})
	# A small camera move resets the history and shifts the wall edge.
	for i in 3:await render_one()
	check(device.transmission.history==4,"the restored scene accumulates again: "+str(device.transmission.history))
	camera.position.x+=.1;await render_one()
	var moved:=classification(device.transmission.colour.get_image(),row)
	observations.append({"stage":"camera moved","classification":moved})
	# A 0.1 m sideways step is about 4.5 pixels of this orthographic frame.
	check(device.transmission.history==1 and moved.edge<covered.edge-2 and moved.edge>covered.edge-8,"a camera move retraces every pixel and shifts the wall edge: "+str(moved))
	await render_many(3)
	check(classification(device.transmission.colour.get_image(),row).edge==moved.edge,"the moved view keeps its new classification while reused")
	# Still frames trace one path each and remember up to 63 of them.
	await render_many(64)
	check(device.transmission.history==device.transmission.HISTORY_LIMIT and device.transmission.HISTORY_LIMIT==63,"a still view accumulates 63 single-path frames: "+str(device.transmission.history))
	var settled: Color=device.transmission.colour.get_image().get_pixel(size.x*3/4,row)
	check(settled.r>0 and settled.b>settled.r and is_finite(settled.r+settled.g+settled.b),"the long accumulation stays finite and lit: "+str(settled))
	# Lighting constants alone never reset the still view: daylight drift,
	# a new sky and local sources blend into the running mean. The frame's
	# history flag, cleared by the controller for abrupt changes, resets it.
	var resets: int=device.transmission.resets
	sun_energy=.4;sun_direction=Vector3(.3,1,.2).normalized();await render_one()
	sky_energy=.2;await render_one()
	points=true;await render_one()
	check(device.transmission.resets==resets and device.transmission.history==device.transmission.HISTORY_LIMIT,"sun, sky and local-light changes keep the transparent history (%d resets)"%(device.transmission.resets-resets))
	var lit: Color=device.transmission.colour.get_image().get_pixel(size.x*3/4,row)
	check(is_finite(lit.r+lit.g+lit.b) and lit.r>=0,"the blended lit water stays finite: "+str(lit))
	await render_one({},false)
	check(device.transmission.resets==resets+1 and device.transmission.history==1,"the cleared history flag resets the transparent history")
	points=false;sun_energy=0;sky_energy=0;sun_direction=Vector3(1,1,0).normalized()
	RenderingServer.call_on_render_thread(device.dispose);await frames(8)
	FileAccess.open(out.path_join("path-transmission-occlusion.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"observations":observations},"\t"))
	camera.queue_free();await frames();finish()
