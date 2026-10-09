extends Node
## Dry-bank placement, immutable shoreline jobs and authored-map evidence.
const Cover = preload("res://src/game/fx/biome_cover.gd")
const Geometry = preload("res://src/game/fx/biome_cover_mesh.gd")
var checks := 0
var failures := 0
var rows := []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL ",label)

func hash_data(value: Variant) -> String:
	var h := HashingContext.new(); h.start(HashingContext.HASH_SHA256); h.update(var_to_bytes(value)); return h.finish().hex_encode()

func fixture() -> TerrainDetails:
	var t := EITerrain.new(); t.map_name = "bank-fixture"; t.resource_prefix = "zone1"
	t.sectors_x = 1; t.sectors_y = 1; t.grid_w = 33; t.texture_size = 512; t.tile_size = 64
	t.heights.resize(33*33); t.land_xy.resize(33*33); t.land_tile.resize(16*16); t.tile_types = PackedInt32Array([3])
	t.ground.resize(32*32); t.ground.fill(3); t.water.resize(32*32); t.water.fill(-INF)
	t.water_mat.resize(32*32); t.water_mat.fill(255); t.surface.resize(32*32); t.surface.fill(-INF)
	t.liquid_ground.resize(32*32); t.liquid_ground.fill(255)
	for y in 33:
		for x in 33: t.heights[y*33+x] = -1.0 if x<8 else 0.3
	for m in 3: t.materials.append({"color":Color(0.2,0.3,0.2,0.2),"type":4,"wave":0.0,"self_illum":0.0})
	var vertices := PackedVector3Array(); var owners := PackedVector2Array(); var indices := PackedInt32Array()
	for ty in 16:
		for tx in 4:
			var m := 0 if ty<5 else (1 if ty<10 else 2); var first := vertices.size()
			for dy in 3:
				for dx in 3:
					vertices.append(Vector3(tx*2+dx,0,-(ty*2+dy))); owners.append(Vector2(0,m))
			for dy in 2:
				for dx in 2:
					var a := first+dy*3+dx; indices.append_array([a+3,a+1,a,a+1,a+3,a+4])
					var at := (ty*2+dy)*32+tx*2+dx
					t.water[at] = 0; t.water_mat[at] = m; t.liquid_ground[at] = 14 if m==1 else 6
	t.water_base = t.water.duplicate()
	var arrays := []; arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices; arrays[Mesh.ARRAY_TEX_UV2] = owners; arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new(); mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var water := MeshInstance3D.new(); water.name = "Water_0_0"; water.mesh = mesh; t.add_child(water)
	var d := TerrainDetails.new(); d.terrain = t; d._cover = true; t.details = d
	var image := Image.create(128,128,false,Image.FORMAT_RGBA8); image.fill(Color(0.5,0.42,0.25)); d._images[0] = image
	d.prepare_grass(); d._cover_field.biome = "gipat"
	# The synthetic name has no campaign zone. Rebuild explicitly with its context.
	d._cover_field.configure(t,d._grass_field,{0:image},"gipat")
	return d

func synthetic() -> void:
	var d := fixture(); var field: Variant = d._cover_field
	for sample in [[Vector2(9,4),1],[Vector2(9,14),2],[Vector2(9,26),3]]:
		var nearby: Vector3 = field.shore(sample[0])
		check(nearby.z == sample[1],"authored liquid and verified sea classification "+str(sample[1]))
	var hit := {"type":3,"colour":Color(0.5,0.4,0.2),"normal":Vector3.UP,"height":0.3}
	var sums := Vector4.ZERO
	for y in 32:
		var p := Vector2(9.0,y+0.4)
		var w: Vector4 = field.bank_weights(p,hit,field.shore(p)); sums += w
		if y<8: check(w.y==0 and w.z==0 and w.w==0,"river does not grow swamp cattails or sea debris")
		if y>21: check(w.x==0 and w.y==0,"sea does not grow inland reeds")
	check(sums.x>0 and sums.y>0 and sums.z>0 and sums.w>0,"fixture admits all four bank species")
	for type in [2,4,6,7,8,9,10,12,13,14,15]:
		hit.type = type
		check(field.bank_weights(Vector2(9,14),hit,Vector3(0.5,0,2)) == Vector4.ZERO,"excluded root material "+str(type))
	hit.type = 3; hit.height = 3
	check(field.bank_weights(Vector2(9,14),hit,Vector3(0.5,0,2)) == Vector4.ZERO,"nearby water below a cliff cannot place bank plants")
	var expected := {}; var jobs := []; var kinds := {}
	for y in 4:
		var key := Vector2i(1,y); var data: Dictionary = field.build(key,[],[]); expected[key] = data
		for r: Dictionary in data.records:
			if r.kind<7: continue
			kinds[r.kind] = int(kinds.get(r.kind,0))+1
			check(r.p.x>=8 and d.terrain.water_at(r.p.x,r.p.y)<r.height-0.06,"bank roots stay dry")
			for kind: int in ([7,8] if r.kind==7 else [r.kind]):
				var plant := r.duplicate(); plant.kind = kind
				var one: Array[Dictionary] = [plant]; var arr: Array = Geometry.new().build(one,key)
				var root := Vector3(r.p.x-key.x*8,r.height+0.008,-(r.p.y-key.y*8))
				for v: Vector3 in arr[Mesh.ARRAY_VERTEX]:
					check(Vector2(v.x-root.x,v.z-root.z).length()<TerrainDetails.SCENERY_RADIUS and v.y-root.y+SoftGroundDeform.DEPTH<Cover.BANK_HEIGHT,"bank mesh and soft-ground lift fit the scenery exclusion envelope")
		var job: RefCounted = d._chunk_job(key)
		jobs.append({"key":key,"job":job,"task":WorkerThreadPool.add_task(Callable(job,"run"))})
	check(kinds.has(7) and kinds.has(9) and kinds.has(10),"synthetic bank emits reeds and both kinds of sea debris")
	var box := {"inverse":Transform3D.IDENTITY,"box":AABB(Vector3(8,1.3,-32),Vector3(8,0.1,32))}
	check(field.bank_records(Vector2i(1,1),[box]).is_empty(),"tall reeds are excluded below an overhanging obstacle")
	var shore_before: Vector3 = field.shore(Vector2(9,14))
	d.terrain.get_node("Water_0_0").free(); d.terrain.heights.fill(99); d.terrain.water.fill(99); d.terrain.liquid_ground.fill(13)
	d.terrain.water_offsets[1] = 50
	for record: Dictionary in jobs:
		WorkerThreadPool.wait_for_task_completion(record.task)
		check(record.job.read_result().cover==expected[record.key],"shoreline worker survives source mutation and water mesh release")
	check(field.shore(Vector2(9,14))==shore_before,"published shoreline never reads live nodes or offsets")
	rows.append({"case":"synthetic","kinds":kinds,"shore_buckets":field.shores.size()})
	d.terrain.free(); d.free(); d = null; field = null
	# Actual flood API must discard the old field, including jobs in flight.
	d = fixture(); var terrain := d.terrain
	for y in 4:
		var job := d._chunk_job(Vector2i(1,y))
		d._grass_jobs.append({"key":Vector2i(1,y),"kernel":job,"task":WorkerThreadPool.add_task(Callable(job,"run"))})
	terrain.set_water_offset(1,-5.0)
	check(d._grass_jobs.is_empty() and d._cover_field==null,"water-level change joins jobs and retires the bank snapshot")
	var f := Cover.new(); f.configure(terrain,null,{},"gipat")
	check(f.shore(Vector2(9,14)).z!=2,"drained swamp is absent from the rebuilt shore field")
	terrain.set_water_offset(1,0.0); f = Cover.new(); f.configure(terrain,null,{},"gipat")
	check(f.shore(Vector2(9,14)).z==2,"restored swamp regains its bank classification")
	terrain.resource_prefix = "unverified-map"; f = Cover.new(); f.configure(terrain,null,{},"gipat")
	check(f.shore(Vector2(9,26)).z==1,"unverified material is inland water, never inferred sea")
	terrain.surface.fill(2); f = Cover.new(); f.configure(terrain,null,{},"gipat")
	check(f.shores.is_empty(),"covered water does not seed a shore through a bridge or floor")
	terrain.free(); d.free()

func authored() -> void:
	for name in ["zone1","zone11","zone15","zone7","zone8"]:
		var started := Time.get_ticks_usec(); var t := EITerrain.load_map(name); var d := t.details
		d.set_process(false); d.prepare_grass(); var field: Variant = d._cover_field
		var prep_us := Time.get_ticks_usec()-started
		var original: Array[Dictionary] = []
		for y in 8:
			for x in 8:
				var key := Vector2i((x+0.5)*t.size_ei().x/64.0,(y+0.5)*t.size_ei().y/64.0)
				for r: Dictionary in field.records(key,[],[]):
					if r.kind<7: original.append(r)
		check((field.native==null)==OS.get_cmdline_user_args().has("--ei-script-grass"),"requested native/script sampler is active "+name)
		var row := {"case":"authored","map":name,"native_sampler":field.native!=null,"dry_count":original.size(),"dry_hash":hash_data(original),"load_and_prepare_us":prep_us}
		var counts := {}; var focuses := {}; var times := []; var points := 0
		var keys: Array = field.shores.keys(); keys.sort()
		for key: Vector2i in keys:
			points += (field.shores[key] as PackedVector4Array).size()
			if key.x<0 or key.y<0 or key.x*8>=t.size_ei().x or key.y*8>=t.size_ei().y: continue
			if name in ["zone11","zone15"] and posmod(key.x+key.y*3,11)!=0: continue
			started = Time.get_ticks_usec()
			var records: Array = field.bank_records(key,[]); times.append(Time.get_ticks_usec()-started)
			for r: Dictionary in records:
				counts[r.kind] = int(counts.get(r.kind,0))+1
				if not focuses.has(r.kind): focuses[r.kind] = str(r.p)
				check(t.water_at(r.p.x,r.p.y)<=r.height-0.06,"authored root remains dry "+name)
				var near: Vector3 = field.shore(r.p)
				check(near.z==3 if r.kind in [9,10] else int(near.z) in [1,2],"authored inland/sea rule "+name)
				check(field.footprint(r.p,field.dry_surface(r.p),r.kind,Cover.RADII[r.kind]*r.scale),"authored bank footprint "+name)
		times.sort()
		row.merge({"bank_counts":counts,"focuses":focuses,"index_bytes":points*16,"sampled_chunks":times.size(),"bank_job_median_us":times[times.size()/2] if not times.is_empty() else 0,"bank_job_max_us":times[-1] if not times.is_empty() else 0})
		if name=="zone1":
			check(counts.has(7) and counts.has(8),"authored starting map supplies reeds and cattails")
			check(not counts.has(9) and not counts.has(10),"zone1's ground-tagged coast is not silently relabelled as sand")
		if name in ["zone7","zone8"]:
			check(int(counts.get(10,0))>0,"authored sandy coast admits shells "+name)
			if name=="zone7": check(int(counts.get(9,0))>0,"island coast also admits wrack")
			var expected := 0 if name=="zone7" else 4
			check(not field.sea.tiles.is_empty() and field.sea.tiles.values().all(func(tile: Dictionary): return tile.owner==expected),"sea snapshot excludes inland/swamp owners "+name)
			check(Array(t._surf).all(func(strength: float): return strength==0.0),"cover habitat does not opt this map into unvalidated surf "+name)
			row["sea_tiles"] = field.sea.tiles.size()
			if name=="zone8":
				var river := false
				for y in range(1,int(t.size_ei().y),2):
					for x in range(1,int(t.size_ei().x),2):
						var at := y*int(t.size_ei().x)+x
						if t.water_mat[at]!=5 or t.water[at]<=t.height_at(x,y)+0.1: continue
						if field.shore(Vector2(x,y)).z==1: river=true; break
					if river: break
				check(river,"connected inland material retains river classification")
		rows.append(row); print("BANK_AUTHORED ",JSON.stringify(row)); t.free()

func _ready() -> void:
	for option in ["gfx_hd_textures","gfx_terrain","gfx_soft_ground","gfx_ground_contact","gfx_grass","gfx_vegetation_interaction","gfx_wind","gfx_water","gfx_water_interaction","gfx_water_caustics","gfx_volumetric","gfx_ssao","gfx_bloom","confine_mouse","vsync"]: GameData.options[option] = 0
	GameData.options["gfx_biome_cover"] = 1; Gfx.ensure_globals()
	synthetic(); authored()
	TexUpscale.shutdown(); await get_tree().process_frame
	FileAccess.open("user://biome-cover-shores.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"rows":rows},"\t"))
	print("BIOME_SHORES checks=",checks," failures=",failures)
	get_tree().quit(1 if failures else 0)
