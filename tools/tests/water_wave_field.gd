extends "water_interaction.gd"
## Analytic propagation/advection and actual controller lifetime. The scalar
## result is compared with the compiled path, not with a duplicate native loop.
const Field = preload("res://src/game/fx/water_wave_field.gd")
var kernel: RefCounted

func empty() -> PackedFloat32Array:
	var result := PackedFloat32Array(); result.resize(Field.SIZE*Field.SIZE*4); return result

func flat() -> PackedFloat32Array:
	var result := empty()
	for i in Field.SIZE*Field.SIZE: result[i*4]=2.0; result[i*4+3]=1.0
	return result

func compare(a: PackedFloat32Array,b: PackedFloat32Array,label: String) -> float:
	check(a.size()==b.size(),label+" dimensions")
	var error := 0.0
	for i in mini(a.size(),b.size()):
		if not is_finite(a[i]) or not is_finite(b[i]): error=INF; break
		error=maxf(error,absf(a[i]-b[i]))
	check(error<0.00001,label+" finite scalar/native error below 1e-5")
	return error

func evolved(state: PackedFloat32Array,domain: PackedFloat32Array,sources: PackedVector4Array,weights: PackedVector2Array,steps: int,seconds: float) -> PackedFloat32Array:
	return kernel.step(state,domain,sources,weights,Vector2.ZERO,steps,seconds) if kernel else Field.solve(state,domain,sources,weights,Vector2.ZERO,steps,seconds)

func analytical() -> void:
	if ClassDB.class_exists(&"WaterWaveKernel"): kernel=ClassDB.instantiate(&"WaterWaveKernel")
	check(kernel!=null,"current exported Linux helper exposes wave solver")
	var domain := flat(); var state := empty(); var centre := (64*Field.SIZE+64)*4
	state[centre]=0.04; state[centre+1]=0.04
	var no_sources := PackedVector4Array(); var no_weights := PackedVector2Array()
	var scalar := Field.solve(state,domain,no_sources,no_weights,Vector2.ZERO,8,8*Field.STEP)
	if kernel: compare(scalar,kernel.step(state,domain,no_sources,no_weights,Vector2.ZERO,8,8*Field.STEP),"impulse")
	check(absf(scalar[centre+8])>0.000001,"impulse propagates beyond its original footprint with no actor")
	check(scalar[centre+8]==scalar[centre-8] and scalar[centre+8]==scalar[centre+Field.SIZE*8],"still-water impulse is symmetric")
	var shifted := Field.shifted(scalar,Vector2i(7,-4))
	check(shifted[((64+4)*Field.SIZE+64-7)*4]==scalar[centre],"integer shift preserves the wave at its world position")
	check(Field.shifted(scalar,Vector2i(Field.SIZE,0)).count(0.0)==scalar.size(),"large teleport starts with a flat window")
	var damping := scalar
	for k in 20: damping=evolved(damping,domain,no_sources,no_weights,8,(k+2)*8*Field.STEP)
	var peak := 0.0
	for i in Field.SIZE*Field.SIZE: peak=maxf(peak,absf(damping[i*4]))
	check(peak<0.001,"unforced rings decay after five game seconds")
	var sources := PackedVector4Array([Vector4(16.125,16.125,0.55,2.0)])
	var weights := PackedVector2Array([Vector2(1.0,0.4)])
	state=evolved(empty(),domain,sources,weights,8,8*Field.STEP)
	check(state[centre+2]>0.99 and state[centre]<0,"visible body stamps depression and disturbed water")
	for i in Field.SIZE*Field.SIZE: domain[i*4+1]=0.9
	var downstream := Field.solve(state,domain,no_sources,no_weights,Vector2.ZERO,8,16*Field.STEP)
	if kernel: compare(downstream,evolved(state,domain,no_sources,no_weights,8,16*Field.STEP),"advected trail")
	check(downstream[centre+4+2]>downstream[centre-4+2],"trail continues downstream after the body leaves")
	var crowd := PackedVector4Array(); var phases := PackedVector2Array()
	for i in 16:
		crowd.append(Vector4(15.25+(i%4)*0.5,15.25+(i/4)*0.5,0.1+i*0.12,0.2+i*0.35))
		phases.append(Vector2(0.2+i*0.05,i*1.7))
	var crowded := Field.solve(state,domain,crowd,phases,Vector2.ZERO,8,0.75)
	if kernel: compare(crowded,evolved(state,domain,crowd,phases,8,0.75),"sixteen varied bodies")
	var bounded := true
	for i in Field.SIZE*Field.SIZE:
		if absf(crowded[i*4])>0.150001 or crowded[i*4+2]<0.0 or crowded[i*4+2]>1.0: bounded=false; break
	check(bounded,"crowded pressure and trail remain bounded")
	for y in Field.SIZE:
		for x in range(65,Field.SIZE): domain[(y*Field.SIZE+x)*4+3]=0
	var dry := evolved(state,domain,no_sources,no_weights,8,1.0)
	var leaked := 0
	for y in Field.SIZE:
		for x in range(65,Field.SIZE):
			var at := (y*Field.SIZE+x)*4
			if dry[at]!=0 or dry[at+2]!=0: leaked+=1
	check(leaked==0,"dry cells cannot retain wave height or trail")
	domain=flat()
	for y in Field.SIZE:
		for x in range(65,Field.SIZE): domain[(y*Field.SIZE+x)*4]=5.0
	state=empty(); state[centre]=0.04; state[centre+1]=0.04
	var separate := evolved(state,domain,no_sources,no_weights,8,1.0)
	check(separate[centre+4]==0,"separate water levels do not exchange waves")
	check(Field.solve(empty(),PackedFloat32Array(),sources,weights,Vector2.ZERO,1,0).is_empty(),"malformed scalar domain rejected")
	if kernel:
		check(kernel.step(empty(),flat(),sources,weights,Vector2.ZERO,9,0).is_empty(),"native catch-up limit enforced")
		var bad := flat(); bad[10]=NAN
		check(kernel.step(empty(),bad,sources,weights,Vector2.ZERO,1,0).is_empty(),"nonfinite native domain rejected")
	rows.append({"case":"analytic","native_available":kernel!=null,"decayed_peak":peak})

func settle(field: Field) -> void:
	for i in 1200:
		field.poll()
		if field._task<0: return
		await get_tree().process_frame
	check(false,"worker finishes within bounded fixture wait")

func lifetime() -> void:
	var astral := "--wave-astral" in OS.get_cmdline_user_args()
	var t := EITerrain.load_map("zone1")
	check(t!=null,"real campaign water loads")
	if t==null: return
	add_child(t); t.set_process(false)
	var p := centre(t); var field := Field.new()
	var point := Vector2(p.x,p.z)
	var source := PackedVector4Array([Vector4(p.x,p.z,0.5,2)])
	var weight := PackedVector2Array([Vector2.ONE])
	var navigation := t.water.duplicate(); var heights := t.heights.duplicate()
	field.advance(t,0,point,source,weight)
	check(field.valid and field.texture!=null,"first visible source allocates bounded field")
	check(field.texture.get_width()==128 and field.state.size()*4==262144,"fixed 256 KiB texture payload")
	field.advance(t,0.2,point,source,weight); await settle(field)
	check(field.steps_done==6,"fixed steps use elapsed game time")
	var pressed := false
	for i in Field.SIZE*Field.SIZE:
		if field.state[i*4]<0 and field.state[i*4+2]>0: pressed=true; break
	check(pressed,"real map coverage receives visible-body pressure")
	var before := field.state.duplicate(); var uploads := field.uploads
	field.advance(t,0.2,point,source,weight)
	check(field.state==before and field.uploads==uploads,"held terrain time does no solve or upload")
	field.advance(t,0.2,point+Vector2(5,0),source,weight)
	check(field.steps_done==6,"paused window shift does not simulate")
	field.advance(t,0.1,point,source,weight)
	check(field.state.count(0.0)>=Field.SIZE*Field.SIZE*3,"clock rewind clears stale height and trail")
	field.advance(t,0.2,point,source,weight); await settle(field)
	var material := int(t.water_mat[floori(-p.z)*t.sectors_x*32+floori(p.x)])
	t.set_water_offset(material,0.4)
	field.advance(t,0.2,point,PackedVector4Array(),PackedVector2Array())
	var disturbed := false
	for i in field.state.size()/4:
		if field.state[i*4]!=0 or field.state[i*4+2]!=0: disturbed=true; break
	check(not disturbed,"flooding invalidates previous surface history before reuse")
	t.set_water_offset(material,0)
	check(t.water==navigation and t.heights==heights,"field leaves navigation and land geometry intact")
	var native := field._kernel!=null
	field.advance(t,0.3,point,source,weight)
	var pending := field._task>=0
	field.clear()
	check(field._task<0 and field.texture==null and field.state.is_empty() and field.domain.is_empty(),"disable joins worker and releases snapshots and texture")
	rows.append({"case":"lifetime","campaign":"astral" if astral else "base","native":native,"worker_on_clear":pending,"focus":str(p),"step_us":field.last_step_us,"domain_us":field.last_domain_us})
	t.free()

func _ready() -> void:
	for key in ["gfx_hd_textures","gfx_terrain","gfx_soft_ground","gfx_ground_contact","gfx_grass","gfx_biome_cover","gfx_vegetation_interaction","gfx_wind","gfx_water_interaction","gfx_water_caustics","gfx_water_current","gfx_water_waves","gfx_weather_surfaces","gfx_volumetric","gfx_ssao","gfx_bloom","confine_mouse","vsync"]: GameData.options[key]=0
	GameData.options["gfx_water"]=1; Gfx.ensure_globals(); Engine.time_scale=0; Engine.max_fps=120
	process_mode=Node.PROCESS_MODE_ALWAYS
	analytical(); await lifetime()
	TexUpscale.shutdown(); await get_tree().process_frame
	FileAccess.open("user://water-wave-field.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"rows":rows},"\t"))
	print("WATER_WAVE_FIELD checks=",checks," failures=",failures); get_tree().quit(1 if failures else 0)
