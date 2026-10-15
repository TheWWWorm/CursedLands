extends Node
func quant(a:Array)->Dictionary:
	a.sort();return {"median":a[a.size()/2],"p95":a[int(a.size()*.95)],"p99":a[int(a.size()*.99)],"max":a.back()}
func _ready()->void:
	GameData.options.merge({"autosave":0,"show_tutorial":0,"auto_graphics":0,"net_lan":0,"net_upnp":0,"net_directory":0},true)
	GameData.options.merge(GfxPresets.values(GfxPresets.VERY_LOW),true)
	var rows:=[]
	for zone:String in ["bz21k","gz21k","gz22k","gz23k","gz24k","gz25k","gz26k"]:
		seed(151031)
		var s:=Session.new();add_child(s);var g:=Game.new();g.session=s;s.game=g;add_child(g)
		s.state.ensure_hero(0,s._hero_proto(0));s.state.world_time=13.0;await s.enter_zone(zone,1,false)
		var w:=s.world
		w.set_process(false);w.set_physics_process(false);s.set_physics_process(false)
		for i in 200:w._tick(GameUnit.TICK)
		w.profile_us.clear();w.profile_counts.clear();w.profile_slow.clear();w.profile_simulation=true
		var times:=[];var worst:=[]
		for i in 600:
			w.profile_slow.clear()
			var start:=Time.get_ticks_usec();w._tick(GameUnit.TICK);var ms:=(Time.get_ticks_usec()-start)/1000.0;times.append(ms)
			if ms>20:worst.append({"tick":i,"ms":ms,"slow":w.profile_slow.duplicate(true)})
		w.profile_simulation=false
		var row:={"zone":zone,"units":w.units.size(),"tick_ms":quant(times),"sum_us":w.profile_us.duplicate(),"slow":worst,"sim_seconds":w.time}
		rows.append(row);print("INGOS_LOGIC ",JSON.stringify(row))
		g.queue_free();s.queue_free();await get_tree().process_frame
	FileAccess.open("user://ingos-logic.json",FileAccess.WRITE).store_string(JSON.stringify(rows,"  "))
	get_tree().quit()
