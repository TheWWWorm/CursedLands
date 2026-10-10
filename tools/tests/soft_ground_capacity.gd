extends Node
## Controlled completion-order regression using authored source meshes and
## the actual SoftGroundDeform dispatcher, native jobs and ArrayMesh install.
## Only acceptance of A's real worker result is held while B finishes first.
## Direct _add_mark calls isolate capacity; no physical footprint claim.
const A := Vector2i(4,2)
const B := Vector2i(5,2)
var checks := 0
var failures := 0
var states := []
var soft: SoftGroundDeform
var palette: GroundDenseColors


func check(ok: bool,label: String) -> bool:
	checks += 1
	if not ok: failures += 1; printerr("FAIL ",label)
	return ok


func mark(key: Vector2i,id: int) -> void:
	var p := Vector2(key*32)+Vector2(id%16*2+1,id/16*2+1)
	soft._add_mark({"p":p,"extent":Vector2(0.04,0.04),"angle":0.0,"time":soft._age})


func state(label: String) -> void:
	var logical := {}; var installed := {}
	for key: Vector2i in soft.sectors:
		logical[str(key)] = soft.sectors[key].tiles.size()
	for key: Vector2i in soft.field._dense_sources:
		installed[str(key)] = soft.field._dense_sources[key].size()
	states.append({"label":label,"logical_tiles":logical,"installed_tiles":installed,
		"palette_count":palette._slots.size() if palette else 0,
		"visible_meshes":soft.sectors.keys().map(func(k: Vector2i) -> String: return str(k)),
		"logical_count":soft.tile_count(),"queued_jobs":soft._mesh_jobs.size()})
	save()


func save() -> void:
	var result := {"checks":checks,"failures":failures,"states":states,
		"scope":"Narrow actual native dispatcher cap regression. Authored zone1 sector4_2 and5_2 source geometry is unchanged. Marks are controlled capacity seeds, not material/route acceptance. Initial A127+B1 installed; A126 expire while its real removal job result is held; B requests and accepts first; then late A result is rejoined. No GPU or performance claim."}
	FileAccess.open("user://dense-capacity-report.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t")+"\n")


func _ready() -> void:
	for option: Array in GameData.OPTIONS:
		if String(option[0]).begins_with("gfx_"): GameData.options[option[0]] = 0
	Gfx.ensure_globals(); Gfx.apply_surface_options()
	if not check(ClassDB.class_exists("SoftGroundMeshJob"),"real native worker available"):
		save(); get_tree().quit(1); return
	var terrain := EITerrain.load_map("zone1")
	if not check(terrain != null,"authored source terrain loaded"):
		save(); get_tree().quit(1); return
	add_child(terrain); terrain.set_process(false)
	soft = SoftGroundDeform.new(); soft.terrain = terrain; terrain.add_child(soft); soft.set_process(false)
	check(soft._native_mesh,"native dispatcher selected")
	for id in 127: mark(A,id)
	mark(B,0)
	if not check(soft.sectors.has(A) and soft.sectors.has(B),"both authored sectors available"):
		terrain.free(); save(); get_tree().quit(1); return
	var a_source: Mesh = soft.sectors[A].source
	var b_source: Mesh = soft.sectors[B].source
	var a_node := (soft.sectors[A].node as WeakRef).get_ref() as MeshInstance3D
	var b_node := (soft.sectors[B].node as WeakRef).get_ref() as MeshInstance3D
	check(soft.tile_count() == 128,"exact initial logical128 seed")
	soft._process(0)
	check(soft._mesh_jobs.size() == 2,"both initial meshes dispatched to real workers")
	soft._finish_mesh_jobs(true)
	palette = soft.field.contact_colors()
	check(soft.field._dense_sources[A].size() == 127 and soft.field._dense_sources[B].size() == 1,"native A127+B1 installed")
	check(palette._slots.size() == 128,"palette exactly full after initial native acceptance")
	check(a_node.mesh != a_source and b_node.mesh != b_source,"actual surface replacements installed")
	state("initial-native128")
	# Refresh one genuine mark per sector so only A's old126 tiles expire.
	soft._age = SoftGroundDeform.LIFE+0.5
	mark(A,126); mark(B,0)
	soft._process(1.1)
	check(soft.sectors[A].tiles.size() == 1 and soft.sectors[B].tiles.size() == 1,"timed expiry leaves A1+B1 logical tiles")
	check(soft.field._dense_sources[A].size() == 127 and palette._slots.size() == 128,"expired A remains installed until replacement acceptance")
	if not check(soft._mesh_jobs.size() == 1 and soft._mesh_jobs[0].key == A,"real A removal job dispatched"):
		soft.clear(); terrain.free(); save(); get_tree().quit(1); return
	# Deterministically defer this real result, equivalent to a slower A job.
	# Kernel/output arrays are not replaced or forged. Production _process,
	# _finish_mesh_jobs and _apply_mesh handle every accepted job normally.
	var held_a: Dictionary = soft._mesh_jobs.pop_back()
	state("A-removal-awaiting-acceptance")
	mark(B,1)
	check(not soft.sectors.has(A),"union reservation restores A before admitting B tile129")
	check(a_node.mesh == a_source,"capacity retirement restores original A mesh immediately")
	state("B-requested-before-A-result")
	soft._process(0)
	check(soft._mesh_jobs.size() == 1 and soft._mesh_jobs[0].key == B,"real B replacement dispatched first")
	soft._finish_mesh_jobs(true)
	check(soft.field._dense_sources[B].size() == 2,"native B replacement accepted with both tiles")
	var tile := B*16+Vector2i(1,0)
	var layer := int(palette._tile_image.get_pixelv(tile).r)-1
	check(layer >= 0,"new visible B tile has a valid native COLOR layer")
	if layer >= 0:
		check(palette._images[layer].get_data() == GroundDenseColors.packed_image(soft.sectors[B].tiles[1][Mesh.ARRAY_COLOR]).get_data(),"new B COLOR is exact accepted native output")
	check(palette._slots.size() == 2,"only B2 remains installed within the cap")
	state("B-native-result-accepted-first")
	soft._mesh_jobs.append(held_a)
	soft._finish_mesh_jobs(true)
	check(not soft.sectors.has(A) and a_node.mesh == a_source,"late A worker result cannot revive retired geometry")
	check(palette._slots.size() == 2 and soft.field._dense_sources.size() == 1,"late A result cannot revive COLOR layers")
	check(soft._mesh_jobs.is_empty(),"all real worker tasks joined")
	state("late-A-result-rejoined")
	soft.clear()
	check(a_node.mesh == a_source and b_node.mesh == b_source,"clear restores both authored meshes")
	check(palette._slots.is_empty() and soft.field._dense_sources.is_empty(),"clear releases all accepted COLOR snapshots")
	state("cleared")
	terrain.free(); palette = null
	save()
	print("DENSE_CAPACITY checks=",checks," failures=",failures)
	TexUpscale.shutdown(); UnitWounds.shutdown(); get_tree().quit(int(failures>0))
