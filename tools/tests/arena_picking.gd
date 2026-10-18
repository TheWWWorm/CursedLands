extends Node
## Keep the exhaustive selection result while avoiding meshes behind a hit.
var checks := 0
var failures := 0
var reference_queries := 0
var optimized_queries := 0
var field: CountedField

class CountedField extends ArenaField:
	var queries := 0
	func unit_rects(unit: GameUnit) -> Array:
		queries += 1
		return super.unit_rects(unit)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		if failures < 12: printerr("FAIL ",label)

func reference(at: Vector2) -> GameUnit:
	var exact := []; var nearby := []; var headers := []
	var camera := field.camera
	var to_view := camera.global_transform.affine_inverse()
	for unit: GameUnit in field.match_state.world.unit_rows():
		if unit.dead or unit.hidden or not unit.visible or camera.is_position_behind(unit.global_position): continue
		if field.numeric_health:
			var head := field.health_anchor(unit)
			if Rect2(head-Vector2(29,40)*field.ui_scale,Vector2(58,44)*field.ui_scale).has_point(at):
				headers.append([at.distance_to(head-Vector2(0,15)*field.ui_scale),unit])
		if not unit.may_cover(camera,at,10*field.ui_scale): continue
		reference_queries += 1
		var rects := unit.screen_rects(camera)
		if rects.is_empty(): continue
		var rect := Rect2(rects[0])
		var distance := at.distance_to(at.clamp(rect.position,rect.end))
		if distance > 10*field.ui_scale: continue
		var depth := -(to_view*unit.global_position).z
		var part_hit := false
		for part in rects.slice(1):
			if Rect2(part).has_point(at): part_hit=true;break
		(exact if part_hit else nearby).append([distance,depth,unit])
	if not headers.is_empty():
		headers.sort_custom(func(a,b):return a[0]<b[0])
		return headers[0][1]
	var hits := exact if not exact.is_empty() else nearby
	if hits.is_empty(): return null
	hits.sort_custom(func(a,b):return a[0]<b[0] if not is_equal_approx(a[0],b[0]) else a[1]<b[1])
	return hits[0][2]

func compare(at: Vector2) -> void:
	var expected := reference(at)
	field.queries = 0
	var actual := field._pick(at)
	optimized_queries += field.queries
	check(actual==expected,"same exact/header/nearby target at "+str(at))

func _ready() -> void:
	GameData.options.merge({"auto_graphics":0,"gfx_soft_ground":0,"gfx_contact_shadows":0,"confine_mouse":0},true)
	var battle := ArenaMatch.new();add_child(battle);battle.set_process(false);battle.set_physics_process(false)
	field=CountedField.new();field.size=Vector2(1280,800);add_child(field);field.set_process(false)
	field.view.size=Vector2i(1280,800);field.match_state=battle;battle.create_world(field.stage)
	field.zoom=17;field._update_camera()
	var units: Array[GameUnit]=[]
	for side in 2:
		for family in [0,11,24,26,32,35,36,38,39]:
			var index:=units.size()
			var unit:=battle._spawn({"id":ArenaRules.FAMILIES[family].forms[2],"team":side,"rank":2,"point":Vector2(14.5+(index%6)*0.6,15.0+int(index/6)*0.7)})
			check(unit!=null and unit.model!=null,"native crowded fixture loads "+str(family))
			if unit:unit.set_process(false);units.append(unit)
	if failures:get_tree().quit(1);return
	for pose in ["idle","walk","attack"]:
		for unit:GameUnit in units:
			unit.model.act(pose,1,0.0);unit.model.player.advance(0.23);unit.model.flush_pending_pose()
		for yaw in [0.15,0.85,2.05]:
			field.yaw=yaw;field._update_camera();field._screen_bounds.clear();EnemyBars._tops.clear()
			for k in [1.0,2.0]:
				field.ui_scale=k
				for numeric in [false,true]:
					field.numeric_health=numeric
					for unit:GameUnit in units:
						var rects:=unit.screen_rects(field.camera)
						if not rects.is_empty():
							var rect:=Rect2(rects[0])
							compare(rect.get_center());compare(rect.position-Vector2.ONE*5*k);compare(rect.end+Vector2.ONE*5*k)
						compare(field.health_anchor(unit)-Vector2(0,15)*k)
					for x in 5:
						for y in 4:compare(Vector2(450+x*95,200+y*115))
	check(optimized_queries<reference_queries*0.7,"crowded picking skips at least 30 percent of detailed bounds without changing targets")
	battle.free();field.free()
	print("ARENA_PICKING checks=",checks," failures=",failures," bounds=",reference_queries," -> ",optimized_queries)
	get_tree().quit(1 if failures else 0)
