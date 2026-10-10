extends "res://src/game/fx/water_wave_field.gd"
## Frozen pre-block domain builder (12978cc), used only as an exact-byte oracle.
## The production solver/lifetime methods remain inherited.

func _domain(terrain: EITerrain) -> void:
	var start := Time.get_ticks_usec()
	domain.resize(SIZE*SIZE*4); domain.fill(0)
	# Navigation stores an upper corner, which can be metres above a sloping
	# river's visible surface. Query the actual unposed triangles instead.
	# Cache one height/gradient per metre; window motion samples only new strips.
	# Keep only this window's cells, not a growing map-wide history.
	if _surface == null: _surface = Surface.new(terrain)
	_surface.begin_frame(false)
	var cells := {}; var samples := {}; var width := terrain.sectors_x*32
	var flow: RefCounted = terrain._current
	for y in SIZE:
		for x in SIZE:
			var point := (Vector2(origin)+Vector2(x+0.5,y+0.5))*CELL
			var cell := Vector2i(floori(point.x),floori(-point.y))
			if not cells.has(cell):
				var value := Vector4.ZERO
				var sample := {}
				if cell.x >= 0 and cell.y >= 0 and cell.x < width and cell.y < terrain.sectors_y*32:
					var at := cell.y*width+cell.x
					var midpoint := Vector2(cell.x+0.5,-cell.y-0.5)
					if not terrain.liquid_ground[at] in [13,14,255]:
						sample = _cells[cell] if _cells.has(cell) else _surface.sample(midpoint)
					var m := int(sample.get("material",-1))
					var h := float(sample.get("height",-INF))
					if m >= 0 and m < terrain.materials.size() and is_finite(h) and not sample.get("lava",false):
						var e := terrain.material_e(m)
						if int(terrain.materials[m].get("type",0)) in [2,3] and e.r+e.g+e.b == 0.0 and terrain._lava[m] == 0.0 and h > terrain.height_at(cell.x+0.5,cell.y+0.5)+0.04:
							var velocity := Vector2.ZERO
							if flow:
								var gradient: Vector3 = flow.sample(Vector2(cell.x+0.5,-cell.y-0.5))
								velocity = Current.velocity(Vector2(gradient.x,gradient.y))
							value = Vector4(h,velocity.x,velocity.y,m+1)
				cells[cell] = value; samples[cell] = sample
			var value: Vector4 = cells[cell]; var at := (y*SIZE+x)*4
			if value.w > 0:
				var slope: Vector2 = samples[cell].slope
				value.x+=slope.dot(point-Vector2(cell.x+0.5,-cell.y-0.5))
			domain[at]=value.x; domain[at+1]=value.y; domain[at+2]=value.z; domain[at+3]=value.w
	_cells=samples
	_levels = terrain._level.duplicate(); _flow_build = flow.builds if flow else -1
	last_domain_us = Time.get_ticks_usec()-start
