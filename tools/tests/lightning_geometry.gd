extends Node
## Compare complete native/legacy bolt geometry and RNG after each draw/tick.
## Includes all bolt kinds, both projections, camera offsets and arena origins.
var checks := 0
var failures := []
var samples := 0
var peak := 0.0
class OffsetFx extends ParticleFx:
	var origin := Vector3.ZERO
	func display_origin() -> Vector3: return origin
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures.append(label);push_error(label)
func _ready() -> void: run.call_deferred()
func run() -> void:
	check(ClassDB.class_exists("LightningGeometryKernel"),"native geometry available")
	if not failures.is_empty(): get_tree().quit(1);return
	var kernel: Object = ClassDB.instantiate("LightningGeometryKernel")
	var probe_vertices := PackedVector3Array([Vector3(-1,2,3),Vector3(4,-5,6),Vector3(7,8,-9)])
	var probe_uvs := PackedVector2Array([Vector2(.25,.5),Vector2(2,3),Vector2(-1,-2)])
	var probe_colors := PackedColorArray([Color(1,0,.5,1),Color(.2,.4,.6,.8),Color(-1,2,0,160.0/255.0)])
	var packed: Array = kernel.surface_data(probe_vertices,probe_uvs,probe_colors)
	check(packed.size()==3 and packed[0] == probe_vertices.to_byte_array(),"dynamic position encoding")
	for i in 3:
		check(packed[1].decode_float(i*12+4)==probe_uvs[i].x and packed[1].decode_float(i*12+8)==probe_uvs[i].y,"dynamic UV encoding")
		for channel in 4: check(packed[1][i*12+channel] == int(clampf(float(probe_colors[i][channel])*255.0,0,255)),"dynamic color matches engine truncation")
	check(packed[2] == AABB(Vector3(-1,-5,-9),Vector3(8,13,15)),"dynamic bounds enclose current positions")
	check(kernel.surface_data(probe_vertices,PackedVector2Array(),probe_colors).is_empty(),"truncated dynamic attributes rejected")
	probe_colors[0] = Color(NAN,0,0,1)
	check(kernel.surface_data(probe_vertices,probe_uvs,probe_colors).is_empty(),"nonfinite dynamic colors rejected")
	var rng := RandomNumberGenerator.new(); rng.seed = 918713
	var points := PackedVector3Array()
	for i in 512: points.append(Vector3(rng.randf_range(-2000,2000),rng.randf_range(-2000,2000),rng.randf_range(-2000,2000)))
	for origin in [Vector3.ZERO,Vector3(64,0,-128),Vector3(1000000,-500000,2000000)]:
		var expected := PackedVector3Array()
		for point in points: expected.append(Vector3(point.x,point.z,-point.y)+origin)
		var conversion := Transform3D(Basis(Vector3(1,0,0),Vector3(0,0,-1),Vector3(0,1,0)),origin)
		check(conversion * points == expected,"packed EI coordinate conversion is exact")
	var viewport := SubViewport.new();viewport.size=Vector2i(1280,720);viewport.own_world_3d=true;add_child(viewport)
	var camera := Camera3D.new();viewport.add_child(camera);camera.current=true
	var native_us:=0;var script_us:=0
	for mode in 3:
		camera.projection=mode;camera.size=48;camera.fov=63;camera.frustum_offset=Vector2(.2,.1)
		camera.h_offset=.3;camera.v_offset=.2
		camera.position=Vector3(20,24,30);camera.look_at(Vector3(4,1,-8))
		for param in [-7.0,0.0,7.0]:
			var fast_owner:=OffsetFx.new();var slow_owner:=OffsetFx.new()
			fast_owner.origin=[Vector3.ZERO,Vector3(64,0,-128),Vector3(-32,4,64)][mode]
			slow_owner.origin=fast_owner.origin
			viewport.add_child(fast_owner);viewport.add_child(slow_owner)
			fast_owner._rng.seed=7319;slow_owner._rng.seed=7319
			var fast:=FxLightning.new(fast_owner,Vector3(-.1,2,3),Vector3(12,13,6),param)
			var slow:=FxLightning.new(slow_owner,Vector3(-.1,2,3),Vector3(12,13,6),param,true)
			check(fast_owner._rng.state==slow_owner._rng.state,"initial branch RNG matches script")
			check(fast._bolts==slow._bolts,"initial branch descriptors match script")
			fast_owner.add_child(fast.node);slow_owner.add_child(slow.node)
			for index in 12:
				if index in [4,8]:
					fast.b = Vector3(40,23,9) if index == 4 else Vector3(4,3,4)
					slow.b = fast.b
				var fraction:=float(index%4)*.23
				fast.update_tick();slow.update_tick()
				var start:=Time.get_ticks_usec();fast.draw(fraction);native_us+=Time.get_ticks_usec()-start
				start=Time.get_ticks_usec();slow.draw(fraction);script_us+=Time.get_ticks_usec()-start
				check(fast_owner._rng.state==slow_owner._rng.state,"RNG retained %s/%s/%s"%[mode,param,index])
				check(fast.node.mesh.get_surface_count()==slow.node.mesh.get_surface_count(),"surface count")
				check(fast._buffer_layout,"dynamic layout matches the native encoder")
				for surface in slow.node.mesh.get_surface_count():
					var a:=fast.node.mesh.surface_get_arrays(surface);var b:=slow.node.mesh.surface_get_arrays(surface)
					check(a[Mesh.ARRAY_VERTEX].size()==b[Mesh.ARRAY_VERTEX].size(),"vertex count")
					var error:=0.0
					for vertex in b[Mesh.ARRAY_VERTEX].size():
						error=maxf(error,a[Mesh.ARRAY_VERTEX][vertex].distance_to(b[Mesh.ARRAY_VERTEX][vertex]))
						samples+=1
					peak=maxf(peak,error)
					check(error<0.00006,"positions %s/%s/%s (%.9f)"%[mode,param,index,error])
					check(a[Mesh.ARRAY_TEX_UV]==b[Mesh.ARRAY_TEX_UV],"identical UVs")
					check(a[Mesh.ARRAY_COLOR]==b[Mesh.ARRAY_COLOR],"identical colors")
					check(fast.node.mesh.surface_get_material(surface)==slow.node.mesh.surface_get_material(surface),"same material")
			fast_owner.free();slow_owner.free()
	for speed in [1.0,2.0]:
		Engine.time_scale=speed
		var world:=GameWorld.new();world.arena_overview=true
		var owner:=ParticleFx.new();owner.world=world;viewport.add_child(owner)
		var bolt:=FxLightning.new(owner,Vector3(1,2,3),Vector3(12,13,6),7.0);owner.add_child(bolt.node)
		bolt.draw(0)
		check(bolt.node.mesh.get_surface_count()==2,"overview shows the first flash at either speed")
		var state:=owner._rng.state;bolt._overview_draw_at=Time.get_ticks_usec()+1000000
		bolt.draw(0)
		check(owner._rng.state==state,"overview retains geometry until the next slot")
		bolt._overview_draw_at=Time.get_ticks_usec()-350000;bolt.draw(.5)
		check(bolt._overview_draw_at>Time.get_ticks_usec(),"overview resumes a future slot after a stall")
		owner.free();world.free()
	Engine.time_scale=1.0
	viewport.free()
	print("LIGHTNING_GEOMETRY ",JSON.stringify({"checks":checks,"failures":failures,"vertices":samples,"peak_error":peak,"native_us":native_us,"script_us":script_us}))
	get_tree().quit(1 if not failures.is_empty() else 0)
