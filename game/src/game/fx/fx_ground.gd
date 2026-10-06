class_name FxGround
extends RefCounted
## Remake: the ground heights the particle callbacks read (FxEmitter.ground),
## as plain data. ParticleFx takes one per tick on the main thread
## (ParticleFx.ground_snapshot) and hands it to every emitter in update_pre,
## so an emitter updated on a WorkerThreadPool worker samples the terrain
## without touching the GameWorld or EITerrain nodes. The packed arrays are
## shared copy-on-write: a change the main thread makes to the terrain gets
## its own copy, this one stays as it was for the tick.
## Authored floor planes use NavGrid's immutable snapshot for that revision.

var heights := PackedFloat32Array()
var surface := PackedFloat32Array()
var floors := {}
var grid_w := 0
var cells_w := 0
var cells_h := 0
var valid := false


static func of(w: GameWorld) -> FxGround:
	var g := FxGround.new()
	var t: EITerrain = w.terrain if w else null
	if t == null or t.heights.is_empty() or t.grid_w <= 0:
		return g
	g.heights = t.heights
	g.surface = t.surface
	g.floors = w.nav.floor_snapshot()
	g.grid_w = t.grid_w
	g.cells_w = t.sectors_x * EITerrain.SECTOR
	g.cells_h = t.sectors_y * EITerrain.SECTOR
	g.valid = g.surface.size() >= g.cells_w * g.cells_h
	return g


## GameWorld.ground_at, including authored object planes: 0 without terrain.
func at(x: float, y: float) -> float:
	if not valid:
		return 0.0
	var ground := EITerrain.ground_in(heights, surface, grid_w, cells_w, cells_h, x, y)
	return NavGrid.ground_in(floors, Vector2(x, y), ground)
