extends Node
## Streaming material-table construction must keep authored primitive identities
## while copying large refined terrain spans without a per-triangle script loop.
const Collector = preload("res://src/game/fx/path_trace_terrain.gd")
const Transitions = preload("res://src/game/fx/terrain_transition.gd")
class Fixture extends RefCounted:
	var vertices := PackedFloat32Array()
	var geometries: Array[Dictionary] = []
	func _layer(_texture: Texture2D) -> int: return 2

var checks := 0
var failures := 0

func check(ok: bool,label: String) -> void:
	checks += 1
	print("PASS " if ok else "FAIL ",label)
	if not ok: failures += 1

func reference_primitives(scene: Fixture) -> PackedInt32Array:
	var result := PackedInt32Array();result.resize(scene.vertices.size()/48)
	for geometry: Dictionary in scene.geometries:
		if not geometry.has("land_tiles"): continue
		var ids: PackedInt32Array = geometry.land_tiles
		for i in ids.size(): result[geometry.offset/3+i]=ids[i]
	return result

func primitive_bytes(collector: RefCounted,scene: Fixture) -> PackedByteArray:
	var start: int=collector.data.decode_u32(12)
	return collector.data.slice(start,start+scene.vertices.size()/48*4)

func collect(scene: Fixture,terrain: EITerrain) -> RefCounted:
	var collector := Collector.new();collector.collect(scene,terrain)
	return collector

func fixture() -> Fixture:
	var scene := Fixture.new()
	scene.geometries=[{"offset":0,"count":9},
		{"offset":9,"count":12,"land_tiles":PackedInt32Array([1,256,65537,2147483647])},
		{"offset":21,"count":15},
		{"offset":36,"count":9,"land_tiles":PackedInt32Array([73,73,8])},
		{"offset":45,"count":6}]
	scene.vertices.resize(17*48)
	return scene

func _ready() -> void: run.call_deferred()

func run() -> void:
	GameData.options.merge({"gfx_terrain":2,"gfx_materials":1},true)
	var terrain := EITerrain.new();terrain.sectors_x=1;terrain.sectors_y=1
	terrain.land_tile.resize(256);terrain.land_tile.fill(2);terrain.land_tile[0]=49153
	terrain.tile_types=PackedInt32Array([0,9,3])
	terrain._detail_atlases=Texture2DArray.new()
	var shader := Shader.new()
	shader.code="shader_type spatial; uniform sampler2D detail_nm; uniform sampler2D macro_tex; uniform bool blend_edges=true;"
	terrain._land_mat=ShaderMaterial.new();terrain._land_mat.shader=shader
	var cliff := TerrainCliff.new();cliff.admitted=1;cliff.mixed=1;cliff.grid_size=Vector2i(3,3)
	cliff.eligible.resize(256);cliff.eligible[0]=1
	cliff.blend_rows.resize(256);cliff.blend_rows[0]=Color(1,2,3,4)
	cliff.guards=PackedByteArray([1,0,1,0,1,0,1,0,1]);terrain._cliffs=cliff
	var transition := Transitions.new();transition.admitted=1;transition.junctions=1
	transition.rows=PackedColorArray([Color(2,3,4,5)]);transition.junction_rows=PackedColorArray([Color(6,7,8,9)])
	terrain._transitions=transition
	var scene := fixture();var collector := collect(scene,terrain)
	var expected := PackedInt32Array([0,0,0,1,256,65537,2147483647,0,0,0,0,0,73,73,8,0,0])
	check(primitive_bytes(collector,scene)==expected.to_byte_array(),"full-width refined primitive IDs retain leading, internal and trailing nonterrain gaps")
	check(collector.terrain_triangles==7 and collector.atlas==terrain._detail_atlases,"snapshot retains exact terrain triangle count and atlas owner")
	# 80-byte header: the derived-map strength float4 sits at offset 64.
	const H := 80
	var tuning:=TerrainSurfaceMaps.tuning
	check(Collector.HEADER==H and collector.data.decode_float(64)==tuning.x and collector.data.decode_float(68)==tuning.y
		and collector.data.decode_float(72)==tuning.z and collector.data.decode_float(76)==tuning.w,"header carries the derived-map strength")
	check(collector.data.decode_u32(0)==16 and collector.data.decode_u32(4)==16 and collector.data.decode_u32(8)==H
		and collector.data.decode_u32(12)==H+1024,"material-table header offsets remain unchanged")
	check(collector.data.decode_u32(H)==(49153|(9<<16)|(1<<24)|(1<<25))
		and collector.data.decode_u32(H+4)==(2|(3<<16)),"tile rotation, traits, cliff admission and blend flags remain unchanged")
	var guards: int=collector.data.decode_u32(40);var pairs: int=collector.data.decode_u32(56);var junctions: int=collector.data.decode_u32(60)
	check(guards==H+1092 and collector.data.slice(guards,guards+9)==cliff.guards
		and collector.data.slice(guards+9,guards+12)==PackedByteArray([0,0,0]),"cliff guards follow the complete primitive table with zero alignment padding")
	check(collector.data.slice(guards+12,pairs)==cliff.blend_rows.to_byte_array()
		and collector.data.slice(pairs,junctions)==transition.rows.to_byte_array()
		and collector.data.slice(junctions)==transition.junction_rows.to_byte_array(),"cliff blends, transition pairs and junction payloads are byte exact")
	var original: PackedByteArray = collector.data
	scene.geometries.reverse();collector=collect(scene,terrain)
	check(collector.data==original,"reordered geometry descriptors retain identical material-table bytes")
	scene.geometries=[{"offset":0,"count":51}];collector=collect(scene,terrain)
	check(primitive_bytes(collector,scene)==reference_primitives(scene).to_byte_array() and collector.terrain_triangles==0,"all nonterrain geometry retains a zero primitive table")
	scene.vertices.resize(0);scene.geometries.clear();collector=collect(scene,terrain)
	check(primitive_bytes(collector,scene).is_empty() and collector.data.decode_u32(40)==H+1024,"empty geometry retains metadata without stray primitive IDs")

	# Same-process relative timing avoids a hardware-specific millisecond limit.
	# The reference is the formerly unbounded per-triangle material copy. A
	# quarter-million refined triangles expose the cost even on a fast CPU.
	scene=Fixture.new();var offset:=13
	for block in 64:
		var ids:=PackedInt32Array();ids.resize(4096)
		for i in ids.size(): ids[i]=1+((block*4096+i)*97)%262144
		scene.geometries.append({"offset":offset*3,"count":ids.size()*3,"land_tiles":ids})
		offset+=ids.size()+11
	scene.vertices.resize(offset*48)
	var reference:=reference_primitives(scene).to_byte_array()
	var timings:=[];var reference_timings:=[];var identical:=true
	collect(scene,terrain) # Warm resource/property lookups before measuring.
	for repeat in 5:
		var start:=Time.get_ticks_usec();reference_primitives(scene);reference_timings.append(Time.get_ticks_usec()-start)
		collector=collect(scene,terrain);timings.append(collector.build_us)
		identical=identical and primitive_bytes(collector,scene)==reference
	timings.sort();reference_timings.sort()
	check(identical and collector.terrain_triangles==262144,"large refined scene preserves all primitive IDs and zeros across 64 spans")
	check(float(timings[2])<float(reference_timings[2])*0.5,
		"complete material collection avoids the per-triangle copy cost: %s us versus %s us"%[timings[2],reference_timings[2]])
	terrain.free()
	print("PT_TERRAIN_COLLECT ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
