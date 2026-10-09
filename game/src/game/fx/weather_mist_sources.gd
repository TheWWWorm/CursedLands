extends RefCounted
## Conservative local mist masks from the actual authored liquid triangles.
## One small mask is built incrementally; no world-size texture or scenery
## index is needed. Empty cells are cached by the controller as well.
const Habitats = preload("res://src/game/fx/ambient_habitats.gd")
const CELL := 12.0
const GRID := 6
const STEP := CELL/GRID
const LAYER_HEIGHT := 4.0
const MAX_HEIGHT := 8.0
const BATCH := 12
const BUDGET_US := 2000
var field: Habitats
var key := Vector2i.ZERO
var image: Image
var cursor := 0
var count := 0
var low := INF
var high := -INF
var building := false
var last_build_us := 0


func _init(terrain: EITerrain) -> void:
	field=Habitats.new(terrain,false)


func allowed() -> bool:
	return field.biome in ["gipat","gipat2","dead_city","ingos","suslanger"]


func source(p: Vector2) -> Dictionary:
	if not allowed(): return {}
	var ground:=field.ground(p)
	var water:=field.liquid(p)
	if ground.is_empty() or water.is_empty(): return {}
	if float(water.height)<=float(ground.height)+0.06: return {}
	var kind:=int(water.type)
	if kind not in [6,14] or (field.biome=="ingos" and kind==6): return {}
	var size:=Vector2i(field.terrain.size_ei())
	var at:=int(p.y)*size.x+int(p.x)
	# A known solid authored floor above the liquid suppresses its source.
	if field.terrain.surface[at]>float(water.height)+0.10: return {}
	return {"height":water.height,"type":kind,"material":water.material}


func begin(cell: Vector2i) -> void:
	key=cell; cursor=0; count=0; low=INF; high=-INF; building=true
	image=Image.create(GRID,GRID,false,Image.FORMAT_RGBAF)
	field._water.begin_frame(false)


func advance() -> bool:
	var started:=Time.get_ticks_usec(); var end:=mini(cursor+BATCH,GRID*GRID)
	while cursor<end:
		var pixel:=Vector2i(cursor%GRID,cursor/GRID); cursor+=1
		var centre:=Vector2(key)*CELL+(Vector2(pixel)+Vector2.ONE*0.5)*STEP
		var hit:=source(centre)
		if not hit.is_empty():
			var valid:=true
			# Conservative five-tap sampled coverage, not a proof that every
			# sub-texel point is wet. Gives up narrow puddles/shore wisps.
			var half:=STEP*0.5-0.01
			for offset: Vector2 in [Vector2(-half,-half),Vector2(half,-half),Vector2(-half,half),Vector2(half,half)]:
				var corner:=source(centre+offset)
				if corner.is_empty() or corner.type!=hit.type or absf(float(corner.height)-float(hit.height))>0.30:
					valid=false; break
			if valid:
				var height:=float(hit.height)
				image.set_pixelv(pixel,Color(float(hit.type==6),float(hit.type==14),height,1.0))
				low=minf(low,height); high=maxf(high,height); count+=1
		if Time.get_ticks_usec()-started>=BUDGET_US: break
	last_build_us=Time.get_ticks_usec()-started
	building=cursor<GRID*GRID
	return not building


func result() -> Dictionary:
	if building or count==0 or high-low+LAYER_HEIGHT>MAX_HEIGHT: return {}
	return {"image":image,"count":count,"low":low,"high":high,"key":key}
