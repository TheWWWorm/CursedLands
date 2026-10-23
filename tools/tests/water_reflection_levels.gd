extends Node
## A broad lower pond and an occluded upper pond surround a narrow stream.
## Either used to win by cell count as camera tilt changed the visible set.
const Reflection = preload("res://src/game/fx/water_reflection.gd")
class Flat extends EITerrain:
	func height_at(_x: float, _y: float) -> float: return -2.0
var checks := 0
var failures := []
func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok: failures.append(label);printerr("FAIL ",label)
func _ready() -> void:
	var terrain := Flat.new();terrain.sectors_x=4;terrain.sectors_y=4
	terrain.water.resize(128*128);terrain.water.fill(-INF)
	terrain.liquid_ground.resize(128*128);terrain.liquid_ground.fill(255)
	add_child(terrain);terrain.set_process(false)
	for y in range(25,30):
		for x in range(29,32):terrain.water[y*128+x]=2.0;terrain.liquid_ground[y*128+x]=11
	var reflection := Reflection.new();reflection.terrain=terrain;add_child(reflection);reflection.set_process(false)
	var camera := Camera3D.new();add_child(camera);camera.current=true;camera.far=100;camera.fov=75
	camera.position=Vector3(30,4,-20)
	for pool_height: float in [0.0,6.0]:
		for y in range(40,76):
			for x in range(12,49):terrain.water[y*128+x]=pool_height;terrain.liquid_ground[y*128+x]=11
		for pitch: float in [-0.1,-0.3,-0.5]:
			camera.rotation=Vector3(pitch,0,0);reflection.plane=-INF
			var selected := reflection._select_plane(camera)
			check(is_equal_approx(selected,2.0),"foreground stream survives broad pool at %.1f, pitch %.1f" % [pool_height,pitch])
	terrain.water.fill(6.0)
	check(not is_finite(reflection._select_plane(camera)),"surfaces above the eye cannot disable a lower mirror")
	var native := EITerrain.load_map("zone13");add_child(native);native.set_process(false);reflection.terrain=native
	var at := Vector2(424,208);var level := native.water_at(at.x,at.y)
	camera.position=Vector3(at.x,level+1.6,-at.y)
	for yaw: float in [2.84,3.14,3.44]:
		for pitch: float in [0.0,-0.25,-0.5]:
			camera.look_at(camera.position+Vector3(cos(yaw)*cos(pitch),sin(pitch),-sin(yaw)*cos(pitch)))
			reflection.plane=-INF
			var selected := reflection._select_plane(camera)
			check(absf(selected-level)<0.05,"real Karansul pool retains its original surface level at yaw %.2f pitch %.2f (%.3f / %.3f)" % [yaw,pitch,selected,level])
			check(reflection._select_plane(camera,true)==selected,"liquid cell index selects the full scan's level at yaw %.2f pitch %.2f" % [yaw,pitch])
	TexUpscale.shutdown()
	print("WATER_REFLECTION_LEVELS ",checks," checks ",failures)
	get_tree().quit(1 if failures else 0)
