extends Node
## CPU/headless authored grass roots and continuous-focus stream coverage.
## Loads the real map/MOB/atlas and scenery exclusions without moving geometry.
var checks := 0
var failures := 0
var report := {"scope":"CPU authored roots and stream selection; not visual or performance acceptance.","envelopes":[],"chunks":[],"witnesses":[]}

func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ",label)
	return ok

func digest(value: Variant) -> String:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(var_to_bytes(value))
	return hash.finish().hex_encode()

func point(p: Vector2) -> Array:
	return [p.x,p.y]

func key_pair(k: Vector2i) -> Array:
	return [k.x,k.y]

func corners(rect: Rect2) -> Array[Vector2]:
	return [rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)]

func distance_between(a: Rect2,b: Rect2) -> float:
	# Independent geometric oracle: closest points on both rectangle outlines.
	# For axis-aligned rectangles the minimum is attained by a corner of one
	# rectangle projected onto the other (including intersecting rectangles).
	var distance := INF
	for p: Vector2 in corners(a):
		distance = minf(distance,p.distance_squared_to(p.clamp(b.position,b.end)))
	for p: Vector2 in corners(b):
		distance = minf(distance,p.distance_squared_to(p.clamp(a.position,a.end)))
	return distance

func envelope(d: TerrainDetails,focus: Vector2i) -> void:
	d._focus = focus
	d._stream(focus)
	var wanted := d._wanted_chunks.duplicate()
	var dimensions := Vector2i(d.terrain.size_ei()/TerrainDetails.CHUNK)
	var focus_box := Rect2(Vector2(focus)*TerrainDetails.CHUNK,Vector2.ONE*TerrainDetails.CHUNK)
	var required := []
	var missing := []
	for y in dimensions.y:
		for x in dimensions.x:
			var k := Vector2i(x,y)
			var roots := Rect2(Vector2(k)*TerrainDetails.CHUNK,Vector2.ONE*TerrainDetails.CHUNK)
			if distance_between(focus_box,roots) < TerrainDetails.RANGE*TerrainDetails.RANGE:
				required.append(k)
				if not wanted.has(k): missing.append(key_pair(k))
	check(missing.is_empty(),"complete continuous-focus cell envelope "+str(focus))
	check(wanted.size()<=TerrainDetails.MAX_CHUNKS,"bounded wanted count "+str(focus))
	var queue_valid := true
	for k: Vector2i in wanted:
		queue_valid = queue_valid and k.x>=0 and k.y>=0 and k.x<dimensions.x and k.y<dimensions.y and d._queue.has(k)
	check(queue_valid,"valid map ownership and queued roots "+str(focus))
	var sample_misses := 0
	var live_boxes := 0
	for yy in [0.0,0.125,4.0,7.875,7.999]:
		for xx in [0.0,0.125,4.0,7.875,7.999]:
			var p := focus_box.position+Vector2(xx,yy)
			for k: Vector2i in required:
				var roots := Rect2(Vector2(k)*TerrainDetails.CHUNK,Vector2.ONE*TerrainDetails.CHUNK)
				if p.distance_squared_to(p.clamp(roots.position,roots.end)) < TerrainDetails.RANGE*TerrainDetails.RANGE:
					live_boxes += 1
					if not wanted.has(k): sample_misses += 1
	check(sample_misses==0,"live root boxes through focus motion "+str(focus))
	report.envelopes.append({"focus":key_pair(focus),"wanted":wanted.size(),"required":required.size(),"missing":missing,"samples":25,"live_boxes":live_boxes,"sample_misses":sample_misses})

func authored_roots(d: TerrainDetails,zone: Dictionary) -> void:
	var dimensions := Vector2i(d.terrain.size_ei()/TerrainDetails.CHUNK)
	var keys: Array[Vector2i] = [dimensions/2]
	for exit: Dictionary in zone.exits.values():
		if exit.get("deploy") is Rect2:
			var k := Vector2i((exit.deploy as Rect2).get_center()/TerrainDetails.CHUNK)
			if not keys.has(k): keys.append(k)
	var rng := RandomNumberGenerator.new()
	rng.seed = String(zone.id).hash()
	for i in 18:
		var k := Vector2i(rng.randi_range(0,dimensions.x-1),rng.randi_range(0,dimensions.y-1))
		if not keys.has(k): keys.append(k)
	var root_count := 0
	var selected := 0
	var missing := 0
	var before := digest([d.terrain.heights,d.terrain.land_xy,d.terrain.land_tile,d.terrain.ground,d.terrain.water,d.terrain.surface])
	for k: Vector2i in keys:
		var native := d.instances(k)
		var script := d.instances_script(k)
		for field in ["transforms","colours","custom"]:
			check(native[field]==script[field],"authored native/scalar exact "+str(k)+" "+field)
		root_count += native.transforms.size()
		var geometry_hash := digest([native.transforms,native.colours,native.custom])
		report.chunks.append({"key":key_pair(k),"roots":native.transforms.size(),"geometry_sha256":geometry_hash,"native_buffer_sha256":digest(native.buffer)})
		if selected >= 8: continue
		var best := {}
		var best_fade := 0.0
		for offset: Vector2i in [Vector2i(1,5),Vector2i(-1,5),Vector2i(1,-5),Vector2i(-1,-5),Vector2i(5,1),Vector2i(5,-1),Vector2i(-5,1),Vector2i(-5,-1)]:
			var focus := k+offset
			if focus.x<0 or focus.y<0 or focus.x>=dimensions.x or focus.y>=dimensions.y: continue
			var box := Rect2(Vector2(focus)*TerrainDetails.CHUNK,Vector2.ONE*TerrainDetails.CHUNK)
			for i in native.transforms.size():
				var transform: Transform3D = native.transforms[i]
				var root := Vector2(transform.origin.x,-transform.origin.z)
				var p := root.clamp(box.position,box.end-Vector2.ONE*0.001)
				var distance := root.distance_to(p)
				var fade := 1.0-smoothstep(28.0,36.0,distance)
				if fade>best_fade:
					best_fade=fade
					best={"key":key_pair(k),"focus_key":key_pair(focus),"focus":point(p),"root":[transform.origin.x,transform.origin.y,transform.origin.z],"index":i,"distance":distance,"height_fraction":fade,"geometry_sha256":geometry_hash}
		if best_fade<0.10: continue
		var f := Vector2i(best.focus_key[0],best.focus_key[1])
		d._focus=f
		d._stream(f)
		best.wanted=d._wanted_chunks.has(k)
		best.old_integer_disk_excludes=Vector2(k-f).length_squared()>25.0
		check(best.old_integer_disk_excludes,"authored witness lies outside old integer disk")
		if not best.wanted: missing+=1
		report.witnesses.append(best)
		selected+=1
	check(root_count>500,"substantial authored native grass roots")
	check(selected>=3,"non-vacuous authored live-fade omission witnesses")
	check(missing==0,"every authored live-fade root witness is streamed")
	check(before==digest([d.terrain.heights,d.terrain.land_xy,d.terrain.land_tile,d.terrain.ground,d.terrain.water,d.terrain.surface]),"stream selection leaves native terrain inputs unchanged")
	report.terrain_input_sha256=before
	report.root_count=root_count
	report.witness_missing=missing

func finish() -> void:
	report.checks=checks
	report.failures=failures
	FileAccess.open("user://grass-stream-envelope.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("GRASS_STREAM_ENVELOPE checks=",checks," failures=",failures," roots=",report.get("root_count",0))
	get_tree().quit(1 if failures else 0)

func _ready() -> void:
	GameData.options.merge(GfxDetect.original_look_values(true,{},-1),true)
	GameData.options.merge({"gfx_grass":1,"gfx_biome_cover":0,"gfx_soft_ground":0,"q_aa":0},true)
	var zone := CampaignMap.load_from(GameData.texts).zone("gz7g")
	if not check(not zone.is_empty(),"authored campaign zone exists"): finish();return
	var map := EIMapScene.load_map(zone.mpr,zone.get("mob",""),false)
	if not check(map!=null,"authored terrain and scenery load"): finish();return
	map.process_mode=Node.PROCESS_MODE_DISABLED
	add_child(map)
	var d := map.terrain.details
	if d==null:
		d=TerrainDetails.new()
		d.terrain=map.terrain
		map.terrain.add_child(d)
		map.terrain.details=d
	d._grass=true
	d._cover=false
	d.prepare_grass()
	check(d._grass_field!=null,"native immutable grass field")
	check(not d._scenery.is_empty(),"authored placed scenery exclusions active")
	report.map={"zone":zone.id,"mpr":zone.mpr,"mob":zone.get("mob",""),"objects":map.object_nodes.size(),"scenery_buckets":d._scenery.size(),"size":point(map.terrain.size_ei())}
	report.constants={"chunk":TerrainDetails.CHUNK,"range":TerrainDetails.RANGE,"max_chunks":TerrainDetails.MAX_CHUNKS,"jobs":TerrainDetails.MAX_GRASS_JOBS,"build_us":TerrainDetails.BUILD_US}
	var dimensions := Vector2i(map.terrain.size_ei()/TerrainDetails.CHUNK)
	var centre := dimensions/2
	for focus: Vector2i in [centre,centre+Vector2i(1,0),centre+Vector2i(0,1),centre+Vector2i.ONE,Vector2i.ZERO,Vector2i(dimensions.x-1,0),Vector2i(0,dimensions.y-1),dimensions-Vector2i.ONE]:
		envelope(d,focus)
	authored_roots(d,zone)
	map.free()
	finish()
