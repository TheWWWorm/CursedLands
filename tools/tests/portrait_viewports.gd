extends Node
## Render PartyFaces with the supplied save's trained build and a default hero.
## Selection/idle animation is driven manually, then settled to an exact pose
## for comparison. This checks UI viewports, not campaign/co-op networking.
## World/Session are data-only fixtures; only portrait/UI processing is live.
var faces:PartyFaces
var units:Array[GameUnit]=[]
var rows:=[]
var failures:=0
var w:GameWorld
var s:Session
var g:Game
var first_bounds:={}
func frames(n:int)->void:
	for i in n:await get_tree().process_frame
func _ready()->void:run.call_deferred()
func run()->void:
	if OS.get_cmdline_user_args().has("--validate-only"):
		print("PASS portrait viewport test parses");get_tree().quit();return
	if DisplayServer.get_name()=="headless":
		push_error("Portrait viewport test requires rendering");get_tree().quit(2);return
	GameData.options.merge({"display_mode":0,"auto_graphics":0,"show_tutorial":0,"phys_interp":1},true)
	await frames(15);GameData._window_gen+=1;get_window().mode=Window.MODE_WINDOWED
	get_tree().physics_interpolation=true
	w=GameWorld.new();add_child(w);w.set_process(false);w.set_physics_process(false)
	s=Session.new();s.online=true;s.state=CampaignState.new();s.world=w
	g=Game.new();g.world=w;g.session=s
	for i in 2:
		var u:=w.spawn_unit({"nid":i+1,"prototype":"Human Hero","position":Vector3(1+i,1,0),"complexion":Vector3(0.0,0.55,0.9) if i==0 else GameUnit.proto_complexion(GameData.db.find("monster_prototypes","Human Hero"))})
		u.controller=i;u.set_meta("hero",{"prototype":"Human Hero"});u.set_process(false);u.set_physics_process(false);units.append(u)
	if Portrait.face_names(units[0])!=Portrait.face_names(units[1]):
		failures+=1;push_error("Training changed the main hero portrait identity")
	var canvas:=Control.new();add_child(canvas);canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	faces=PartyFaces.new();faces.game=g;canvas.add_child(faces)
	for size:Vector2i in [Vector2i(1920,1080),Vector2i(1280,1024),Vector2i(720,1280),Vector2i(2560,1440),Vector2i(1920,1080)]:
		get_window().size=size;await frames(5)
		for selected:bool in [true,false]:
			g.selected.assign([units[0]] if selected else [])
			await frames(2)
			for cell in faces._cells:
				var p:Portrait=cell[1];p.set_process(false);p._head_motion=0
				for i in 90:p._update_head(1.0/30.0)
				p._head_motion=0;p._selection_q=Quaternion(Vector3.LEFT,PI/14) if p.selected else Quaternion.IDENTITY;p._update_head(0)
			await frames(3);await RenderingServer.frame_post_draw
			var index:=rows.size()
			get_viewport().get_texture().get_image().save_png("user://portrait-pair-%02d.png"%index)
			var row:={"index":index,"window":str(get_window().size),"canvas":str(Interface800.canvas_size(faces)),"selected":selected,"faces":[]}
			for cell in faces._cells:
				var p:Portrait=cell[1]
				var b:=p._model.global_basis
				var axes:=Vector3(b.x.length(),b.y.length(),b.z.length())
				var ok:=absf(axes.x-axes.y)<.00001 and absf(axes.x-axes.z)<.00001 and p._vp.size==Vector2i(p.size) and not p._model.is_physics_interpolated() and not p._face_cam.is_physics_interpolated()
				if not ok:failures+=1
				var im:=p._vp.get_texture().get_image()
				var image_key:="%s-%s"%[selected,cell[2]]
				var bound:=im.get_used_rect()
				if index<2:first_bounds[image_key]=bound
				if index>=8 and bound!=first_bounds[image_key]:
					failures+=1;push_error("Portrait silhouette changed after returning to the original size: "+image_key)
				im.save_png("user://portrait-pair-%02d-%s.png"%[index,"own" if cell[2] else "friend"])
				row.faces.append({"own":cell[2],"selected":p.selected,"complexion":str(p._unit.info.complexion),"face_names":Portrait.face_names(p._unit),"display":str(p.size),"viewport":str(p._vp.size),"exe_rect":str(p.exe_rect),"axis_lengths":str(axes),"quaternion":str(p._model.quaternion),"selection_q":str(p._selection_q),"quaternion_norm":p._model.quaternion.length(),"alpha_bounds":str(bound),"alpha_ratio":float(bound.size.y)/maxi(1,bound.size.x),"ok":ok})
			rows.append(row);print("PORTRAIT_PAIR ",JSON.stringify(row))
	FileAccess.open("user://portrait-pair.json",FileAccess.WRITE).store_string(JSON.stringify(rows,"\t"))
	# Non-humanoid fallback heads use a separate model/camera path.
	var fallback_proto:="wolfgreyf1"
	if not GameData.db.find("monster_prototypes",fallback_proto).is_empty():
		var wolf:=w.spawn_unit({"nid":3,"prototype":fallback_proto,"position":Vector3(1,1,0)})
		wolf.set_process(false);wolf.set_physics_process(false)
		var preview:=Portrait.new();add_child(preview);preview.size=Vector2(128,128);preview.show_unit(wolf)
		await frames(8)
		if preview._cam==null or preview._model.is_physics_interpolated() or preview._cam.is_physics_interpolated():
			failures+=1;push_error("Fallback portrait inherits world interpolation")
		else:print("PASS fallback portrait model and camera use the UI clock")
		preview.queue_free()
	else:
		failures+=1;push_error("Fallback portrait prototype unavailable")
	print("PORTRAIT_RESULT ",failures," failures")
	faces.queue_free();await frames(2);w.queue_free();g.free();s.free();await frames(2);TexUpscale.shutdown();get_tree().quit(1 if failures else 0)
