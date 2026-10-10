extends Node
## Run identically against baseline/candidate packs. Hash every dynamic field
## and ordered classification, including exact-threshold and nonfinite inputs.
const Field = preload("res://src/game/fx/waterfall_field.gd")
var checks := 0
var failures := 0
var rows := []

func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok: failures+=1; printerr("FAIL ",label)

func digest(value: Variant) -> String:
	var h := HashingContext.new(); h.start(HashingContext.HASH_SHA256)
	h.update(var_to_bytes(value)); return h.finish().hex_encode()

func _ready() -> void:
	var random := RandomNumberGenerator.new(); random.seed=1937241
	var positive := 0
	for case in 96:
		var field := Field.new()
		field.size=Vector2i(65,33) if case%4==0 else Vector2i(random.randi_range(9,48),random.randi_range(9,40))
		var count: int=field.size.x*field.size.y
		field.rest.resize(count); field.rest.fill(INF)
		field.owners.resize(count); field.owners.fill(-1)
		field.bed.resize(count)
		for y in range(3,field.size.y-3):
			for x in range(4,mini(field.size.x-3,25)):
				var i: int=y*field.size.x+x
				var top: bool=y<field.size.y/2
				field.rest[i]=11.0 if top else 5.0
				field.owners[i]=0 if top else 1
				field.bed[i]=field.rest[i]-2.5
				if case%4!=0:
					var shape := random.randi_range(0,15)
					if shape<3: field.rest[i]+=random.randf_range(-3.0,3.0)
					if shape==3: field.rest[i]=field.rest[i-1]+[0.9,0.8999999,0.9000001][case%3]
					if shape==4: field.bed[i]=field.rest[i]+0.0500001
					if shape==5: field.owners[i]=-2
					if shape==6: field.rest[i]=NAN
					if shape==7: field.bed[i]=INF
					if shape==8: field.owners[i]=random.randi_range(0,3)
		var geometry := digest([field.rest,field.owners,field.bed])
		var states := []
		for levels: PackedFloat32Array in [PackedFloat32Array([0,0,0,0]),PackedFloat32Array([0.2,0,0,0]),
			PackedFloat32Array([0.2,6.2,-1,0]),PackedFloat32Array([-3,-3,0,1]),PackedFloat32Array(),
			PackedFloat32Array([1e30,-1e30,0,0]),PackedFloat32Array([NAN,INF,0,0]),PackedFloat32Array([0,0,0,0])]:
			var changed: bool=field.refresh(levels)
			positive+=int(not field.falls.is_empty())
			states.append({"changed":changed,"falls":field.falls.size(),"candidates":field.candidates,
				"hash":digest([field.layer,field.exposed,field.falls,field.candidates])})
		check(states.front().hash==states.back().hash,"levels restore all fields "+str(case))
		check(geometry==digest([field.rest,field.owners,field.bed]),"classification preserves authored snapshot "+str(case))
		rows.append({"case":case,"size":str(field.size),"states":states})
	check(positive>24,"positive controls retain real waterfall classifications")
	var report := {"checks":checks,"failures":failures,"positive_states":positive,"cases":rows}
	FileAccess.open("user://waterfall-levels.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
	print("WATERFALL_LEVELS checks=",checks," failures=",failures)
	get_tree().quit(1 if failures else 0)
