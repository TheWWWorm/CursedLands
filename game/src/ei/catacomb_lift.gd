extends RefCounted
## Give the original Catacombs lift room for a co-op party. Use the figure's
## width morph for both rendering and navigation, and move the frame and
## controls with it. The origin, length, height and original mover stay intact:
## the original script computes its vertical offset from the upper landing.

const LIFT := 2240358
const SWITCHES := [338779, 1357456]
const LEFT_FRAME := [1983521,2251725,2040961,2069726,2098507,2127311]
const RIGHT_FRAME := [2251724,2251726,2251727,2280587,2309456,2338345]
const LEFT_CARGO := [2338355,1052297]
const RIGHT_CARGO := [2338351,2338352,2171692,2206284,2338348]


static func apply(map_name: String, mob_name: String, mob: EIMob, terrain: EITerrain) -> Dictionary:
	if GameData.campaign_id != CampaignProfile.ASTRAL or map_name != "zone1dun2" or mob_name != map_name:
		return {}
	var objects := {}
	for o: Dictionary in mob.objects: objects[int(o.get("nid",0))] = o
	# Leave missing or already remodelled map data alone.
	var expected := {LIFT:["stbr6",Vector3(30.722,60.451,-0.3)],
		338779:["stst58",Vector3(29.62972,61.67737,0.2)],
		1357456:["stst58",Vector3(29.66708,62.68576,0.2)]}
	for nid: int in expected:
		var o: Dictionary = objects.get(nid,{})
		if o.get("template") != expected[nid][0] or not o.get("position",Vector3.INF).is_equal_approx(expected[nid][1]):
			return {}
	if not objects[LIFT].complexion.is_equal_approx(Vector3(0,1,0)): return {}
	for nid: int in LEFT_FRAME + RIGHT_FRAME + LEFT_CARGO + RIGHT_CARGO:
		if objects.get(nid,{}).get("template") != ("stst82" if nid in LEFT_CARGO else "stst83"):
			return {}
	objects[LIFT].complexion = Vector3(0,2.1,0)
	var relocated := {}
	for nid: int in SWITCHES + LEFT_FRAME + RIGHT_FRAME + LEFT_CARGO + RIGHT_CARGO:
		var o: Dictionary = objects[nid]
		var before: Vector3 = o.position
		var after := before
		after.x += -0.9 if nid in SWITCHES else (-1.0 if nid in LEFT_FRAME + LEFT_CARGO else 1.0)
		# The frame keeps its world height. Ground cargo follows the hillside.
		if nid not in LEFT_CARGO + RIGHT_CARGO:
			after.z += terrain.height_at(before.x,before.y) - terrain.height_at(after.x,after.y)
		o.position = after
		if nid in SWITCHES: relocated[nid] = [before,after]
	return relocated


## Old saves and their replay packets contain the original switch X/Y.
## Translate those once; script updates already use the relocated coordinates.
static func moved_position(relocated: Dictionary, nid: int, p: Vector3) -> Vector3:
	if not relocated.has(nid): return p
	var before: Vector3 = relocated[nid][0]
	if is_equal_approx(p.x,before.x) and is_equal_approx(p.y,before.y):
		p += (relocated[nid][1] as Vector3) - before
	return p
