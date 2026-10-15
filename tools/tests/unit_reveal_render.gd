extends Node
class GroundWorld extends GameWorld:
	func ground_at(_x:float,_y:float)->float:return 0.0
var rows:=[]
var checks:=0
var failures:=0
func frames(n:int)->void:
	for i in n:await get_tree().process_frame
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL ",label)
func pixels(label:String,cam:Camera3D,u:GameUnit)->void:
	await RenderingServer.frame_post_draw
	var im:=get_viewport().get_texture().get_image()
	im.save_png("user://"+label+".png")
	var sum:=Vector2.ZERO
	var n:=0
	for y in im.get_height():
		for x in im.get_width():
			var c:=im.get_pixel(x,y)
			if c.r>0.5 and c.g<0.15 and c.b<0.15:sum+=Vector2(x,y);n+=1
	var centre:=sum/maxi(n,1)
	# Do not query scene-node transforms before the screenshot: doing so can
	# refresh the very renderer cache this regression is intended to observe.
	var expected:=cam.unproject_position(EISpace.pos(u.pos.x,u.pos.y,0.5))
	var row:={"label":label,"pixel_count":n,"centroid":str(centre),"expected":str(expected),"error":centre.distance_to(expected),"pos":str(u.pos),"drawn":str(u._drawn),"root":str(u.global_position),"sleeping":u._presentation_sleeping,"frame_drawing":u._frame_drawing}
	rows.append(row);print("REVEAL ",JSON.stringify(row))
	check(n>30 and absf(centre.x-expected.x)<im.get_width()*0.02,label+" rendered horizontal placement")
func _ready()->void:_run.call_deferred()
func _run()->void:
	GameData.options.merge({"auto_graphics":0,"vsync":0},true)
	get_tree().root.physics_interpolation_mode=Node.PHYSICS_INTERPOLATION_MODE_ON
	get_tree().physics_interpolation=true
	Engine.max_fps=60
	get_window().content_scale_mode=Window.CONTENT_SCALE_MODE_VIEWPORT
	get_window().content_scale_size=Vector2i(800,600)
	var env:=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color.BLACK;add_child(env)
	var cam:=Camera3D.new();add_child(cam);cam.projection=Camera3D.PROJECTION_ORTHOGONAL;cam.size=20;cam.position=Vector3(0,14,14);cam.look_at(Vector3.ZERO);cam.current=true
	var sound:=GameSound.new();var old:=GameSound.instance;sound.mixer=SoundMixer.new();sound.mixer.listener=Vector3.ZERO;GameSound.instance=sound
	var mat:=StandardMaterial3D.new();mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;mat.albedo_color=Color.RED
	for proto:String in ["BoarTutor","WolfGreyF0"]:
		for auth:bool in [false,true]:
			var w:=GroundWorld.new();w.authority=auth;add_child(w);w.set_physics_process(false);sound._world=w
			var u:=w.spawn_unit({"nid":9001,"prototype":proto,"position":Vector3(-3,0,0)})
			check(u!=null,proto+" created")
			for mesh:GeometryInstance3D in u._geoms:mesh.material_override=mat
			await frames(30)
			var label:=proto+str(auth)
			print("HIDDEN_MODE ",u.physics_interpolation_mode," ",u._frame_drawing," ",get_tree().physics_interpolation)
			u.hide();u.fogged=true
			w.set_physics_process(true)
			await frames(30)
			for step in 30:
				var snap:=u.snapshot();snap[1]=-3.0+float(step+1)*0.1;snap[2]=0.0
				if auth:u.pos=Vector2(snap[1],0)
				else:u.apply_snapshot(snap)
				await frames(6)
			await frames(120)
			u.fogged=false;u.show()
			await frames(2)
			await pixels(label+"-reveal",cam,u)
			await frames(15)
			await pixels(label+"-idle",cam,u)
			w.queue_free();await frames(3)
	GameSound.instance=old;sound.mixer.free();sound.free()
	FileAccess.open("user://unit-reveal.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"rows":rows},"\t"))
	print("UNIT_REVEAL ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
