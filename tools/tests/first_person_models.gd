extends Node
var failures:=0
var checks:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL ",label)
func _ready()->void:
	for weld in [false,true]:
		EIUnitModel.smooth_joints=weld
		var model:=EIUnitModel.create({"prototype":"Human Hero","complexion":Vector3(0.5,0.5,0.5)})
		add_child(model)
		var pose:=model._head.transform
		var unit:=GameUnit.new()
		unit.set_process(false);unit.set_physics_process(false);unit.model=model
		add_child(unit)
		var height:=EnemyBars.head_top(unit)
		model._head.position.y+=0.2;EnemyBars._tops.clear()
		check(EnemyBars.head_top(unit)>height+0.15,"health bar follows animated head with smoothed joints "+str(weld))
		model._head.transform=pose;unit.free()
		model.set_head_hidden(true)
		model.refresh_detailed_head()
		check(not model._head.is_visible_in_tree() and model._head.transform==pose,"hide head without deforming animation bones, weld "+str(weld))
		if weld:
			check(model._welded_head==null and not model._head.visible and model.get_node("Skeleton/Body").visible,"welded body stays visible with head hidden")
		model.set_part_visible("hd",true)
		check(not model._head.visible,"equipment/severed-part refresh preserves first-person hiding")
		model.set_head_hidden(false)
		check(model._head.visible,"leaving first person restores intact head")
		model.set_head_hidden(true);model.set_part_visible("hd",false);model.set_head_hidden(false)
		check(not model._head.visible,"leaving first person does not restore a severed head")
		model.free()
	EIUnitModel.smooth_joints=false
	print("FIRST_PERSON_MODELS ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
