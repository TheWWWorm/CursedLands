extends "ground_mark_receivers.gd"
## Compare animated pigment against the existing CPU-clipped rectangle on
## actual terrain. Run rendered on DX12, Vulkan and Compatibility.

func compare_images(reference: Image, animated: Image, background: Image) -> Dictionary:
	var ink := 0; var different := 0; var error := 0.0
	for y in range(0,reference.get_height(),2):
		for x in range(0,reference.get_width(),2):
			var a:=reference.get_pixel(x,y);var b:=animated.get_pixel(x,y);var c:=background.get_pixel(x,y)
			var delta:=absf(a.r-b.r)+absf(a.g-b.g)+absf(a.b-b.b)
			if absf(a.r-c.r)+absf(a.g-c.g)+absf(a.b-c.b)>.02:ink+=1
			if delta>.03:different+=1
			error+=delta
	return {"ink_pixels":ink,"different_pixels":different,"error_per_ink_pixel":error/maxi(ink,1)}

func run() -> void:
	prepare_scene()
	GameData.options.marks=1
	camera.position=focus+Vector3(0,4,4);camera.look_at(focus)
	marks.add_blood(64,62,.12,.65,2,false)
	check(marks.blood_marks.size()==1,"authored soil accepts a growing blood pool")
	if marks.blood_marks.is_empty():get_tree().quit(1);return
	var mark:=marks.blood_marks[0]
	var original_mesh:=mark.projection.mesh
	var started:=Time.get_ticks_usec()
	for i in 70:marks._update(mark)
	var animation_us:=Time.get_ticks_usec()-started
	check(mark.projection.mesh==original_mesh,"growth and continued rotation reuse the receiving geometry")
	check(is_equal_approx(mark.a,.65),"pool reaches its authored final size")
	marks.hide();await frames(8);var background:=view.get_texture().get_image();marks.show()
	var comparisons:=[]
	for size: float in [.15,.4,.65]:
		for angle: float in [.2,1.3,2.7]:
			mark.a=size;mark.b=size*.7;mark.angle=angle
			marks._place(mark);await frames(4)
			var animated:=view.get_texture().get_image()
			# The non-animated path clips the exact current rectangle on the
			# CPU, providing the previous projection's independent UV reference.
			mark.foot=true;marks._projection.place(mark,true);await frames(4)
			var reference:=view.get_texture().get_image()
			var row:=compare_images(reference,animated,background)
			row["size"]=size;row["angle"]=angle;comparisons.append(row)
			check(row.ink_pixels>10,"blood remains visible at size %s angle %s"%[size,angle])
			check(row.different_pixels<=maxi(8,ceili(row.ink_pixels*.025)) and row.error_per_ink_pixel<.025,
				"animated pigment matches CPU-clipped projection at size %s angle %s"%[size,angle])
			mark.foot=false;marks._projection.place(mark,true)
			if size==.65 and angle==1.3:
				animated.save_png("user://blood-animated.png");reference.save_png("user://blood-cpu-reference.png")
	var before:=mark.projection.mesh
	GameData.options.gfx_soft_ground=1-int(GameData.options.get("gfx_soft_ground",0))
	terrain.apply_gfx();marks._projection.sync([marks.blood_marks])
	check(mark.projection.mesh!=before,"surface changes rebuild the receiving patch")
	mark.life=mark.fade/2;marks._update(mark)
	check(is_equal_approx(mark.projection.material_override.get_shader_parameter("opacity"),mark.decal.modulate.a),"animated pigment preserves authored fading")
	mark.life=1;marks._tick();await frames()
	check(marks.blood_marks.is_empty(),"expired animated pool releases its geometry")
	FileAccess.open("user://ground-mark-animation.json",FileAccess.WRITE).store_string(JSON.stringify({
		"checks":checks,"failures":failures,"animation_70_ticks_ms":animation_us/1000.0,"comparisons":comparisons},"\t"))
	view.free();await frames();TexUpscale.shutdown()
	print("GROUND_MARK_ANIMATION ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
