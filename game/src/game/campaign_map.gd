class_name CampaignMap
extends RefCounted
## Parses "map.txt" from texts.res: the campaign's zone graph.
## Zone types: "game" (explorable island zone), "brief" (village/base hub with
## briefings and traders), "edge" (a path between zones shown on the island map).

## zone id -> {id, allod, type, mpr, mob, size: Vector2i, minimap, objtex, figure,
## position: Vector3, weather, sky, camera, restrict, exits: {n: {to, to_exit, deploy: Rect2, remove: Rect2, area: Rect2 (record, the last of the two in file order), view, passtime}}}
var zones := {}
## quest id -> global map position (map.txt "#quest": first line)
var quests := {}
## quest id -> its area on the zone picture of the objectives screen: zone
## x, y pairs (map.txt "#quest": second line, read by the original)
var quest_areas := {}
## allod -> its global map figures (map.txt "#allod"): [arrow, pointball,
## quest marker, island ("down"), armor] (the original allod record +4..).
var allods := {}


static func load_from(texts: EIResArchive) -> CampaignMap:
	var m := CampaignMap.new()
	m._parse(EIText.ansi(texts.read("map.txt")))
	return m


func zone(id: String) -> Dictionary:
	return zones.get(id.to_lower(), {})


## Finds the zone whose .mpr is `mpr` (e.g. "zone1" -> gz1g).
func zone_by_map(mpr: String) -> Dictionary:
	for z: Dictionary in zones.values():
		if z.get("mpr", "") == mpr.to_lower():
			return z
	return {}


func _parse(text: String) -> void:
	var cur := {}
	var exit := {}
	var directive := ""
	for raw in text.split("\n"):
		var line := raw.strip_edges()
		var c := line.find("//")
		if c >= 0:
			line = line.substr(0, c).strip_edges()
		if line.is_empty() or line.begins_with("##"):
			continue
		var w := line.split(" ", false)
		if line.begins_with("#"):
			directive = w[0].substr(1).to_lower()
			match directive:
				"zone":
					cur = {"id": w[1].to_lower(), "allod": w[2] if w.size() > 2 else "",
						"type": w[3] if w.size() > 3 else "game", "exits": {}}
					zones[cur.id] = cur
					exit = {}
				"exit":
					exit = {}
					cur.exits[int(w[1])] = exit
				"quest":
					quests[w[1].to_lower()] = Vector3.ZERO
					quest_areas[w[1].to_lower()] = PackedVector2Array()
					cur = {"_quest": w[1].to_lower(), "_line": 0}
				"allod":
					cur = {"_allod": w[1].to_lower()}
					allods[cur._allod] = PackedStringArray()
			continue
		match directive:
			"allod": allods[cur._allod].append(w[0].to_lower())
			"quest":
				cur._line += 1
				if cur._line == 1 and w.size() >= 3:
					quests[cur._quest] = Vector3(float(w[0]), float(w[1]), float(w[2]))
				elif cur._line == 2:
					for i in range(0, w.size() - 1, 2):
						quest_areas[cur._quest].append(Vector2(float(w[i]), float(w[i + 1])))
			"res":
				cur.mpr = w[0].to_lower()
				cur.mob = w[1].to_lower() if w.size() > 1 else cur.mpr
			"maps":
				if not cur.has("size"):
					cur.size = Vector2i(int(w[0]), int(w[1]))
				else:
					cur.minimap = w[0]
					cur.objtex = w[1] if w.size() > 1 else ""
			"figure": cur.figure = w[0]
			"camera": cur.camera = w[0]
			"weather": cur.weather = w[0]
			"sky": cur.sky = w[0]
			"restrict": cur.restrict = Vector3(float(w[0]), float(w[1]), float(w[2]))
			"position":
				var p := Vector3(float(w[0]), float(w[1]), float(w[2]))
				if cur.has("_quest"):
					quests[cur._quest] = p
				else:
					cur.position = p
			"exit": exit.merge({"to": w[0].to_lower(), "to_exit": int(w[1])}, true)
			"deploy":   # #deploy fills record....
				exit.deploy = _rect(w)
				exit.area = exit.deploy
			"remove":   # #remove fills.. only (the minimap's exit mark)
				exit.remove = _rect(w)
				exit.area = exit.remove
			"view": exit.view = float(w[0])
			"passtime": exit.passtime = float(w[0])
			"deployangle": exit.deploy_angle = float(w[0])


## the original (global map route): depth-first walk from `start`
## over the zone exits. Reaching `dest` records the exit's target entrance with
## the passtime summed along the path (−1 when `dest` is next to `start`; the
## last exit's passtime is not added), keeping the smallest time per entrance;
## the walk may pass through `dest` once. A zone is walked through when it is
## not on the current path and: a game zone with GS var "z.<id>" = 2, an edge
## with "z.<id>" ≠ 1, or a brief zone with "z.<id>" ≠ 0. `var_of` reads a GS
## var. Returns {entrance: hours}.
func routes(start: String, dest: String, var_of: Callable) -> Dictionary:
	var out := {}
	var z := zone(start)
	if not z.is_empty():
		_route(z, dest.to_lower(), var_of, [], 0.0, [false], out)
	return out


func _route(z: Dictionary, dest: String, var_of: Callable, stack: Array, time: float, through: Array, out: Dictionary) -> void:
	for n in z.get("exits", {}):
		var ex: Dictionary = z.exits[n]
		var t := zone(String(ex.get("to", "")))
		if t.is_empty():
			continue
		var passed := false
		if t.id == dest:
			var ent := int(ex.get("to_exit", 0))
			var v := -1.0 if stack.is_empty() else time
			if not out.has(ent) or time < float(out[ent]):
				out[ent] = v
			if through[0]:
				continue
			through[0] = true
			passed = true
		if not stack.has(t.id):
			var st := float(var_of.call("z." + t.id))
			var go := false
			match String(t.get("type", "game")):
				"game": go = is_equal_approx(st, 2.0)
				"edge": go = not is_equal_approx(st, 1.0)
				"brief": go = not is_zero_approx(st)
			if go:
				stack.append(z.id)
				_route(t, dest, var_of, stack, time + float(ex.get("passtime", 0.0)), through, out)
				stack.pop_back()
		if passed:
			through[0] = false


static func _rect(w: PackedStringArray) -> Rect2:
	var a := Vector2(float(w[0]), float(w[1]))
	var b := Vector2(float(w[2]), float(w[3]))
	return Rect2(a, b - a).abs()
