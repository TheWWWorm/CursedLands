extends Node
## Authored map/type records and the real contact dispatcher. Static sand art
## and original footprint decals are separate from this remake deformation.
var checks:=0
var failures:=0
func check(ok:bool,label:String) -> void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func _ready() -> void:
	for option:Array in GameData.OPTIONS:
		if String(option[0]).begins_with("gfx_"):GameData.options[option[0]]=0
	GameData.options.gfx_soft_ground=1;Gfx.ensure_globals();Gfx.apply_surface_options()
	var found:Dictionary={}
	for map_name in ["zone11","zone15"]:
		var t:=EITerrain.load_map(map_name);check(t!=null,"authored "+map_name)
		if not t:continue
		add_child(t);t.set_process(false);t.details.set_process(false)
		var soft:=t.details.soft_ground;soft.set_process(false)
		var profiles:=t._ground_tile_image()
		var ray:=preload("res://src/game/fx/raytrace_ground.gd").new();ray.configure(t)
		var counts:Dictionary={};var samples:Dictionary={}
		for y in profiles.get_height():
			for x in profiles.get_width():
				var value:=profiles.get_pixel(x,y);var type:=int(value.g)
				if not type in [3,9,12]:continue
				var p:=Vector2(x*2+1,y*2+1)
				if t.ground_type(p.x,p.y)!=type or t.ground_at(p.x,p.y)>t.height_at(p.x,p.y)+.04 or t.water_at(p.x,p.y)>t.height_at(p.x,p.y)-.025:continue
				counts[type]=counts.get(type,0)+1
				if not samples.has(type):samples[type]=p
				var expected:Vector2={3:Vector2.ZERO,9:Vector2(.20,.30),12:Vector2(.075,.12)}[type]
				if not Vector2(value.b,value.a).is_equal_approx(expected) or not ray.profile_at(Vector2i(x,y)).is_equal_approx(expected):
					check(false,"raster/ray profile mismatch %s %s"%[map_name,p])
		check(not counts.is_empty(),"map exposes dry authored surface witnesses")
		for type:int in samples:
			found[type]=true;soft.clear();var p:Vector2=samples[type]
			check(soft.step_allowed(p)==(type!=3),"contact admission %s type %d"%[map_name,type])
			soft.add_step(p,Vector2(.12,.18),.4)
			soft.add_travel(17,p,Vector2(.12,.18));soft.add_travel(17,p+Vector2(.2,0),Vector2(.12,.18))
			if type==3:
				check(soft.sectors.is_empty() and soft._queue.is_empty() and soft._walkers.is_empty(),"sand creates no tracks, geometry or travel history")
			else:
				check(not soft.sectors.is_empty() and not soft._queue.is_empty(),"snow retains footprint and travel marks")
				for i in 16:soft._process(0);soft._finish_mesh_jobs(true)
				check(soft.tile_count()>0 and soft._queue.is_empty(),"snow installs dense geometry through production dispatcher")
		print("SNOW_SURFACES ",map_name," ",counts)
		t.free()
	check(found.has(3) and found.has(9),"authored sand and loose snow exercised")
	# Packed snow is not present on these two maps. Exercise the profile table
	# explicitly without claiming an authored packed-snow witness.
	var table:=EITerrain.new();table.sectors_x=1;table.sectors_y=1
	table.land_tile.resize(256);table.land_tile.fill(0);table.tile_types=PackedInt32Array([12])
	var packed:=table._ground_tile_image().get_pixel(0,0)
	check(Vector2(packed.b,packed.a).is_equal_approx(Vector2(.075,.12)) and 12 in SoftGroundDeform.TYPES,"packed-snow profile and contact eligibility retained")
	table.free()
	print("SNOW_ONLY_TRACKS ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
