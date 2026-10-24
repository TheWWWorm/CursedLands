extends "res://tools/tests/path_trace_recording_route.gd"

func milestone(label: String) -> void:
	if label!="slope":await super(label);return
	var marks: GroundMarks=s.world.get_node("GroundMarks")
	var particles: ParticleFx=s.world.get_node("ParticleFx")
	print("MARK_COUNTS ",JSON.stringify({"blood":marks.blood_marks.size(),"feet":marks.foot_marks.size(),"fire":marks.fire_marks.size()}))
	for i in 2:
		marks.set_process(false);await stage("marks-off-"+str(i),6)
		marks.set_process(true);await stage("marks-restored-"+str(i),6)
	particles.set_process(false);await stage("particles-off",6)
	particles.set_process(true);await stage("particles-restored",6)
	FileAccess.open(out.path_join("marks-profile.json"),FileAccess.WRITE).store_string(JSON.stringify({"runs":route_results,"track":track,"failures":failures},"\t"))
	await finish()
