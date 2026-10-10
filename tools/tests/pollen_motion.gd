extends Node
## Measure the actual particle shader's rendered trajectory and cadence.
const Particles = preload("res://src/game/fx/ambient_particles.gd")
var checks := 0
var failures := 0
var view: SubViewport
var pollen: Particles

func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok: failures+=1; printerr("FAIL ",label)

func frame(seconds: float, wind := Vector4.ZERO) -> Image:
	pollen.update(seconds,Vector3.ZERO,Vector4.ZERO,wind,PackedVector4Array())
	for i in 4: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	return view.get_texture().get_image()

func centre(image: Image) -> Vector2:
	var sum := Vector2.ZERO; var weight := 0.0
	for y in image.get_height():
		for x in image.get_width():
			var c := image.get_pixel(x,y)
			var w := c.r+c.g+c.b
			sum+=Vector2(x,y)*w; weight+=w
	return sum/maxf(weight,0.00001)

func _ready() -> void:
	GameData.options.merge({"auto_graphics":0,"gfx_clouds":0,"gfx_original":0},true)
	Gfx.ensure_globals()
	view=SubViewport.new(); view.size=Vector2i(256,256); view.own_world_3d=true
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS; add_child(view)
	var env := WorldEnvironment.new(); env.environment=Environment.new()
	env.environment.background_mode=Environment.BG_COLOR; env.environment.background_color=Color.BLACK
	env.environment.tonemap_mode=Environment.TONE_MAPPER_LINEAR; view.add_child(env)
	var camera := Camera3D.new(); view.add_child(camera); camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=0.5; camera.position=Vector3(0,1.18,2); camera.make_current()
	pollen=Particles.new(); view.add_child(pollen)
	pollen.multimesh.instance_count=1; pollen.multimesh.visible_instance_count=1
	pollen.multimesh.set_instance_transform(0,Transform3D.IDENTITY)
	pollen.multimesh.set_instance_custom_data(0,Color(0.4,0,0.055,0))
	pollen.multimesh.custom_aabb=AABB(Vector3(-1,0,-1),Vector3(2,3,2))
	var positions: Array = []
	for seconds in [0.0,0.5,1.0,1.5,2.0]:
		var image := await frame(seconds)
		var point := centre(image); positions.append([seconds,point.x,point.y])
		check(point.x>20 and point.x<236 and point.y>10 and point.y<245,"pollen remains visibly inside capture at %.1fs"%seconds)
		image.save_png("user://pollen-motion-%.1f.png"%seconds)
	var dx := absf(float(positions[-1][1])-float(positions[0][1]))*0.5/256.0
	var rise := (float(positions[0][2])-float(positions[-1][2]))*0.5/256.0
	check(dx<0.001,"calm pollen has no circular horizontal orbit")
	check(rise>0.03 and rise<0.09,"two-second rise stays a slow float")
	var reference := await frame(2.0,Vector4(1,0,0.8,0))
	var clocks: Array = []
	for fps in [30,60,144,240]:
		var clock := EIWaterWaves.new()
		for i in fps*2: clock.advance(1.0/float(fps))
		var seconds := clock.time_ticks()*EIWaterWaves.TICK
		var image := await frame(seconds,Vector4(1,0,0.8,0))
		check(absf(seconds-2.0)<0.000001,"terrain clock holds real elapsed time at %d FPS"%fps)
		check(image.get_data()==reference.get_data(),"pollen pose is pixel-identical at %d FPS"%fps)
		clocks.append({"fps":fps,"seconds":seconds})
	check((await frame(2.0,Vector4(1,0,0.8,0))).get_data()==reference.get_data(),"held terrain time freezes rendered pollen")
	FileAccess.open("user://pollen-motion.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"positions":positions,"two_second_drift_m":dx,"two_second_rise_m":rise,"clocks":clocks},"\t"))
	view.free()
	print("POLLEN_MOTION ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
