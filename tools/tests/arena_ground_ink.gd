extends "arena_expansion_ui.gd"
## Rendered coverage for marks beyond Mobile's eight-decal-per-mesh limit.
## Also run with --rendering-method gl_compatibility for browser-style materials.
func _ready() -> void:
	OS.add_logger(errors)
	await frames(12)
	screen = ArenaPveScreen.new()
	add_child(screen)
	await frames(12)
	screen._begin()
	screen.run.auto_save = false
	var terrain := screen.battle.world.terrain as ArenaWinterTerrain
	var marks := screen.battle.world.ground_marks
	check(is_instance_valid(terrain._ink), "limited-decal renderer uses the snow ink surface")
	# Actual authored blood textures, opacity and lifetime; only their positions
	# are fixed for a stable comparison that exceeds the eight-decal limit.
	for i in 20:
		marks.add_blood(29 + (i % 5) * 1.5, 28 + (i / 5) * 1.5, 0.4, 0.4, 2, false)
	await frames(24)
	marks.set_process(false)
	check(marks.blood_marks.size() == 20, "all twenty native marks survive composition")
	check(marks.blood_marks.all(func(m):return m.decal.cull_mask == 0), "marks leave decal slots available for contact shadows")
	await RenderingServer.frame_post_draw
	var visible := get_viewport().get_texture().get_image()
	visible.save_png("user://arena-ground-ink-visible.png")
	for m in marks.blood_marks:m.decal.hide()
	await frames(12)
	await RenderingServer.frame_post_draw
	var hidden := get_viewport().get_texture().get_image()
	var changed := 0
	for y in range(visible.get_height()/4, visible.get_height()*4/5, 2):
		for x in range(visible.get_width()/8, visible.get_width()*7/8, 2):
			var a := visible.get_pixel(x,y)
			var b := hidden.get_pixel(x,y)
			if absf(a.r-b.r)+absf(a.g-b.g)+absf(a.b-b.b)>0.07:changed+=1
	check(changed > 50, "native blood visibly changes the snow")
	check(errors.messages.is_empty(), "no script or shader errors")
	print("ARENA_GROUND_INK ",checks," checks; pixels=",changed," failures=",JSON.stringify(failures))
	OS.remove_logger(errors)
	get_tree().quit(0 if failures.is_empty() else 1)
