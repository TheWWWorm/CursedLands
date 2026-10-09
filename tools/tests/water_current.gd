extends "water_detail_clock.gd"
## Analytic geometry, scalar/native parity, real map data and rendered flow.
const Current = preload("res://src/game/fx/water_current.gd")
var maps := []

func compare(a: PackedFloat32Array,b: PackedFloat32Array,label: String) -> float:
	check(a.size()==b.size(),label+" dimensions")
	var error := 0.0
	for i in mini(a.size(),b.size()):
		if not is_finite(a[i]) or not is_finite(b[i]): error=INF; break
		error=maxf(error,absf(a[i]-b[i]))
	check(error<0.00001,label+" finite fields agree within 1e-5")
	return error

func analytic() -> void:
	var kernel: RefCounted
	if ClassDB.class_exists(&"WaterCurrentKernel"): kernel=ClassDB.instantiate(&"WaterCurrentKernel")
	var dim := Vector2i(65,33); var count := dim.x*dim.y
	var rest := PackedFloat32Array(); rest.resize(count); rest.fill(10)
	var bed := PackedFloat32Array(); bed.resize(count)
	var owner := PackedInt32Array(); owner.resize(count)
	var levels := PackedFloat32Array(); levels.resize(64)
	var cases := []
	for name: String in ["level-over-sloping-bed","tilt","holes","buried","mixed-levels"]:
		for y in dim.y:
			for x in dim.x:
				var i := y*dim.x+x
				bed[i]=x*0.04; owner[i]=0; rest[i]=10
				if name in ["tilt","holes","buried"]: rest[i]+=x*0.1+y*0.2
				if name=="holes" and (x+y)%7==0: owner[i]=-1
				if name=="buried": bed[i]=rest[i]+1
				if name=="mixed-levels" and x>=32: owner[i]=1
		levels[1]=0.4 if name=="mixed-levels" else 0.0
		var field: PackedFloat32Array=Current.build_script(dim,rest,owner,bed,levels)
		if kernel: compare(field,kernel.build(dim,rest,owner,bed,levels),name)
		for y in dim.y:
			for x in dim.x:
				var i := (y*dim.x+x)*4
				if name=="level-over-sloping-bed": check(field[i]==0 and field[i+1]==0 and field[i+2]==0,"sloping bed cannot create a current")
				if name=="tilt":
					check(absf(field[i]+0.1)<0.00001 and absf(field[i+1]-0.2)<0.00001,"planar flow points downhill in Godot X/Z, including shared x=32 seam")
					check(field[i+2]<0.00001,"planar flow has no bend")
				if name=="buried": check(field[i]==0 and field[i+1]==0 and field[i+3]==0,"buried layers cannot create a current")
				if name=="mixed-levels" and x in [31,32]: check(field[i]<0,"offset difference changes the mean surface flow")
		cases.append(name)
	check(Current.velocity(Vector2.ZERO)==Vector2.ZERO,"still water has no velocity")
	check(Current.velocity(Vector2(0.01,0))==Vector2.ZERO,"sub-onset surface slope stays still")
	check(absf(Current.velocity(Vector2(10,0)).length()-4)<0.00001,"river speed is bounded at four metres per second")
	check(Current.build_script(dim,rest,PackedInt32Array(),bed,levels).is_empty(),"malformed scalar data rejected")
	if kernel:
		check(kernel.build(dim,rest,PackedInt32Array(),bed,levels).is_empty(),"malformed native data rejected")
		check(kernel.build(Vector2i(-1,-1),rest,owner,bed,levels).is_empty(),"negative native dimensions rejected")
	rows.append({"case":"analytic","native_available":kernel!=null,"cases":cases})

func source_rules() -> void:
	var t := EITerrain.new(); t.sectors_x=1; t.sectors_y=1; t.grid_w=33
	t.heights.resize(33*33); t.liquid_ground.resize(32*32); t._lava.resize(64); t._level.resize(64)
	t.materials=[{"type":3,"color":Color(0.2,0.3,0.5,0.6),"self_illum":0.0}]
	var vertices := PackedVector3Array(); var uv2 := PackedVector2Array()
	for lane in 9:
		var x := 10+lane%3; var y := 10+lane/3
		vertices.append(Vector3(x-128.0/252.0,10+x*0.1+y*0.2,-y-128.0/252.0)); uv2.append(Vector2.ZERO)
	var arrays := []; arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices; arrays[Mesh.ARRAY_TEX_UV2]=uv2
	var mesh := ArrayMesh.new(); mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var node := MeshInstance3D.new(); node.name="Water_0_0"; node.mesh=mesh; t.add_child(node)
	var field: RefCounted=Current.new(t)
	for lane in 9:
		var i := (10+lane/3)*33+10+lane%3
		check(field.owners[i]==0 and absf(field.base[i]-vertices[lane].y)<0.00001,"two-metre tile origin recovers vertices beyond half-metre XY jitter")
	check(field.sample(Vector2(-0.1,-10))==Vector3.ZERO,"negative sample cannot truncate onto the map")
	field=null
	for mode: String in ["type4","lava","swamp","emission","sea"]:
		t.materials[0].type=4 if mode=="type4" else 3
		t.materials[0].self_illum=1.0 if mode=="emission" else 0.0
		t._lava[0]=1.0 if mode=="lava" else 0.0
		t.liquid_ground.fill(14 if mode=="swamp" else 0)
		t.resource_prefix="zone7" if mode=="sea" else ""
		field=Current.new(t)
		check(field.values.count(0.0)==field.values.size(),"non-river surface omitted: "+mode)
		field=null
	t.free()

func scan(t: EITerrain) -> Dictionary:
	var flow: RefCounted=t._current
	var running := 0; var peak := 0.0; var best := -INF; var focus := Vector3.INF; var direction := Vector2.ZERO
	for y in range(1,flow.size.y-1):
		for x in range(1,flow.size.x-1):
			var i: int=y*flow.size.x+x
			var v: Vector3=flow.value(i); var slope := Vector2(v.x,v.y).length()
			peak=maxf(peak,slope); running+=int(slope>0.015)
			if slope<0.04 or slope>0.5: continue
			if flow.owners[i] in EITerrain.SEA_MATERIALS.get(t.resource_prefix,[]) or x<8 or y<8 or x>flow.size.x-9 or y>flow.size.y-9: continue
			var height: float=flow.base[i]+t._level[maxi(flow.owners[i],0)]
			var depth: float=height-t.height_at(x,y)
			if depth<0.3 or depth>3: continue
			var score := -absf(slope-0.12)-absf(depth-1.0)*0.1
			# Prefer a patch with several metres of running, exposed water.
			for dy in range(-3,4):
				for dx in range(-3,4):
					var p := Vector2(x+dx,-y-dy)
					if flow.sample(p).length()<0.03: score-=0.2
			if score>best: best=score; focus=Vector3(x,height,-y); direction=Vector2(v.x,v.y)
	return {"running_vertices":running,"peak_slope":peak,"focus":str(focus),"focus_xyz":[focus.x,focus.y,focus.z] if focus.is_finite() else [],"direction":str(direction)}

func settle(flow: WeakRef) -> void:
	var until := Time.get_ticks_msec()+2500
	while flow.get_ref()._task>=0 and Time.get_ticks_msec()<until:
		await get_tree().create_timer(0.01,true,false,true).timeout
		flow.get_ref().poll()
	check(flow.get_ref()._task<0,"coalesced worker converges within bound")

func real_maps() -> void:
	for zone: String in (["zone1","zone8","zone9"] if "--current-astral" in OS.get_cmdline_user_args() else ["zone1","zone8","zone15"]):
		GameData.options["gfx_water_current"]=0
		var t := EITerrain.load_map(zone); check(t!=null,"map exists "+zone)
		if t==null: continue
		add_child(t); t.set_process(false)
		check(t._current==null,"off path owns no field "+zone)
		var navigation := t.water.duplicate(); var ground := t.heights.duplicate()
		GameData.options["gfx_water_current"]=1
		var began := Time.get_ticks_usec(); t.apply_gfx(); var preparation := Time.get_ticks_usec()-began
		var flow: RefCounted=t._current
		check(flow!=null and flow.texture!=null,"field installed "+zone)
		var info := scan(t)
		info.merge({"map":zone,"materials":str(t.materials),"size":str(flow.size),"texture_bytes":flow.values.size()*4,"native":flow._kernel!=null,
			"prepare_us":preparation,"build_us":flow.last_build_us,"upload_us":flow.last_upload_us,"conflicting_or_excluded_vertices":flow.conflicts})
		var started := Time.get_ticks_usec()
		var scalar: PackedFloat32Array=Current.build_script(flow.size,flow.base,flow.owners,flow.ground,t._level)
		info.scalar_build_us=Time.get_ticks_usec()-started
		info.max_native_scalar_error=compare(flow.values,scalar,"real "+zone)
		check(t.water==navigation and t.heights==ground,"flow does not change gameplay/terrain heights "+zone)
		var builds: int=flow.builds
		t.apply_gfx(); t._waves.advance(7.3); t._update_wave_parameters()
		check(flow.builds==builds,"options and wave phase reuse the field "+zone)
		if zone=="zone1":
			var initial: PackedFloat32Array=flow.values.duplicate()
			t.set_water_offset(0,0.2); t.set_water_offset(0,0.4)
			check(flow.builds==builds,"water-level changes coalesce before rendering")
			await get_tree().process_frame; await get_tree().process_frame
			await settle(weakref(flow))
			check(flow.builds==builds+1,"one rebuild publishes the final scripted water level")
			compare(flow.values,Current.build_script(flow.size,flow.base,flow.owners,flow.ground,t._level),"flooding")
			t.set_water_offset(0,0); t._refresh_water_current()
			await settle(weakref(flow))
			compare(flow.values,initial,"restored scripted water level")
			if flow._kernel==null:
				var requested := t._level.duplicate(); requested[0]=0.05
				flow.refresh(requested,true); var task: int=flow._task
				for step in range(1,21):
					requested[0]=step*0.02; flow.refresh(requested,true)
					check(flow._task==task,"continuous flooding does not enqueue another active job")
				await settle(weakref(flow))
				compare(flow.values,Current.build_script(flow.size,flow.base,flow.owners,flow.ground,requested),"coalesced final level")
				requested[0]=0.7; flow.refresh(requested,true)
				check(flow._task>=0,"teardown fixture owns a running worker")
			t.set_water_offset(0,0.1) # retirement while a deferred refresh is queued
		var weak := weakref(flow); flow=null
		GameData.options["gfx_water_current"]=0; t.apply_gfx()
		check(weak.get_ref()==null and t._current==null,"disable releases field snapshot "+zone)
		check(t._water_mat.get_shader_parameter("water_current")==null,"disable releases GPU texture "+zone)
		t.free(); await get_tree().process_frame
		maps.append(info); print("WATER_CURRENT_MAP ",JSON.stringify(info))

func _ready() -> void:
	for key in ["gfx_hd_textures","gfx_terrain","gfx_soft_ground","gfx_ground_contact","gfx_grass","gfx_biome_cover","gfx_vegetation_interaction","gfx_wind","gfx_water_interaction","gfx_water_caustics","gfx_water_current","gfx_weather_surfaces","gfx_volumetric","gfx_ssao","gfx_bloom","confine_mouse","vsync"]: GameData.options[key]=0
	GameData.options["gfx_water"]=1; Gfx.ensure_globals(); Engine.time_scale=0; Engine.max_fps=120
	process_mode=Node.PROCESS_MODE_ALWAYS
	analytic(); source_rules(); await real_maps()
	TexUpscale.shutdown(); await get_tree().process_frame
	FileAccess.open("user://water-current.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"rows":rows,"maps":maps},"\t"))
	print("WATER_CURRENT checks=",checks," failures=",failures); get_tree().quit(1 if failures else 0)
