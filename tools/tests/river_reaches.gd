extends Node
const Current = preload("res://src/game/fx/water_current.gd")
var checks := 0
var failures := 0
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1; printerr("FAIL ",label)
func _ready() -> void:
	var dim := Vector2i(81,41); var n := dim.x*dim.y
	var rest := PackedFloat32Array(); rest.resize(n); rest.fill(10)
	var bed := PackedFloat32Array(); bed.resize(n)
	var material := PackedInt32Array(); material.resize(n); material.fill(-1)
	var levels := PackedFloat32Array([0.0])
	for y in dim.y:
		for x in dim.x:
			var i := y*dim.x+x
			if (x <= 62 and y >= 18 and y <= 22) or (x >= 58 and x <= 62 and y >= 20 and y <= 38):
				material[i]=0; rest[i]=10.0-clampf((x-35)/10.0,0,1)
			if x>=70 and x<=77 and y>=3 and y<=10: material[i]=0
	var field := Current.build_script(dim,rest,material,bed,levels)
	var rows := []
	for point: Vector2i in [Vector2i(2,20),Vector2i(24,20),Vector2i(40,20),Vector2i(52,20),Vector2i(60,34),Vector2i(60,38),Vector2i(74,7)]:
		var at := (point.y*dim.x+point.x)*4
		var flow := Vector2(field[at],field[at+1]); rows.append({"point":str(point),"flow":str(flow),"speed":Current.velocity(flow).length()})
		if point.x==74: check(flow==Vector2.ZERO,"disconnected pond stays still")
		elif point.y==20: check(flow.x>0.04 and absf(flow.y)<0.01,"upstream, slope and downstream all flow east "+str(point))
		elif point.y==38: check(flow.y < -0.02 and Current.velocity(flow).length()>0.15,"terminal reach retains downstream motion")
		else: check(flow.y < -0.04 and absf(flow.x)<0.01,"flat reach follows the bend "+str(point))
	var kernel: RefCounted=ClassDB.instantiate(&"WaterCurrentKernel") if ClassDB.class_exists(&"WaterCurrentKernel") else null
	check(kernel==null or kernel.has_method("build_rivers"),"installed native helper supports continuous river reaches")
	if kernel and kernel.has_method("build_rivers"):
		var native: PackedFloat32Array=kernel.build_rivers(dim,rest,material,bed,levels)
		var error := 0.0
		for i in field.size(): error=maxf(error,absf(native[i]-field[i]))
		check(error<0.00001,"native and scalar river field agree"); rows.append({"native_error":error})
	else: rows.append({"native":"script fallback"})
	FileAccess.open("user://river-reaches.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"rows":rows},"\t"))
	print("RIVER_REACHES checks=",checks," failures=",failures," ",JSON.stringify(rows))
	get_tree().quit(int(failures>0))
