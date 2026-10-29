extends RefCounted
## Mirror the raster's snow vertex lift in acceleration geometry.
## Authored UV/tile coordinates, including shifted MPR vertices, identify the
## logical grid. Collision and source arrays remain unchanged.
var terrain: EITerrain
var tiles: Image
var cells: Image
var profiles := {}
const MAX_SECTORS := 128
var _sectors := {}
var _source_key := []
var cache_hits := 0
var cache_misses := 0
var _cache_enabled := not OS.get_cmdline_user_args().has("--ei-rt-no-ground-cache")

func configure(source: EITerrain) -> void:
	var key := [source.get_instance_id(),source._tile_tex,source._cell_tex,Gfx.on("gfx_soft_ground"),source._cliffs,source.snow_melt_revision]
	if _cache_enabled and key==_source_key:return
	_source_key=key;profiles.clear();_sectors.clear();tiles=null;cells=null
	terrain=source
	if not Gfx.on("gfx_soft_ground") or terrain.land_tile.is_empty() or terrain.heights.is_empty():return
	tiles=terrain._ground_tile_image()
	cells=terrain._surface_cell_image()

func profile_at(cell: Vector2i) -> Vector2:
	cell=cell.clamp(Vector2i.ZERO,tiles.get_size()-Vector2i.ONE)
	var value:=tiles.get_pixelv(cell)
	return Vector2(value.b,value.a)

func vertex_profile(grid: Vector2i) -> Vector2:
	grid=grid.clamp(Vector2i.ZERO,Vector2i(terrain.grid_w-1,terrain.sectors_y*32))
	if profiles.has(grid):return profiles[grid]
	var index:=grid.y*terrain.grid_w+grid.x
	var p:=Vector2(grid)+terrain.land_xy[index]
	var tile:=Vector2i((p*0.5).floor())
	var result:=Vector2.ZERO
	if profile_at(tile).x>0:
		var at:=p*0.5-Vector2.ONE*0.5
		var base:=Vector2i(at.floor());var blend:=at-at.floor()
		blend=Vector2(smoothstep(0,1,blend.x),smoothstep(0,1,blend.y))
		result=profile_at(base).lerp(profile_at(base+Vector2i.RIGHT),blend.x).lerp(
			profile_at(base+Vector2i.DOWN).lerp(profile_at(base+Vector2i.ONE),blend.x),blend.y)
		var local:=p-Vector2(tile)*2.0
		var mask:=1.0
		for edge: Array in [[Vector2i.LEFT,local.x],[Vector2i.RIGHT,2.0-local.x],
			[Vector2i.UP,local.y],[Vector2i.DOWN,2.0-local.y]]:
			if profile_at(tile+edge[0]).x==0.0:mask*=smoothstep(0,0.6,edge[1])
		var water:=cells.get_pixelv(Vector2i(p.floor()).clamp(Vector2i.ZERO,cells.get_size()-Vector2i.ONE))
		var water_y:=water.r+terrain._level[clampi(roundi(water.a),0,63)]
		result*=mask*smoothstep(0.025,0.10,terrain.heights[index]-water_y)
		result*=1.0-float(terrain.snow_melt.get(index,0.0)) # SnowMelt, as soft_vertex_profile
	profiles[grid]=result
	return result

func profile(grid: Vector2) -> Vector2:
	var cell:=Vector2i(grid.floor()).clamp(Vector2i.ZERO,Vector2i(terrain.grid_w-2,terrain.sectors_y*32-1))
	var p:=(grid-Vector2(cell)).clamp(Vector2.ZERO,Vector2.ONE)
	if p.x+p.y<=1.0:
		return vertex_profile(cell)*(1.0-p.x-p.y)+vertex_profile(cell+Vector2i.RIGHT)*p.x+vertex_profile(cell+Vector2i.DOWN)*p.y
	return vertex_profile(cell+Vector2i.ONE)*(p.x+p.y-1.0)+vertex_profile(cell+Vector2i.RIGHT)*(1.0-p.y)+vertex_profile(cell+Vector2i.DOWN)*(1.0-p.x)

func arrays(source: Array,sector_id := 0) -> Array:
	if tiles==null:return source
	# Sector source arrays are immutable for their node's lifetime. Recenter
	# snapshots can share the lifted arrays; they still pack/cull independently.
	# The terrain's surface tables and soft-ground option invalidate this cache.
	if _cache_enabled and sector_id!=0 and _sectors.has(sector_id):
		var cached: Array=_sectors[sector_id]
		_sectors.erase(sector_id);_sectors[sector_id]=cached;cache_hits+=1
		return cached
	cache_misses+=1
	if profiles.size()>65536:profiles.clear()
	var result:=source.duplicate()
	var points: PackedVector3Array=source[Mesh.ARRAY_VERTEX].duplicate()
	var uv: PackedVector2Array=source[Mesh.ARRAY_TEX_UV]
	var uv2: PackedVector2Array=source[Mesh.ARRAY_TEX_UV2]
	var per_row:=float(terrain.texture_size)/terrain.tile_size
	var border:=8.0/terrain.texture_size*per_row
	for i in points.size():
		var id:=roundi(uv2[i].y)
		var tile:=Vector2i(id%tiles.get_width(),id/tiles.get_width())
		var code:=terrain.land_tile[id]
		var packed_tile:=code&63
		var origin:=Vector2(packed_tile%int(per_row),int(per_row)-1-packed_tile/int(per_row))
		var local:=(uv[i]*per_row-origin-Vector2.ONE*border)/(1.0-2.0*border)
		local=Vector2(local.x,1.0-local.y)-Vector2.ONE*0.5
		match (4-((code>>14)&3))%4:
			1:local=Vector2(-local.y,local.x)
			2:local=-local
			3:local=Vector2(local.y,-local.x)
		var grid:=(Vector2(tile)+(local+Vector2.ONE*0.5).clamp(Vector2.ZERO,Vector2.ONE))*2.0
		points[i].y+=profile(grid).x
	result[Mesh.ARRAY_VERTEX]=points
	if _cache_enabled and sector_id!=0:
		if _sectors.size()>=MAX_SECTORS:_sectors.erase(_sectors.keys()[0])
		_sectors[sector_id]=result
	return result
