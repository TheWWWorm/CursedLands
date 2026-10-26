extends Node
const Fixture = preload("arena_fixture.gd")
## Rendered regression for real viewport scaling, body picking and combat feedback.
## Run with an X/Wayland display at least as large as the requested resolution.
## Saves per-state PNGs; each language/resolution runs in a fresh process.

var checks := 0
var failures: Array[String] = []
var screen: ArenaPveScreen
var hold_preparation := true

func _process(_dt: float) -> void:
	# Long visual inspection fixtures own their clock; the flow fixture releases it.
	if hold_preparation and is_instance_valid(screen) and screen.run.stage == "prepare":
		screen.run.preparation_left = ArenaRules.PREPARATION_SECONDS

class Errors extends Logger:
	var messages: Array[String] = []
	func _log_error(fn: String, file: String, line: int, code: String, why: String, _notify: bool, kind: int, _trace: Array[ScriptBacktrace]) -> void:
		# Stock Godot 4.7 reports TexUpscaleTexture's push constants as
		# unexpected on the main device, although its output matches the
		# local-device upscale exactly; the project's engine does not.
		if fn == "compute_list_set_push_constant" and Engine.get_version_info().build == "official":
			return
		if kind != ERROR_TYPE_WARNING: messages.append("%s %s (%s:%d %s)" % [code, why, file, line, fn])
var errors := Errors.new()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		printerr("FAIL ", label)

func frames(count := 6) -> void:
	for i in count: await get_tree().process_frame

func move(at: Vector2) -> void:
	Input.warp_mouse(at)
	var motion := InputEventMouseMotion.new()
	motion.position = at
	Input.parse_input_event(motion)
	await frames(2)

func click(at: Vector2) -> void:
	await move(at)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = at
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		Input.parse_input_event(event)
		await frames(2)

func shot(label: String) -> void:
	await frames()
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://expansion-" + label + ".png")
	print("CAPTURE ", label, " ", get_viewport().get_visible_rect().size)

func bounded(control: Control, label: String) -> void:
	var rect := control.get_global_rect()
	check(Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size).grow(1).encloses(rect), label + " is inside the viewport")

func body(uid: int) -> GameUnit:
	for unit: GameUnit in screen.battle.world.unit_rows():
		if unit.get_meta("arena_placement", {}).get("run_uid", 0) == uid: return unit
	return null

func point(unit: GameUnit) -> Vector2:
	var rects := unit.screen_rects(screen.field.camera)
	return Rect2(rects[0]).get_center() if not rects.is_empty() else Vector2.ZERO

func _ready() -> void:
	OS.add_logger(errors)
	await frames(24)
	GameData._window_gen += 1
	get_tree().root.mode = Window.MODE_WINDOWED
	var lang := "en"
	var dimensions := Vector2i(1280,800)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--arena-resolution="):
			var spec := arg.get_slice("=",1).split(",")
			lang=spec[0];dimensions=Vector2i(int(spec[1]),int(spec[2]))
	get_tree().root.size=dimensions
	get_tree().root.position=Vector2i.ZERO
	RemakeText.lang=lang
	await frames(8)
	screen=ArenaPveScreen.new();add_child(screen)
	await frames(15)
	var tag := "%s-%d" % [lang,dimensions.x]
	await shot(tag+"-landing")
	screen._seed_input.text="6519";screen._begin();Fixture.buy_company(screen.run, 1);screen.run.auto_save=false
	await frames(12)
	var uid := int(screen.run.army[2].uid)
	var bat := body(uid)
	await move(point(bat));await get_tree().create_timer(0.45).timeout
	check(screen._rail.visible and screen._inspected_unit==bat,"hover body opens side details")
	check(screen._live_health.text == ArenaUnitInfo.summary(String(bat.info.prototype), bat, -1, 0, screen._field_army()),"hover includes attack rating")
	check(screen._live_health.text.contains(RemakeText.t("Weaknesses: none")) or screen._live_health.text.contains(RemakeText.t("Weaknesses: %s").get_slice("%",0)),"hover includes native weaknesses")
	bounded(screen._rail,"hover rail")
	await shot(tag+"-hover")
	await move(Vector2(400,400)*screen._ui_scale);await get_tree().create_timer(0.35).timeout
	check(not screen._rail.visible,"details close after leaving a creature")
	await click(point(body(uid)))
	check(screen.selected_uid==uid and screen._sell_target.visible,"select shows sell target")
	await click((screen._army_row.get_child(0) as Button).get_global_rect().get_center())
	check(not screen.run.unit(uid).deployed and screen.selected_uid==0,"empty reserve slot withdraws and releases creature")
	await click((screen._army_row.get_child(0) as Button).get_global_rect().get_center())
	await click(screen.field.screen_point(Vector2(24,39)))
	check(screen.run.unit(uid).deployed and screen.selected_uid==0 and screen.field.ghost_id.is_empty(),"successful placement releases creature and ghost")
	# No second move after the first placement.
	var placed: Array=screen.run.unit(uid).point.duplicate()
	await click(screen.field.screen_point(Vector2(27,39)))
	check(screen.run.unit(uid).point==placed,"second ground click leaves placed creature alone")
	await click(point(body(uid)))
	await shot(tag+"-selected")
	var gold:=screen.run.gold
	var sale:=screen.run.sale_value(screen.run.unit(uid))
	await click(screen._sell_target.get_global_rect().get_center())
	check(screen.run.unit(uid).is_empty() and screen.run.gold==gold+sale,"click sell target sells selected creature")
	check(screen.selected_uid==0 and not screen._sell_target.visible,"sell releases selection")
	screen.run.undo();await frames()
	check(not screen.run.unit(uid).is_empty(),"sale can be undone")
	# The lock and surrounding offers must stay in exactly the same positions.
	var lock:=screen._shop.get_child(0).get_child(1) as Button
	var lock_rect:=lock.get_global_rect()
	var shelf_rect:=screen._shop.get_global_rect()
	await move(lock_rect.get_center());await frames()
	check(lock.get_global_rect()==lock_rect and screen._shop.get_global_rect()==shelf_rect,"lock hover never moves shelf or target")
	await click(lock_rect.get_center());await frames()
	lock=screen._shop.get_child(0).get_child(1)
	check(lock.get_global_rect()==lock_rect,"pressed lock preserves geometry")
	# Training is a real spend, can be undone, and exposes its effect before buying.
	screen.run.gold=25;screen._refresh();await frames()
	bounded(screen._train_button,"direct training")
	await shot(tag+"-training")
	var previous_xp := screen.run.experience()
	await click(screen._train_button.get_global_rect().get_center())
	check(screen.run.experience()==previous_xp+5 and screen.run.gold==20,"training control buys five XP")
	screen.run.undo();await frames()
	check(screen.run.capacity()==3 and screen.run.gold==25,"training undo restores capacity and gold")
	# Every evolution form fits, including held weapons and animated wings.
	screen.run.boons.assign(["scout"])
	for rank in 3:
		screen.run.shop.clear()
		for family in 6: screen.run.shop.append({"family":family,"rank":mini(rank,ArenaRules.FAMILIES[family].forms.size()-1),"locked":false})
		screen.run.gold=100;screen._refresh();await frames(16)
		for sample in 3:
			await get_tree().create_timer(0.3).timeout
			for box in screen._shop.get_children():
				var card: ArenaCreatureCard=box.get_child(0)
				preview_fits(card.preview,card.prototype)
				check(card.get_children().any(func(c): return c is ArenaStars),"shop star rank visible")
		if rank==2: await shot(tag+"-veterans")
	# Long native names, six offers and nine narrow reserve previews together.
	screen.run.boons.assign(["reserve","scout"])
	screen.run.shop.clear()
	for family in 6:
		screen.run.shop.append({"family":family,"rank":mini(2,ArenaRules.FAMILIES[family].forms.size()-1),"locked":false})
	for i in 9: screen.run._recruit(1 if i%2==0 else 3,2,27)
	screen._refresh();await frames(20)
	for button in screen._army_row.get_children():
		for child in button.get_children():
			if child is WikiPreview: preview_fits(child,"reserve orc")
	for box in screen._shop.get_children(): preview_fits(box.get_child(0).preview,"expanded shop")
	bounded(screen._bench_panel,"expanded reserves")
	# Reserve slots now fit the shelf; all eleven destinations stay reachable.
	check(screen._army_row.size.x <= screen._bench_scroll.size.x + 1,"expanded reserves fit the responsive shelf")
	for slot: Control in screen._army_row.get_children():
		check(screen._bench_scroll.get_global_rect().grow(1).encloses(slot.get_global_rect()), "every reserve destination is visible")
	bounded(screen._shop_panel,"expanded shop")
	await move((screen._shop.get_child(1).get_child(0) as Control).get_global_rect().get_center())
	await get_tree().create_timer(0.4).timeout
	bounded(screen._rail,"localized orc details")
	await shot(tag+"-expanded")
	# Final native hit resolves the encounter, then the battlefield gets a beat.
	Fixture.begin(screen.run, 6519,1);await frames()
	screen._fight();screen.battle.set_process(false)
	# The real start waits for formation arrivals before combat begins.
	for frame in 120:
		if screen.battle.phase == ArenaMatch.Phase.FIGHT: break
		await frames(1)
	check(screen.battle.phase == ArenaMatch.Phase.FIGHT, "formation arrival reaches real combat")
	for tick in 1800:
		if screen.battle.phase != ArenaMatch.Phase.FIGHT:break
		screen.battle.simulate_tick()
	check(screen.battle.winner==0 and screen.battle.settle_remaining>0,"real victory begins settle interval")
	check(not screen._outcome.visible,"result does not cover the final hit")
	var duration:=screen.battle.world.time
	var result:Dictionary=screen.run.last_result.duplicate(true)
	screen.battle.set_process(true)
	await get_tree().create_timer(0.65).timeout
	check(not screen._outcome.visible,"result remains hidden during finishing animation")
	await get_tree().create_timer(1.1).timeout
	check(screen._round_banner.visible and screen._round_banner.heading.text == RemakeText.t("Victory") and not screen._outcome.visible,"victory notice remains readable without covering the board")
	check(screen.battle.world.time==duration and screen.run.last_result==result,"settling cannot alter combat or pay income again")
	bounded(screen._round_banner,"victory notice")
	await shot(tag+"-victory")
	screen.queue_free();await frames()
	OS.remove_logger(errors)
	check(errors.messages.is_empty(),"no runtime errors: "+str(errors.messages))
	print("ARENA_EXPANSION_UI ",tag," ",checks," checks; failures=",JSON.stringify(failures))
	get_tree().quit(0 if failures.is_empty() else 1)


func preview_fits(preview:WikiPreview,label:String)->void:
	check(preview.fit_slot and preview._creature_fitted,label+" is fitted")
	var doll:=preview.creature
	var box:=Rect2(Vector2.ZERO,Vector2(doll._vp.size)).grow(2)
	var fits:=true
	for mesh:MeshInstance3D in doll._model.find_children("*","MeshInstance3D",true,false):
		if not doll._shown_part(mesh):continue
		var bounds:=EIUnitModel.preview_bounds(mesh)
		for i in 8:
			var corner:=mesh.global_transform*bounds.get_endpoint(i)
			if not box.has_point(doll._cam.unproject_position(corner)):fits=false
	check(fits,label+" animated mesh and weapon stay inside preview")
