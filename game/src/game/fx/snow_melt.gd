extends RefCounted
## Remake (Snow deformation): the loose snow round the map's lit fires has
## already thawed when a zone is shown. Derived only from the authored TORCH
## records (camp fires and braziers), so every load, client and saved game gets
## the same field; nothing is saved and nothing grows in over time. Unlit
## braziers (strength 0), carried torches and spell fires leave the snow alone.
## The field is a sparse {grid vertex index: thaw 0..1}; the loose-snow profile
## (GroundSurfaceShader.soft_vertex_profile) and its CPU mirrors are scaled by
## 1 - thaw. Collision, navigation and the original terrain stay unchanged.

const MIN_RADIUS := 1.8
const RADIUS_PER_STRENGTH := 4.0 # torch_strength: flame size, light radius / 10
const MAX_RADIUS := 4.5
## Inside this fraction of the radius the loose layer has gone entirely.
const CORE := 0.4
## A torch mounted high on a wall barely warms the ground beneath it.
const HEIGHT_FADE := Vector2(1.0, 3.0)
## World-anchored irregularity of the thaw's edge (fraction of the radius).
const EDGE_NOISE := 0.22

static var _noise: FastNoiseLite


## (x, y, radius, strength) of every lit TORCH record, in record order.
static func sources(mob: EIMob) -> Array[Vector4]:
	var out: Array[Vector4] = []
	if mob == null:
		return out
	for o: Dictionary in mob.objects:
		if String(o.get("kind", "")) != "TORCH":
			continue
		var s := float(o.get("torch_strength", 0.0))
		if not (s > 0.0):
			continue
		var p: Vector3 = o.get("position", Vector3.ZERO)
		var off: Vector3 = o.get("torch_offset", Vector3.ZERO)
		# Object z is relative to the ground; ParticleSystem.setup_zone places
		# the flame at the same unrotated offset.
		var lift := 1.0 - smoothstep(HEIGHT_FADE.x, HEIGHT_FADE.y, p.z + off.z)
		if lift <= 0.0:
			continue
		var radius := clampf(MIN_RADIUS + s * RADIUS_PER_STRENGTH, MIN_RADIUS, MAX_RADIUS)
		out.append(Vector4(p.x + off.x, p.y + off.y, radius, lift))
	return out


static func _edge_noise() -> FastNoiseLite:
	if _noise == null:
		_noise = FastNoiseLite.new()
		_noise.seed = 52817
		_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		_noise.fractal_type = FastNoiseLite.FRACTAL_NONE
		_noise.frequency = 0.45
	return _noise


## Thaw at EI point `p` from one source (before combining sources by max).
static func thaw(source: Vector4, p: Vector2) -> float:
	var centre := Vector2(source.x, source.y)
	var distance := p.distance_to(centre)
	if distance >= source.z * (1.0 + EDGE_NOISE):
		return 0.0
	var rough := _edge_noise().get_noise_2d(p.x, p.y) * EDGE_NOISE
	var r := distance / (source.z * (1.0 + rough))
	return (1.0 - smoothstep(CORE, 1.0, r)) * source.w


## Sparse thaw per terrain grid vertex. Only vertices whose surrounding tiles
## carry loose snow are stored; other ground has nothing to thaw.
static func field(terrain: EITerrain, fires: Array[Vector4]) -> Dictionary:
	var out := {}
	if terrain == null or fires.is_empty() or terrain.grid_w <= 0:
		return out
	var rows := terrain.sectors_y * EITerrain.SECTOR + 1
	var tiles := Vector2i(terrain.sectors_x * EITerrain.TILES, terrain.sectors_y * EITerrain.TILES)
	for fire: Vector4 in fires:
		var reach := fire.z * (1.0 + EDGE_NOISE)
		var lo := Vector2i(floori(fire.x - reach), floori(fire.y - reach)).clamp(Vector2i.ZERO, Vector2i(terrain.grid_w - 1, rows - 1))
		var hi := Vector2i(ceili(fire.x + reach), ceili(fire.y + reach)).clamp(Vector2i.ZERO, Vector2i(terrain.grid_w - 1, rows - 1))
		for y in range(lo.y, hi.y + 1):
			for x in range(lo.x, hi.x + 1):
				var index := y * terrain.grid_w + x
				var amount := thaw(fire, Vector2(x, y) + terrain.land_xy[index])
				if amount <= 0.0 or amount <= float(out.get(index, 0.0)):
					continue
				if not _loose_near(terrain, Vector2i(x, y), tiles):
					continue
				out[index] = amount
	return out


static func _loose_near(terrain: EITerrain, vertex: Vector2i, tiles: Vector2i) -> bool:
	# The four tiles sharing this vertex (a vertex on a tile edge belongs to two).
	for dy in [-1, 0]:
		for dx in [-1, 0]:
			var tile := Vector2i((vertex.x + dx) >> 1, (vertex.y + dy) >> 1)
			if tile.x < 0 or tile.y < 0 or tile.x >= tiles.x or tile.y >= tiles.y:
				continue
			var id := terrain.land_tile[tile.y * tiles.x + tile.x] & 0x3fff
			if id < terrain.tile_types.size() and terrain.tile_types[id] in SoftGroundDeform.TYPES:
				return true
	return false


## Bilinear thaw at an EI point, for CPU queries between grid vertices.
static func at(terrain: EITerrain, p: Vector2) -> float:
	if terrain.snow_melt.is_empty():
		return 0.0
	var rows := terrain.sectors_y * EITerrain.SECTOR + 1
	var q := p.clamp(Vector2.ZERO, Vector2(terrain.grid_w - 1, rows - 1))
	var lo := Vector2i(q.floor()).clamp(Vector2i.ZERO, Vector2i(terrain.grid_w - 2, rows - 2))
	var f := q - Vector2(lo)
	var melt := terrain.snow_melt
	var i := lo.y * terrain.grid_w + lo.x
	return lerpf(lerpf(melt.get(i, 0.0), melt.get(i + 1, 0.0), f.x),
		lerpf(melt.get(i + terrain.grid_w, 0.0), melt.get(i + terrain.grid_w + 1, 0.0), f.x), f.y)
