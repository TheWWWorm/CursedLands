extends "terrain_atlas_scene.gd"
## Additional visible-water coverage. A finite water-grid entry can be buried
## below land, so select a surface above the actual terrain height instead.
func liquid_focus(terrain: EITerrain) -> Vector3:
	var width := terrain.sectors_x*EITerrain.SECTOR
	var center := terrain.size_ei()*0.5
	var best := Vector3(INF,INF,INF); var distance := INF
	for i in terrain.water_base.size():
		var level := terrain.water_base[i]
		if not is_finite(level): continue
		var x := float(i%width)+0.5; var y := float(i/width)+0.5
		if level < terrain.height_at(x,y)+0.15: continue
		var d := Vector2(x,y).distance_squared_to(center)
		if d < distance:
			distance = d; best = Vector3(x,level,-y)
	check(best.is_finite(),"visible water surface found")
	print("VISIBLE_WATER_FOCUS ",best)
	return best
