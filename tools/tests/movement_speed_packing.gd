extends Node
## The reference is captured from both original executable prefixes.
## Verify all four selected gaits and running-speed turning while walking.
var checks := 0
var failures := 0
var mismatches := []

func check(ok: bool, label: String, actual: float, expected: float) -> void:
	checks+=1
	if not ok:
		failures+=1
		mismatches.append({"case":label,"actual":actual,"expected":expected})
		if failures<12:printerr("FAIL ",label," got=",actual," expected=",expected)

func _ready() -> void:
	var source: String = get_script().resource_path.get_base_dir()+"/fixtures/original_movement_speed.json"
	var fixture:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(source))
	var campaign := "lost_in_astral" if GameData.campaign_id==CampaignProfile.ASTRAL else "original"
	var u:=GameUnit.new()
	for row:Dictionary in fixture.campaigns[campaign].rows:
		u.race={"speeds":Array(row.input.speeds)};u.proto={"tuning_move":float(row.input.factor)}
		for gait in 4:
			u.stance=GameUnit.STANCE_KNEEL if gait==2 else GameUnit.STANCE_CRAWL if gait==3 else GameUnit.STANCE_NONE
			u.running=gait==0
			for turning in [false,true]:
				var selected:=0 if turning and gait==1 else gait
				var expected:=float(row.bytes[selected])*2.0/255.0*float(row.bytes[4])/25.5
				var actual:=u._move_base(turning)
				check(absf(actual-expected)<1e-12,"%s/gait%d/turn%d"%[row.input.id,gait,int(turning)],actual,expected)
		u.stance=GameUnit.STANCE_NONE;u.running=true
		# Overloaded players must still select the walk byte for translation.
		u.stats={"load":2.0,"max_load":1.0}
		var walk:=float(row.bytes[1])*2.0/255.0*float(row.bytes[4])/25.5
		check(absf(u._move_base()-walk)<1e-12,String(row.input.id)+"/overloaded",u._move_base(),walk)
		u.stats={}
	u.free()
	FileAccess.open("user://movement-speed-packing.json",FileAccess.WRITE).store_string(JSON.stringify({
		"campaign":campaign,"checks":checks,"failures":failures,"mismatches":mismatches,
		"native":fixture.campaigns[campaign].sha256,"scope":fixture.scope},"\t"))
	print("MOVEMENT_SPEED_PACKING ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
