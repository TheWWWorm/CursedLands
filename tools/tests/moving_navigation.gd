extends Node
## Authored Portal lift scripts and Catacombs door, with all movement classes.
## Work counts catch the old whole-map-per-step regression independent of CPU.
const LIFT := 2240358
const UP := 338779
const DOWN := 1357456
const CALL := 1369841
const DOOR := 1032949
class ReferenceNav extends NavGrid:
	var targets := {}
	func _record_footprint(info: Dictionary,t := -1.0) -> Dictionary:
		return super._record_footprint(info,float(targets.get(int(info.get("nid",0)),t)))
class MeasuredNav extends NavGrid:
	var labels := 0
	var updates := 0
	var update_us := 0
	var max_update_us := 0
	var updated_cells := 0
	func _label(l: Layer) -> void:
		labels+=1;super._label(l)
	func _update_region(r: Rect2i) -> void:
		var start := Time.get_ticks_usec()
		updates+=1;updated_cells+=r.get_area();super._update_region(r)
		var elapsed := Time.get_ticks_usec()-start
		update_us+=elapsed;max_update_us=maxi(max_update_us,elapsed)
	func reset() -> void:
		labels=0;updates=0;update_us=0;max_update_us=0;updated_cells=0

var checks := 0
var failures := 0
var w: GameWorld
var nav: MeasuredNav
var rows := []
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		if failures<20:printerr("FAIL ",label)

func ticks(n: int) -> void:
	for i in n:
		w.vm.tick(GameUnit.TICK);w.lever_sys.tick();w.time+=GameUnit.TICK

func position(nid: int) -> Vector3:
	return w.objects[nid].get_meta("ei").position

func snapshot(label: String) -> void:
	rows.append({"label":label,"updates":nav.updates,"labels":nav.labels,
		"update_us":nav.update_us,"max_update_us":nav.max_update_us})
	print("MOVING_NAV_SAMPLE ",JSON.stringify(rows.back()))

func verify_grid(label: String) -> void:
	# Fresh construction independently re-rasterizes the current authored
	# objects and all closures. Retained blocked-cell costs may be stale by
	# design; compare costs only at open cells inside the changed region.
	var fresh := ReferenceNav.new()
	# A lever's collision pose is its target, not the mesh's current morph.
	# Include anonymous scenery, which has no world.objects entry.
	fresh.targets=w.lever_sys._physical
	fresh.build(w.terrain,w.terrain.water_base,nav._fp_nodes.values())
	check(nav._hq==fresh._hq,label+" floor heights match fresh placement")
	check(nav._steep==fresh._steep,label+" slope boundaries match fresh placement")
	var r := nav._fp_rect(nav._fp[LIFT if w.zone.id=="gz1h" else DOOR]).grow(4)
	for cls in 8:
		var actual := nav.layer(cls)
		var expected := fresh.layer(cls)
		if actual.land!=expected.land:
			var differences := []
			for i in actual.land.size():
				if actual.land[i]!=expected.land[i]:
					differences.append({"cell":Vector2i(i%nav.size.x,i/nav.size.x),"land":[actual.land[i],expected.land[i]],
						"raw":[actual.raw[i],expected.raw[i]],"steep":[nav._steep[i],fresh._steep[i]],
						"scalar":[nav._closed_at(Vector2i(i%nav.size.x,i/nav.size.x),nav._group(cls),actual.raw),fresh._closed_at(Vector2i(i%nav.size.x,i/nav.size.x),fresh._group(cls),expected.raw)],
						"near_raw":[[actual.raw[i-1],actual.raw[i+1],actual.raw[i-nav.size.x],actual.raw[i+nav.size.x]],
						[expected.raw[i-1],expected.raw[i+1],expected.raw[i-nav.size.x],expected.raw[i+nav.size.x]]],
						"spans":[nav._spans.get(i,[]),fresh._spans.get(i,[])]})
					if differences.size()>=3:break
			print("NAV_DIFFERENCE ",label," class ",cls," ",differences)
		check(actual.land==expected.land,label+" passability class "+str(cls))
		var before := nav.labels
		check(actual.comp==expected.comp,label+" lazy connectivity class "+str(cls))
		var once := nav.labels
		check(once-before<=1 and actual.comp==expected.comp and nav.labels==once,label+" labels cached after read")
		var costs_equal := true
		for y in range(r.position.y,r.end.y):
			for x in range(r.position.x,r.end.x):
				var i := y*nav.size.x+x
				if actual.land[i]==0 and actual.cost[i]!=expected.cost[i]:costs_equal=false
		check(costs_equal,label+" local movement costs class "+str(cls))
		# Request a class afresh while its group cache survives a moving floor.
		var rebuilt := nav._build_layer(cls)
		check(rebuilt.land==expected.land,label+" late-built movement class "+str(cls))

func _ready() -> void:
	GameData.options.merge({"net_upnp":0,"net_directory":0,"net_lan":0,"autosave":0,"show_tutorial":0},true)
	var zone := "gz1h"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--zone="):zone=arg.trim_prefix("--zone=")
	var s := Session.new();add_child(s)
	var g := Game.new();g.session=s;s.game=g;add_child(g)
	s.set_physics_process(false);s.state=CampaignState.new();s.state.ensure_hero(0,"Human Hero")
	await s.enter_zone(zone,1,false)
	w=s.world;w.set_process(false);w.set_physics_process(false)
	nav=MeasuredNav.new();nav.build(w.terrain,w.terrain.water_base,w.map.object_nodes)
	w.nav=nav
	for u: GameUnit in w.unit_rows():
		u._occ_cell=Vector2i(-1,-1);u._trk_key=-1
		u._bucket=-1;u._abucket=-1;u._cbucket=-1;u._cabucket=-1
		nav.track_unit(u)
	for cls in 8:nav.native_graph(nav.layer(cls))
	# Hold unrelated story actions, while running the original lift family.
	w.vm.instances.clear()
	if zone=="gz1h":
		w.vm.spawn("Lift#01",[w.objects[LIFT]])
		check(w.objects.has(LIFT) and w.levers.has(CALL),"Portal lift fixture present")
		# A single SetCP must invalidate one union, never two intermediate maps.
		nav.reset();w.move_object(LIFT,position(LIFT)+Vector3(0,0,0.2))
		check(nav.updates==1,"one footprint replacement per object move")
		check(nav.labels==0,"SetCP does not flood any complete movement map")
		w.move_object(LIFT,position(LIFT)-Vector3(0,0,0.2))
		var origin := position(LIFT)
		var area := nav._fp_rect(nav._fp[LIFT]).get_area()
		var footprint_count := nav._fp.size()
		nav.reset();w.move_object(LIFT,origin+Vector3(80,-80,0))
		check(nav.updated_cells<=area*3,"distant SetCP updates footprints without the intervening map")
		check(nav.labels==0,"distant SetCP avoids global connectivity floods")
		w.move_object(LIFT,origin)
		check(nav._fp.size()==footprint_count,"moving object replaces its stamp without retaining old footprints")
		ticks(30);w.lever_sys.set_state(CALL,1,0);ticks(30)
		nav.reset();w.lever_sys.set_state(UP,1,0);ticks(500)
		check(is_equal_approx(position(LIFT).z,14.1),"original Portal up script reaches upper landing")
		check(nav.updates>100,"original script repeatedly moves platform and its switches")
		check(nav.labels==0,"entire lift ascent performs no global connectivity floods")
		snapshot("portal-up");verify_grid("upper landing")
		nav.reset();w.lever_sys.set_state(DOWN,1,0);ticks(500)
		check(is_equal_approx(position(LIFT).z,-0.4),"original Portal down script reaches lower landing")
		check(nav.labels==0,"entire lift descent performs no global connectivity floods")
		snapshot("portal-down");verify_grid("lower landing")
	else:
		check(w.levers.has(DOOR),"Catacombs door fixture present")
		for state in [1,0,1,0]:
			nav.reset();w.lever_sys.set_state(DOOR,state,0)
			check(nav.updates==1,"one footprint replacement per door state")
			check(nav.labels==0,"door state does not flood any complete movement map")
			snapshot("door-"+str(state));verify_grid("door-"+str(state))
	FileAccess.open("user://moving-navigation.json",FileAccess.WRITE).store_string(JSON.stringify(rows,"\t"))
	g.queue_free();s.queue_free()
	for i in 5:await get_tree().process_frame
	print("MOVING_NAVIGATION ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
