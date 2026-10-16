extends "arena_expansion_ui.gd"
## Actual pointer purchases/evolution and native battle footprints/blood.

func recruit(family: int) -> int:
	for index in screen.run.shop.size():
		if int(screen.run.shop[index].family) == family:
			await click((screen._shop.get_child(index).get_child(0) as Control).get_global_rect().get_center())
			return int(screen.selected_uid)
	return 0

func _ready() -> void:
	OS.add_logger(errors)
	await frames(24)
	GameData._window_gen += 1
	GameData.options.merge({"gfx_soft_ground":1,"footprints":1,"marks":1,"auto_graphics":0,"confine_mouse":0},true)
	get_tree().root.mode = Window.MODE_WINDOWED
	var lang := "en"
	var dimensions := Vector2i(1280,800)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--arena-resolution="):
			var spec := arg.get_slice("=",1).split(",")
			lang=spec[0];dimensions=Vector2i(int(spec[1]),int(spec[2]))
	get_tree().root.size=dimensions;get_tree().root.position=Vector2i.ZERO
	RemakeText.lang=lang
	await frames(8)
	screen=ArenaPveScreen.new();add_child(screen);await frames(18)
	var tag := "winter-%s-%d" % [lang,dimensions.x]
	bounded(screen._landing_panel,"opening setup")
	await shot(tag+"-landing")
	screen._seed_input.text="8171";screen._begin();screen.run.auto_save=false
	await frames(12)
	check(screen.run.army.is_empty() and screen.battle.team_count(0)==0,"expedition opens without free units")
	check(screen.run.gold==16 and screen.run.shop.size()==6,"opening shop has all six affordable families")
	await shot(tag+"-empty")
	var wolf := await recruit(2)
	check(wolf>0 and not screen.run.unit(wolf).deployed,"click buys wolf into reserves")
	await click(screen.field.screen_point(Vector2(27,29)))
	check(screen.run.unit(wolf).deployed and screen.selected_uid==0,"placement releases bought creature")
	var boar := await recruit(0)
	await click(screen.field.screen_point(Vector2(27,35)))
	check(boar>0 and screen.run.unit(boar).deployed,"second opening recruit can be chosen and placed")
	# Two visible purchases from the real shop finish a wave-one evolution.
	screen.run.shop[0]={"family":2,"rank":0,"locked":false}
	screen.run.shop[1]={"family":2,"rank":0,"locked":false}
	screen._refresh();await frames()
	await recruit(2);await recruit(2);await get_tree().create_timer(0.4).timeout
	check(screen.run.unit(wolf).prototype=="wolfgreyf3" and screen.run.wave==1,"wave-one evolution keeps field identity")
	check(screen._evolution_notice.visible and screen._evolution_notice.current.to=="wolfgreyf3","evolution shows before/after feedback")
	check(screen.field.evolution_pulses.has(wolf),"upgraded field creature is highlighted")
	bounded(screen._evolution_notice,"evolution notice")
	for preview in screen._evolution_notice.find_children("*","WikiPreview",true,false):preview_fits(preview,"evolution")
	await shot(tag+"-evolution")
	await click(point(body(boar)))
	check(screen.selected_uid==boar,"feedback leaves battlefield interaction available")
	await click(screen.field.screen_point(Vector2(27,38)))
	await get_tree().create_timer(3.5).timeout
	check(not screen._evolution_notice.visible,"feedback closes on its own")
	# Later-region models are inspected at both ranks, including wings/weapons.
	screen.run.wave=19;screen.run.gold=80;screen.run.boons.assign(["scout"])
	for rank in 2:
		screen.run.shop.clear()
		for family in range(6,12):screen.run.shop.append({"family":family,"rank":rank,"locked":false})
		screen._refresh();await frames(24)
		for box in screen._shop.get_children():preview_fits(box.get_child(0).preview,"later recruit")
		await shot(tag+"-roster-%d"%rank)
	screen._show_recruitment();await frames()
	bounded(screen._modal_panel,"recruitment progression")
	await shot(tag+"-market")
	screen._close_modal()
	# A normal rendered fight drives foot contacts, terrain compaction and hit
	# splatter. No synthetic blood/footprint stamps stand in for these events.
	screen.run.begin(8171);screen.run.auto_save=false
	Fixture.buy_company(screen.run,0)
	screen.run.wave=4;screen.run._roll_shop(false)
	screen.run.army[0].rank=1;screen.run.army[0].prototype="boarredf3"
	screen.run.army[1].rank=1;screen.run.army[1].prototype="orcmalef3"
	screen.run.army[2].rank=1;screen.run.army[2].prototype="goblina3"
	screen.run.arrange();screen._refresh();await frames(12)
	var terrain := screen.battle.world.terrain
	check(terrain is ArenaWinterTerrain and terrain.resource_prefix=="zone11","original Ingos winter terrain")
	check(terrain._land_mat.shader.code.contains("arena_paving") and terrain.get_node_or_null("CourtyardPaving")==null,"artwork shares the native deformed ground receiver")
	check(terrain.ground_type(27,32)==9,"battlefield uses native snow surface")
	var marks := screen.battle.world.ground_marks
	check(is_instance_valid(marks),"footprint owner exists before the first hit")
	check(is_instance_valid(terrain.details.soft_ground),"snow deformation enabled")
	screen._fight()
	for seconds in 45:
		await get_tree().create_timer(1.0).timeout
		if seconds==5:await shot(tag+"-combat")
		if screen.battle.phase==ArenaMatch.Phase.FINISHED:break
	check(screen.battle.phase==ArenaMatch.Phase.FINISHED,"native winter encounter finishes")
	await get_tree().create_timer(2.0).timeout
	check(not marks.foot_marks.is_empty(),"native walking animation leaves footprints")
	check(not marks.blood_marks.is_empty(),"native hits/deaths leave blood")
	check(marks.blood_marks.any(func(m):return not m.splash),"spectator battle includes corpse pools")
	var soft := terrain.details.soft_ground
	check(not soft.sectors.is_empty(),"walking creatures leave deformed snow trails")
	print("WINTER_MARKS footprints=",marks.foot_marks.size()," blood=",marks.blood_marks.size()," track_sectors=",soft.sectors.size())
	screen._outcome.hide();screen._outcome_shade.hide()
	await shot(tag+"-aftermath")
	# Compare settled pixels with and without blood and native snow geometry.
	marks.set_process(false)
	await frames()
	var before := get_viewport().get_texture().get_image()
	for mark in marks.blood_marks:mark.decal.hide()
	await frames()
	var blood_hidden := get_viewport().get_texture().get_image()
	check(changed_pixels(before,blood_hidden)>15,"blood changes visible battlefield pixels")
	for mark in marks.blood_marks:mark.decal.show()
	await frames()
	before=get_viewport().get_texture().get_image()
	soft.clear();await frames(12)
	check(changed_pixels(before,get_viewport().get_texture().get_image())>30,"snow trails change visible battlefield pixels")
	# A quality change must keep the courtyard material and mark receivers.
	terrain.apply_gfx();await frames()
	check(terrain._land_mat.shader.code.contains("arena_paving"),"graphics refresh preserves winter art")
	screen.queue_free();await frames(8)
	check(errors.messages.is_empty(),"no scene, shader or script errors: "+JSON.stringify(errors.messages))
	print("ARENA_WINTER_UI ",checks," checks; failures=",JSON.stringify(failures))
	OS.remove_logger(errors)
	get_tree().quit(0 if failures.is_empty() else 1)

func changed_pixels(a: Image,b: Image) -> int:
	var count := 0
	for y in range(a.get_height()/4,a.get_height()*4/5,2):
		for x in range(a.get_width()/8,a.get_width()*7/8,2):
			var p := a.get_pixel(x,y);var q := b.get_pixel(x,y)
			if absf(p.r-q.r)+absf(p.g-q.g)+absf(p.b-q.b)>0.07:count+=1
	return count
