extends "res://tools/tests/path_trace_walk_performance.gd"
var probe_rt: Node
var diagnostic_tick:=0
func _init() -> void:walk_legs=3
func _process(dt: float) -> void:
	super._process(dt)
	if not is_instance_valid(probe_rt):probe_rt=get_tree().root.find_child("SceneRaytrace",true,false)
	if not is_instance_valid(probe_rt):return
	diagnostic_tick+=1
	if diagnostic_tick%60!=0:return
	var cache: RefCounted=probe_rt.get("_ground_cache")
	var gather: RefCounted=probe_rt.get("_gather")
	print("WALK_DIAGNOSTIC ",JSON.stringify({"frame":diagnostic_tick,"hits":cache.cache_hits if cache else -1,
		"misses":cache.cache_misses if cache else -1,"sectors":cache._sectors.size() if cache else -1,
		"cursor":gather._cursor if gather else -1,"pending":gather.pending.size() if gather else -1,
		"generation":probe_rt._snapshot_generation,"scene":probe_rt.stats}))
