extends Node
const Reflection = preload("res://src/game/fx/water_reflection.gd")
var checks := 0
var failures := 0

class Probe extends Reflection:
	var scans := 0
	var height := 3.0
	func _select_plane(_source: Camera3D) -> float:
		scans += 1
		return height

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1;printerr("FAIL ",label)

func _ready() -> void:
	var terrain := EITerrain.new()
	var camera := Camera3D.new()
	var other := Camera3D.new()
	add_child(camera);add_child(other)
	var scenery := Probe.new();scenery.terrain=terrain
	var clouds := Probe.new();clouds.terrain=terrain
	check(scenery.visible_plane(camera)==3.0,"initial water plane")
	check(clouds.visible_plane(camera)==3.0 and clouds.scans==0,"cloud colour reuses scenery's scan")
	for i in 50:
		scenery.visible_plane(camera);clouds.visible_plane(camera)
	check(scenery.scans==1 and clouds.scans==0,"same poll interval scans once")
	terrain._reflection_plane_query.until=0;clouds.height=4.0
	check(clouds.visible_plane(camera)==4.0 and clouds.scans==1,"wall-clock expiry refreshes while simulation is held")
	check(scenery.visible_plane(camera)==4.0,"both consumers share the refreshed plane")
	clouds.height=5.0;scenery.request_refresh()
	check(clouds.visible_plane(camera)==5.0 and clouds.scans==2,"water edits invalidate both consumers")
	scenery.height=6.0
	check(scenery.visible_plane(other)==6.0 and scenery.scans==2,"camera switch scans immediately")
	var second := EITerrain.new();clouds.terrain=second
	check(clouds.visible_plane(other)==5.0 and clouds.scans==3,"another map has independent scan state")
	clouds.height=-INF;other.rotate_x(.2)
	check(clouds.visible_plane(other)==-INF and clouds.scans==4,"large turn refreshes before the poll deadline")
	clouds.height=7.0;other.rotate_x(-.2)
	check(clouds.visible_plane(other)==7.0 and clouds.scans==5,"return to visible water has no delayed reflection gap")
	other.position.x+=.1;clouds.visible_plane(other)
	check(clouds.scans==5,"small camera movement retains the bounded poll")
	other.position.x+=5;clouds.height=8.0
	check(clouds.visible_plane(other)==8.0 and clouds.scans==6,"camera jump refreshes the shared plane immediately")
	scenery.free();clouds.free();camera.free();other.free();terrain.free();second.free()
	print("CLOUD_WATER_QUERY checks=",checks," failures=",failures)
	get_tree().quit(int(failures>0))
