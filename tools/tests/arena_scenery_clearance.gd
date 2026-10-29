extends Node
var checks:=0
var failures:=[]
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);printerr("FAIL ",label)
func _ready()->void:
	var ground:=ArenaTerrain.create(false);add_child(ground)
	var scenery:=ArenaTerrain.scenery(ground,ground)
	var nav:=NavGrid.new();nav.build(ground,ground.water_base,scenery)
	check(scenery.size()==21,"all surrounding scenery remains present")
	for movement in range(8):
		var blocked:=[]
		for y in range(37,91):
			for x in range(37,91):
				var point:=NavGrid.center(Vector2i(x,y))
				if not nav.cell_open(point,movement):blocked.append(point)
		check(blocked.is_empty(),"entire fighting area is clear for movement class "+str(movement)+": "+str(blocked.slice(0,3)))
		# Include formerly valid home placements that were blocked in reflection,
		# and rear corners that could leave copied units stranded behind stones.
		for home in [Vector2(20.25,35.25),Vector2(21.25,35.75),Vector2(20.25,43.75),Vector2(20.25,20.25)]:
			var away:=Vector2(64-home.x,home.y)
			var route:=nav.find_path(away,Vector2(32,32),[],[],0.0,movement)
			check(not route.is_empty() and route[-1].distance_to(Vector2(32,32))<0.3,"mirrored creature reaches combat: "+str([movement,home]))
	ground.queue_free();await get_tree().process_frame
	print("ARENA_SCENERY_CLEARANCE ",JSON.stringify({"checks":checks,"failures":failures.size()}))
	get_tree().quit(0 if failures.is_empty() else 1)
