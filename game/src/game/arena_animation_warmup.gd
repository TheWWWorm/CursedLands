class_name ArenaAnimationWarmup
extends Node
const PickBounds = preload("res://src/ui/mesh_screen_rect.gd")
## Decode the finite recruit/creep animation catalog while the opening scene
## is visible. Workers own archive bytes and new resources, never scene nodes
## or the global caches. Publish completed libraries only on the main thread.
var jobs: Array = []
var task := -1
var source: EIResArchive
var flags: Array
var pending := {}
var _picking := {} # mesh id -> weak source; never retains a retired army
static var _current: WeakRef
static var _model_frame := -1

## Field figures and shop portraits share one scene-construction budget.
## Independent per-widget budgets otherwise stack during round refreshes.
static func claim_model_frame() -> bool:
	if _model_frame == Engine.get_process_frames(): return false
	_model_frame = Engine.get_process_frames()
	return true


static func queue_picking(geometry: Array[GeometryInstance3D]) -> void:
	if DisplayServer.get_name() == "headless": return
	var warmer: ArenaAnimationWarmup = _current.get_ref() if _current else null
	if warmer == null: return
	for node: GeometryInstance3D in geometry:
		if node is MeshInstance3D and node.mesh and not PickBounds._mesh_meta(node.mesh).loaded:
			warmer._picking[node.mesh.get_instance_id()] = weakref(node.mesh)


static func picking_ready() -> bool:
	var warmer: ArenaAnimationWarmup = _current.get_ref() if _current else null
	return warmer == null or warmer._picking.is_empty()


func _prepare_picking() -> void:
	var started := Time.get_ticks_usec()
	for id: int in _picking.keys():
		var mesh := (_picking[id] as WeakRef).get_ref() as Mesh
		_picking.erase(id)
		if mesh == null: continue
		# GPU mesh readback and morph-array extraction must happen while
		# staging, not all at once when several fighters reach the pointer.
		PickBounds._mesh_data(mesh)
		if Time.get_ticks_usec() - started >= 1000: break

class LibraryJob extends RefCounted:
	var template := ""
	var data := PackedByteArray()
	var paths := {}
	var root := ""
	var scales: Array = []
	var options: Array = []
	var result := {}
	var mutex := Mutex.new()
	var done := false
	var published := false
	func run() -> void:
		if not EIResArchive.is_archive(data):
			mutex.lock();done=true;mutex.unlock();return
		var base := EIAnim._build_library(template,paths,root,1.0,true,data,options,false)
		result[base_key()] = base
		for scale: float in scales:
			var library := base
			if scale != 1.0:
				library = AnimationLibrary.new()
				for name in base.get_animation_list():
					library.add_animation(name,EIAnim._scaled(base.get_animation(name),scale))
			result["%s@%.3f:true:%s:%s:%s" % [template,scale,options[0],options[1],options[2]]] = library
		mutex.lock();done=true;mutex.unlock()
	func ready() -> bool:
		mutex.lock();var complete:=done;mutex.unlock();return complete
	func base_key() -> String:
		return "%s@base:true:%s:%s:%s" % [template,options[0],options[1],options[2]]

func _ready() -> void:
	process_priority = -100
	_current = weakref(self)
	if DisplayServer.get_name() != "headless": prepare()


static func ready_for(prototype: String) -> bool:
	var warmer: ArenaAnimationWarmup = _current.get_ref() if _current else null
	if warmer == null or warmer.task < 0 or warmer.source != GameData.figures: return true
	var proto := GameData.db.find("monster_prototypes", prototype)
	var race := GameData.db.find("race_models", proto.get("base_race", ""))
	var job: LibraryJob = warmer.pending.get(String(race.get("mask", "")).to_lower())
	# Staged models wait without blocking the main thread. Otherwise the
	# first click can synchronously decode the very library being prefetched.
	return job == null or job.published

func prepare() -> void:
	if task >= 0 or not Portability.threads(): return
	source = GameData.figures
	flags = [EIAnim.parent_first,EIAnim.absolute,EIAnim.invert_keys]
	var templates := {}; var ids := {}
	# Humans have the largest libraries and can appear in the opening shop.
	for index in range(24,ArenaRules.FAMILIES.size()):
		for id in ArenaRules.FAMILIES[index].forms: ids[id] = true
	for family in ArenaRules.FAMILIES:
		for id in family.forms: ids[id] = true
	for wave in ArenaRules.WAVES:
		for id in wave.slice(1): ids[id] = true
	for id: String in ids:
		var proto := GameData.db.find("monster_prototypes",id)
		var race := GameData.db.find("race_models",proto.get("base_race",""))
		var template := String(race.get("mask","")).to_lower()
		if template.is_empty(): continue
		if not templates.has(template):
			var model := EIFigure.get_model(template)
			if model.is_empty(): continue
			var job := LibraryJob.new(); job.template=template; job.options=flags.duplicate()
			var parents := {}
			for link in model.links: parents[link[0]]=link[1]
			for part: String in parents:
				var chain:=PackedStringArray([part.replace(".","_")]);var parent:String=parents[part]
				while parents.has(parent):
					chain.insert(0,parent.replace(".","_"));parent=parents[parent]
				job.paths[part]=NodePath("/".join(chain))
				if String(parents[part]).is_empty() and not "." in part: job.root=part
			job.data=GameData.read_figure(template+".anm")
			templates[template]=job
		var job: LibraryJob=templates[template]
		var scale:=EIUnitModel.height_scale(template,GameUnit.proto_complexion(proto).z)
		if not job.scales.has(scale): job.scales.append(scale)
	for job: LibraryJob in templates.values():
		if job.scales.any(func(scale):return not EIAnim._libraries.has("%s@%.3f:true:%s:%s:%s" % [job.template,scale,flags[0],flags[1],flags[2]])):
			jobs.append(job)
			pending[job.template] = job
	if jobs.is_empty(): return
	task=WorkerThreadPool.add_group_task(func(index):jobs[index].run(),jobs.size(),2,false,"arena animation libraries")

func _process(_dt: float) -> void:
	_prepare_picking()
	if task < 0: return
	if source == GameData.figures and flags == [EIAnim.parent_first,EIAnim.absolute,EIAnim.invert_keys]:
		for job: LibraryJob in jobs:
			if job.published or not job.ready(): continue
			for key in job.result:
				if not EIAnim._libraries.has(key): EIAnim._libraries[key]=job.result[key]
			job.published=true
	if not WorkerThreadPool.is_group_task_completed(task):return
	WorkerThreadPool.wait_for_group_task_completion(task);task=-1
	jobs.clear();pending.clear();source=null

func _exit_tree() -> void:
	if task >= 0:
		WorkerThreadPool.wait_for_group_task_completion(task);task=-1
	jobs.clear();pending.clear();source=null
	_picking.clear()
