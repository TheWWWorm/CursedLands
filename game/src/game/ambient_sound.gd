class_name AmbientSound
extends RefCounted
## Ground ambience, the original (called every world tick by the
## terrain's while its flags have bit 8): the 3 × 3 terrain
## sectors (32 m) around the listener each vote for the ground type that
## dominates them; the three loudest types play their "circle" loop as a 2D
## sound and, by chance, a random one-shot near one of their sectors.

const SECTOR := 32.0
const RANGE2 := 2304.0   # (48 m)², the sector volume falls to 0 there
## Table (16 × 0x18 bytes): name, sound count (filled at load
## ), weight, remap (−1 = itself), pan limit, chance %.
const TYPES := [
	["Grass", 1.0, 30, 6], ["Ground", 1.0, 30, 6], ["Stone", 1.0, 30, 6], ["sand", 1.0, 30, 6],
	["rock", 1.5, 100, 4], ["field", 1.0, 30, 6], ["water", 3.0, 100, 6], ["road", 3.0, 30, 6],
	["", 0.0, 100, 0], ["snow", 1.0, 30, 6], ["Ice", 3.0, 30, 6], ["DryGrass", 1.0, 30, 6],
	["SnowBall", 1.0, 30, 6], ["lava", 3.0, 100, 0], ["swamp", 3.0, 100, 7], ["rock", 1.5, 100, 4],
]

var mixer: SoundMixer
var world: GameWorld
## Ambient set (terrain): "Dungeon", or the allod "Ingos" / "Suslanger"
## else "Gipat".
var set_name := "Gipat"
var _counts := {}          # "set/type" -> number of day sounds
var _hist := {}            # Vector2i sector -> PackedFloat32Array(16) tile counts
var _slots: Array = []     # [{type, handle}] of the playing loops


func _init(m: SoundMixer, w: GameWorld, dungeon: bool) -> void:
	mixer = m
	world = w
	var allod := String(w.zone.get("allod", "")).to_lower()
	set_name = "Dungeon" if dungeon else "Ingos" if allod == "ingos" else "Suslanger" if allod == "suslanger" else "Gipat"


## Its folders for EIAudio.prefetch: every type's loop and day sounds (the
## counts, _count) and the sounds of the hour's time of day.
func folders(hour: float) -> PackedStringArray:
	var out := PackedStringArray()
	for t: Array in TYPES:
		if String(t[0]):
			var d := "ambient\\%s\\%s" % [set_name, t[0]]
			out.append(d)
			out.append(d + "\\day")
			if daytime(hour) != "day":
				out.append(d + "\\" + daytime(hour))
	return out


func stop() -> void:
	for s: Dictionary in _slots:
		mixer.stop(int(s.handle))
	_slots.clear()


## the number of random sounds of a type = how many
## "ambient\<set>\<type>\day\<n>.wav" exist, counting n = 1, 2, … .
func _count(t: int) -> int:
	var key := "%s/%s" % [set_name, TYPES[t][0]]
	if not _counts.has(key):
		var n := 0
		while EIAudio.sfx("ambient\\%s\\%s\\day\\%d.wav" % [set_name, TYPES[t][0], n + 1]) != null:
			n += 1
		_counts[key] = n
	return _counts[key]


## the time-of-day folder from the world hour.
static func daytime(hour: float) -> String:
	var h := fposmod(hour, 24.0)
	if h >= 6.0 and h <= 18.0:
		return "day"
	if h > 2.0 and h < 6.0:
		return "morning"
	if h > 18.0 and h < 22.0:
		return "evening"
	return "night"


##  builds sector from the 16 x 16 land tiles AND every
## present liquid tile. Water does not replace the land beneath it. Counting
## the 1 m ground grid missed the second vote on sectors containing liquids.
func _sector(s: Vector2i) -> PackedFloat32Array:
	if _hist.has(s):
		return _hist[s]
	var t := world.terrain
	var out := PackedFloat32Array()
	if t and s.x >= 0 and s.y >= 0 and s.x < t.sectors_x and s.y < t.sectors_y:
		out.resize(16)
		var width := t.sectors_x * EITerrain.TILES
		for y in EITerrain.TILES:
			for x in EITerrain.TILES:
				var i := (s.y * EITerrain.TILES + y) * width + s.x * EITerrain.TILES + x
				for tiles in [t.land_tile, t.water_tile]:
					if i >= tiles.size() or int(tiles[i]) < 0:
						continue
					var code := int(tiles[i]) & 0x3fff
					var g: int = t.tile_types[code] if code < t.tile_types.size() else 15
					if g >= 0 and g < 16:
						out[g] += 1.0
	_hist[s] = out
	return out


func tick() -> void:
	if world == null or world.terrain == null:
		return
	var L := mixer.listener
	var sx := int(floor(roundf(L.x) / SECTOR))
	var sy := int(floor(roundf(L.y) / SECTOR))
	# Per type: [sum of vol², direction (last rel + Σ vol·rel)]
	var sum := PackedFloat32Array()
	sum.resize(16)
	var dirs: Array[Vector3] = []
	dirs.resize(16)
	var cells: Array = []   # 9 × {type (−1 = no sector), vol, rel}
	for gy in 3:
		for gx in 3:
			var sec := Vector2i(sx - 1 + gx, sy - 1 + gy)
			var counts := _sector(sec)
			if counts.is_empty():
				cells.append({"type": -1, "vol": 0.0, "rel": Vector3.ZERO})
				continue
			var cx := (sec.x + 0.5) * SECTOR
			var cy := (sec.y + 0.5) * SECTOR
			var rel := Vector3(cx - L.x, cy - L.y, world.ground_at(cx, cy) - L.z)
			var w := PackedFloat32Array()
			w.resize(16)
			for i in 16:
				w[i] += counts[i] * float(TYPES[i][1])
			var best := -1.0
			var bt := 0
			for i in 16:
				if w[i] > best:
					best = w[i]
					bt = i
			var d2 := minf(rel.x * rel.x + rel.y * rel.y, RANGE2)
			var vol := (RANGE2 - d2) / RANGE2 * 100.0
			sum[bt] += vol * vol
			dirs[bt] = rel
			cells.append({"type": bt, "vol": vol, "rel": rel})
	var order: Array = range(16)
	order.sort_custom(func(a, b): return sum[a] > sum[b])
	var top: Array = []
	for k in 3:
		var t: int = order[k]
		if sum[t] <= 0.001:
			break
		var dir := dirs[t]
		for c: Dictionary in cells:
			if int(c.type) == t:
				dir += float(c.vol) * (c.rel as Vector3)
		var vol := mini(roundi(sqrt(sum[t])), 100)
		var lim := float(TYPES[t][2])
		var pan := roundf(clampf(mixer.screen_pan(Vector2(dir.x, dir.y)), -lim, lim))
		top.append({"type": t, "vol": vol, "pan": pan})
		# The random one-shot: chance % per tick, from a random sector of
		# this type, ±16 m around its centre, 3D (priority 1, 32 / 48 m).
		if randi() % 100 + 1 <= int(TYPES[t][3]):
			var cell: Dictionary = cells[randi() % 9]
			while int(cell.type) != t:
				cell = cells[randi() % 9]
			var n := _count(t)
			if n > 0:
				var hour: float = world.session.state.world_time if world.session and world.session.state else 12.0
				var path := "ambient\\%s\\%s\\%s\\%d.wav" % [set_name, TYPES[t][0], daytime(hour), randi() % n + 1]
				var rel: Vector3 = cell.rel
				var p := L + rel + Vector3(randf_range(-16.0, 16.0), randf_range(-16.0, 16.0), 0.0)
				mixer.play3d(path, 1, p, 32.0, 48.0)
	# Loops: a type still in the top three keeps its sound
	# a new one starts "circle.wav" (2D, priority 1000, looped, camera fade);
	# the others stop.
	var old := _slots
	_slots = []
	for e: Dictionary in top:
		var h := -1
		for s: Dictionary in old:
			if int(s.type) == int(e.type):
				h = int(s.handle)
				old.erase(s)
				mixer.update2d(h, e.vol, e.pan)
				break
		if h == -1:
			h = mixer.play2d("ambient\\%s\\%s\\circle.wav" % [set_name, TYPES[e.type][0]], 1000, e.vol, e.pan, true, true)
		_slots.append({"type": e.type, "handle": h})
	for s: Dictionary in old:
		mixer.stop(int(s.handle))
