extends Node
## Exercise the real frame classifier with the reported 140 m / 60 frame
## route. Raster motion vectors remain valid during sustained fast travel.
const Controller=preload("res://src/game/fx/scene_raytrace.gd")
var checks:=0
var failures: Array[String]=[]
var controller: Node
var camera: Camera3D
var game_stub: Game
var rows: Array[Dictionary]=[]

func check(ok: bool,label: String) -> void:
	checks+=1;print("PASS " if ok else "FAIL ",label)
	if not ok:failures.append(label)

func frame(dt:=1.0/60.0) -> PackedByteArray:
	return controller._frame(camera,Vector2i(1920,1080),1,false,dt)

func prime() -> void:
	controller._history_key="";controller._path_signature=PackedByteArray()
	camera.position=Vector3(235.15686,19.39305,-170.16466);camera.rotation=Vector3(-.557968,.740299,0)
	camera.fov=55;Gfx.sun=Color.BLACK;Gfx.ambient=Color(.2,.2,.2);Gfx.fog_sky=Color(.2,.2,.2)
	frame();frame();frame()

func _ready() -> void:
	run.call_deferred()

func run() -> void:
	Gfx.ensure_globals();GameData.options.merge({"pt_mode":1,"pt_accumulation":0,"pt_sharc":0},true)
	game_stub=Game.new();game_stub._sky_cave=false
	controller=Controller.new(game_stub);controller._path_mode=true;add_child(controller);controller.set_process(false)
	camera=Camera3D.new();add_child(camera)
	for hz in [60,30,20]:
		prime();var resets:=0;var strict_resets:=0
		for i in 60:
			camera.position.x-=140.0/60.0
			var data:=frame(1.0/hz)
			if controller._rr_reset:resets+=1
			if data.decode_float(82*4)==0.0:strict_resets+=1
		check(resets<=1,"sustained 2.33 m/frame travel at %d Hz does not repeatedly reset RR (%d)"%[hz,resets])
		check(strict_resets==60,"strict PT cache rejects large movement at %d Hz"%hz)
		frame(1.0/hz);check(not controller._rr_reset,"stopping the route retains RR history at %d Hz"%hz)
		rows.append({"hz":hz,"rr_resets":resets,"strict_cache_resets":strict_resets})
	prime();camera.position.x+=7;frame()
	check(controller._rr_reset,"isolated seven-metre camera cut still resets RR")
	prime()
	for i in 8:camera.position.x-=2.34;frame()
	camera.position.x+=40;frame()
	check(controller._rr_reset,"teleport during continuous travel resets RR")
	prime()
	for i in 8:camera.position.x-=2.34;frame()
	camera.fov=60;camera.position.x-=2.34;frame()
	check(controller._rr_reset,"projection change during travel resets RR")
	prime()
	for i in 8:camera.position.x-=2.34;frame()
	Gfx.ambient=Color(.8,.8,.8);camera.position.x-=2.34;frame()
	check(controller._rr_reset,"abrupt global lighting change during travel resets RR")
	prime()
	for i in 8:camera.position.x-=2.34;frame()
	camera.rotate_y(PI);camera.position.x-=2.34;frame()
	check(controller._rr_reset,"view direction cut during travel resets RR")
	# The same velocity with ordinary frame-duration variation is continuous.
	prime();var variable_resets:=0
	for i in 60:
		var dt: float=[1.0/30.0,1.0/45.0,1.0/60.0][i%3]
		camera.position.x-=140.0*dt;frame(dt)
		if controller._rr_reset:variable_resets+=1
	check(variable_resets<=1,"variable frame times preserve continuous RR motion (%d resets)"%variable_resets)
	prime();variable_resets=0
	for i in 60:
		camera.position.x-=2.34;frame([1.0/30.0,1.0/45.0,1.0/60.0][i%3])
		if controller._rr_reset:variable_resets+=1
	check(variable_resets<=1,"fixed simulation steps survive variable presentation intervals (%d resets)"%variable_resets)
	prime();variable_resets=0
	for i in 60:
		camera.position.x-=2.34;frame()
		if controller._rr_reset:variable_resets+=1
		frame()
	check(variable_resets<=1,"duplicate presented poses between simulation ticks retain RR motion (%d resets)"%variable_resets)
	for i in 5:frame()
	camera.position.x-=7;frame()
	check(controller._rr_reset,"a real cut after a stopped camera still resets RR")
	prime()
	var lamp:=OmniLight3D.new();add_child(lamp);lamp.position=camera.position;lamp.omni_range=4
	lamp.add_to_group(Gfx.POINT_LIGHT_GROUP);controller._collect_lights(camera.position)
	var packet:=frame()
	check(not controller._rr_reset,"a newly nearby local light does not reset the whole RR image")
	check(packet.decode_float(82*4)==0,"new local light still invalidates strict PT caches")
	frame();lamp.position+=Vector3(200,0,0);controller._collect_lights(camera.position);packet=frame()
	check(not controller._rr_reset,"leaving local-light coverage retains RR surface detail")
	check(packet.decode_float(82*4)==0,"removed local light still invalidates strict PT caches")
	lamp.free()
	FileAccess.open("user://pt-travel-history.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"routes":rows},"\t"))
	controller.free();camera.free();game_stub.free()
	print("PT_TRAVEL_HISTORY ",checks," checks ",failures.size()," failures")
	get_tree().quit(0 if failures.is_empty() else 1)
