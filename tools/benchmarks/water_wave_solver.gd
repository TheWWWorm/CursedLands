extends Node
## Compare the existing native solver with its production scalar oracle on
## identical immutable inputs. Timed calls exclude hashes and parity checks.
const Field = preload("res://src/game/fx/water_wave_field.gd")
var checks := 0
var failures := 0
var rows := []

func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok: failures+=1; printerr("FAIL ",label)

func digest(value: Variant) -> String:
	var hash := HashingContext.new(); hash.start(HashingContext.HASH_SHA256)
	hash.update(var_to_bytes(value)); return hash.finish().hex_encode()

func _ready() -> void:
	check(ClassDB.class_exists(&"WaterWaveKernel"),"native wave solver available")
	if failures: get_tree().quit(1); return
	var kernel := ClassDB.instantiate(&"WaterWaveKernel")
	for name: String in ["still","river","shore-step","crowd"]:
		var state := PackedFloat32Array(); state.resize(Field.SIZE*Field.SIZE*4)
		var domain := state.duplicate()
		for y in Field.SIZE:
			for x in Field.SIZE:
				var i := (y*Field.SIZE+x)*4
				state[i]=0.003*sin(x*0.2)+0.004*cos(y*0.17)
				state[i+1]=state[i]*0.95; state[i+2]=float((x+y)%17)/17.0
				domain[i]=2.0; domain[i+3]=1.0
				if name in ["river","crowd"]: domain[i+1]=0.9; domain[i+2]=-0.25
				if name=="shore-step":
					if x>90: domain[i]=5.0
					if y>100 or (x+y)%29==0: domain[i+3]=0.0
		var sources := PackedVector4Array()
		var weights := PackedVector2Array()
		for i in (16 if name=="crowd" else 1):
			sources.append(Vector4(14.25+(i%4)*0.6,14.25+(i/4)*0.6,0.25+i*0.1,0.5+i*0.2))
			weights.append(Vector2(0.25+i*0.04,i*1.7))
		var original := digest([state,domain,sources,weights])
		for steps in [1,8]:
			var samples := []
			var reference := PackedFloat32Array()
			for native: bool in [false,true,true,false]:
				var started := Time.get_ticks_usec()
				var result: PackedFloat32Array=kernel.step(state,domain,sources,weights,Vector2.ZERO,steps,0.75) if native else Field.solve(state,domain,sources,weights,Vector2.ZERO,steps,0.75)
				var elapsed := Time.get_ticks_usec()-started
				check(result.size()==state.size(),name+" result dimensions")
				if reference.is_empty(): reference=result
				check(result.to_byte_array()==reference.to_byte_array(),name+" exact scalar/native state")
				samples.append({"native":native,"microseconds":elapsed,"state_hash":digest(result)})
			check(digest([state,domain,sources,weights])==original,name+" inputs remain immutable")
			rows.append({"case":name,"steps":steps,"sources":sources.size(),"samples":samples})
	var report := {"checks":checks,"failures":failures,"rows":rows,"platform":OS.get_name(),
		"engine":Engine.get_version_info(),"scope":"CPU solver call time only; 128x128 domain, immutable equal inputs, ABBA; no GPU or FPS claim."}
	FileAccess.open("user://water-wave-solver.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
	print("WATER_WAVE_SOLVER checks=",checks," failures=",failures)
	get_tree().quit(1 if failures else 0)
