extends Node
## Fixed-seed, headless native simulation costs; not a rendered FPS benchmark.
func _ready()->void:
	GameData.options.merge({"autosave":0,"show_tutorial":0,"auto_graphics":0,"net_lan":0,"net_upnp":0,"net_directory":0},true)
	var rows:=[]
	for zone in ["gz15h","gz17h","bz14h","bz15h"]:
		seed(15418)
		var s:=Session.new();add_child(s);s.set_physics_process(false)
		var g:=Game.new();g.session=s;s.game=g;add_child(g)
		s.state.ensure_hero(0,s._hero_proto(0));s.state.world_time=13.0;s._enter_zone(zone,1,false)
		var w:=s.world;w.set_process(false);w.set_physics_process(true);w.vm.briefings._check=INF
		for i in 100:w._tick(GameUnit.TICK)
		w.profile_simulation=true;w.profile_us.clear();w.profile_counts.clear();w.profile_slow.clear()
		var samples:=[]
		for i in 400:
			var start:=Time.get_ticks_usec();w._tick(GameUnit.TICK);samples.append((Time.get_ticks_usec()-start)/1000.0)
		samples.sort()
		var row:={"zone":zone,"actors":w.units.size(),"median_ms":samples[200],"p95_ms":samples[380],"profile_us":w.profile_us,"counts":w.profile_counts}
		rows.append(row);print("SUSLANGER_LOGIC ",JSON.stringify(row))
		g.queue_free();s.queue_free();await get_tree().process_frame
	FileAccess.open("user://suslanger-logic.json",FileAccess.WRITE).store_string(JSON.stringify(rows,"\t"))
	get_tree().quit()
