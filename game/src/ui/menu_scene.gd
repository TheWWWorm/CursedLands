class_name MenuScene
extends Node3D
## The original main menu: the "zonemainmenunew" island with the carved
## signpost (menus.res "unmoco2"), whose six boards are the menu buttons.
## Hovering a board plays its animation; clicking emits `pressed`.

signal pressed(action: String)

## Board part -> menu action.
const BOARDS := {"button01_new_game": "new", "button02_load_game": "load", "button03_multiplayer": "multiplayer",
	"button04_options": "options", "button06_credits": "credits", "button08_exit": "exit"}

var camera: Camera3D
var _column: Node3D
var _player: AnimationPlayer
var _boards := {}   # part -> Node3D
var _hover := ""
var _mats := {}     # part -> Array[StandardMaterial3D]
var _sky: ShaderMaterial
var _sky_spin := 0.0
var _env: Environment
var _sun: DirectionalLight3D
var _lights: EILights
## World time of the menu island (hours). loads the island and
## sets the world clock to the computer's local time (GetLocalTime: wHour +
## wMinute / 60); tools may override it with set_hour.
var hour := 12.0

## Night rain (menu init, per-frame): is a
## random bit (half the visits). At init, hour < 7 and the bit start the rain
## ((1, 20.0) → the world's precipitation = 1, fade 20
## ticks, the zone weather's client state); with the bit, the whole hour
## turning 0 starts it and turning 7 stops it. While not 7 < hour < 21
## with the bit, hour < 6 and the game window active (
## bit 0 = flags +4 of the display object, set / cleared by the main
## loop from WM_ACTIVATE), at most every 100 ms
## one random number in 41 (% 0x29 == 4) strikes a lightning
## (top x = r·20, y = r·60, z 17; ground x ± 2, y ± 2, z 1).
## Drawn and heard by the game's own pieces: Weather (client state, the rain
## loop), FxRainSnow (reads `sound.weather`), ParticleFx script lights and
## bolts. **Approx.**: the 3D listener is the menu camera's eye (the original's
## listener in the menu is not traced).
class MenuSound extends RefCounted:
	var weather: Weather
	var _ticks := 0
	var _tick_acc := 0.0

var sound := MenuSound.new()
var rain_bit := false
var _mixer: SoundMixer
var _fx: ParticleFx
var _last_hour := -1
var _strike_ms := 0


func _process(dt: float) -> void:
	# The dome turns by game ticks × 0.000333 rad; the tick
	# counter starts near 0 when the menu opens.
	_sky_spin += dt * EISky.SPIN_PER_SECOND
	EISky.set_spin(_sky, _sky_spin)
	_weather_tick(dt)
	# The clock runs at the game's rate: sets it
	# as the game start does.
	set_hour(fmod(hour + dt / CampaignState.HOUR_SECONDS, 24.0))


func _setup_weather() -> void:
	_mixer = SoundMixer.new()
	add_child(_mixer)
	sound.weather = Weather.new(_mixer, null)
	add_child(FxRainSnow.new(self))
	_fx = ParticleFx.new()
	_fx.name = "ParticleFx"
	add_child(_fx)
	rain_bit = randi() & 1 == 1
	_last_hour = int(hour)
	if hour < 7.0 and rain_bit:
		_rain(1)


## (w, 20.0): precipitation w with a 20-tick fade.
func _rain(w: int) -> void:
	if sound.weather:
		sound.weather.on_event({"w": w, "fade": 20.0}, sound._ticks + sound._tick_acc / GameSound.TICK)


func _weather_tick(dt: float) -> void:
	if sound.weather == null:
		return
	sound._tick_acc += dt
	while sound._tick_acc >= GameSound.TICK:
		sound._tick_acc -= GameSound.TICK
		sound._ticks += 1
	if camera:
		var e := camera.global_position
		var b := camera.global_transform.basis
		_mixer.set_listener(Vector3(e.x, -e.z, e.y), Vector2(-b.z.x, b.z.z), Vector2(b.x.x, -b.x.z))
	sound.weather.tick(sound._ticks + sound._tick_acc / GameSound.TICK)
	var h := int(hour)
	if h != _last_hour and rain_bit:
		if h == 0:
			_rain(1)
		elif h == 7:
			_rain(0)
	_last_hour = h
	var day := hour > 7.0 and hour < 21.0
	if day or not rain_bit or h >= 6 or not get_window().has_focus():
		return
	var now := Time.get_ticks_msec()
	if now <= _strike_ms:
		return
	_strike_ms = now + 100
	if randi() % 41 == 4:
		var x := randf() * 20.0
		var y := randf() * 60.0
		_strike(Vector3(x, y, 17.0), Vector3(x + randf() * 4.0 - 2.0, y + randf() * 4.0 - 2.0, 1.0))


## (top, ground), as Weather._strike: one time in four only
## thunder ("nature\thunder\1..4", 60 / 150, at the top), otherwise a white
## point light (id 1, radius 80) at the middle, "nature\lightning\1..3" at
## the top and two bolts (ids 1, 2, param −7) one script tick apart.
func _strike(top: Vector3, ground: Vector3) -> void:
	if randi() & 3 == 0:
		_mixer.play3d("nature\\thunder\\%d.wav" % (randi() % 4 + 1), 0, top, 60.0, 150.0)
		return
	var mid := (top + ground) * 0.5
	_fx.script_cmd("CreatePointLight", [1, mid.x, mid.y, mid.z, 80.0, 255, 255, 255])
	_mixer.play3d("nature\\lightning\\%d.wav" % (randi() % 3 + 1), 0, top, 60.0, 150.0)
	var bolt := [top.x, top.y, top.z, ground.x, ground.y, ground.z, -7]
	_fx.script_cmd("CreateLightning", [1] + bolt)
	await get_tree().create_timer(ScriptVM.SLEEP_UNIT).timeout
	if not is_instance_valid(_fx):
		return
	_fx.script_cmd("DeleteLightning", [1])
	await get_tree().create_timer(ScriptVM.SLEEP_UNIT).timeout
	if not is_instance_valid(_fx):
		return
	_fx.script_cmd("CreateLightning", [2] + bolt)
	await get_tree().create_timer(ScriptVM.SLEEP_UNIT).timeout
	if not is_instance_valid(_fx):
		return
	_fx.script_cmd("DeleteLightning", [2])
	_fx.script_cmd("DeletePointLight", [1])


## Lights the island for `h` as the daylight update (LightsGipat).
func set_hour(h: float) -> void:
	hour = h
	if _env == null:
		return
	var ld := EISky.light_dir_ei(h)
	var gd := EISpace.vec(ld).normalized()
	_sun.basis = Basis.looking_at(gd, Vector3.FORWARD if absf(gd.y) > 0.99 else Vector3.UP)
	Gfx.update_original(_env, _sun, _lights, h, false)
	EISky.update(_sky, _lights, h, false, Gfx.on("gfx_sky"))


static func create() -> MenuScene:
	var map := EIMapScene.load_map("zonemainmenunew")
	if map == null:
		return null
	var s := MenuScene.new()
	s.add_child(map)
	for n: Node3D in map.object_nodes:
		var info: Dictionary = n.get_meta("ei", {})
		if String(info.get("template", "")) == "unmoco2":
			s._column = n
		elif n is EIUnitModel:
			(n as EIUnitModel).act("idle")
	if s._column == null:
		return null
	s._setup_column()
	s._setup_view(map)
	return s


func _setup_column() -> void:
	var labels := EIFigure.material_for("mainmenu00labels")
	for mi: MeshInstance3D in _column.find_children("*", "MeshInstance3D", true, false):
		var part := String(mi.get_parent().name)
		if part.begins_with("but") and not part.begins_with("button"):
			mi.material_override = labels
	for part: String in BOARDS:
		var n := _column.find_child(part, true, false) as Node3D
		if n:
			_boards[part] = n
			var mats := []
			for mi: MeshInstance3D in n.find_children("*", "MeshInstance3D", true, false):
				var m: Material = mi.material_override.duplicate()
				mi.material_override = m
				mats.append(m)
			_mats[part] = mats
	var paths := {}
	for n: Node in _column.find_children("*", "Node3D", true, false):
		if not n is MeshInstance3D:
			paths[String(n.name)] = _column.get_path_to(n)
	_player = AnimationPlayer.new()
	_column.add_child(_player)
	_player.root_node = NodePath("..")
	_player.add_animation_library("ei", EIAnim.library("unmoco2", paths, "column"))
	if _player.has_animation("ei/cidle"):
		_player.play("ei/cidle")


func _setup_view(map: EIMapScene) -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	# The original sky dome (EISky). keeps the default allod
	# "gipat" unless a zone record names another, so the menu uses LightsGipat;
	# the hour is the local time.
	_sky = EISky.material(false)
	_lights = EILights.load_for("Gipat", false)
	# The menu screen sets BorderFogDistance to 6 m (
	# (6.0)); the island is only 64 m across.
	Gfx.set_border(map.terrain.size_ei(), 6.0)   # the original menu value, not the option
	env.sky = Sky.new()
	env.sky.sky_material = _sky
	env.sky.process_mode = Sky.PROCESS_MODE_REALTIME
	Gfx.setup_original_env(env)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	_env = env
	_sun = DirectionalLight3D.new()
	_sun.shadow_enabled = true
	Gfx.setup_sun_casters(_sun)
	add_child(_sun)
	var t := Time.get_datetime_dict_from_system()
	set_hour(float(t.hour) + float(t.minute) / 60.0)
	_setup_weather()
	camera = Camera3D.new()
	camera.fov = CameraRig.ORIGINAL_FOV   # the renderer's one projection (CameraRig)
	camera.near = minf(camera.near, Gfx.NEAR_CLIP)
	camera.far = Gfx.far_clip()
	add_child(camera)
	camera.transform = _cam_pose("camera/mainmenu.cam")
	if camera.transform == Transform3D.IDENTITY:
		# No camera file: stand behind the signpost looking at the ogre's camp.
		var info: Dictionary = _column.get_meta("ei", {})
		var cp: Vector3 = info.get("position", Vector3.ZERO)
		var col := Vector2(cp.x, cp.y)
		var view := Vector2(11.3, 30.2)
		var eye2 := col + (col - view).normalized() * 4.3
		var ground := map.terrain.height_at(col.x, col.y)
		var eye := EISpace.pos(eye2.x, eye2.y, ground + 2.4)
		camera.transform = Transform3D(Basis.looking_at(EISpace.pos(view.x, view.y, ground + 1.6) - eye), eye)


## First keyframe of an original .cam file: 36-byte records of
## [time f32, u32, pos x y z f32, quat w x y z f32] (EI coordinates). The camera
## looks along its local +z with -y up and +x to the right.
func _cam_pose(rel: String) -> Transform3D:
	var b := GameFiles.read(GameData.root.path_join(rel), 0, 36)
	if b.size() < 36:
		return Transform3D.IDENTITY
	var q := EISpace.quat(b.decode_float(20), b.decode_float(24), b.decode_float(28), b.decode_float(32))
	var right := q * EISpace.vec(Vector3(1, 0, 0))
	var up := q * EISpace.vec(Vector3(0, -1, 0))
	var back := q * EISpace.vec(Vector3(0, 0, -1))
	return Transform3D(Basis(right, up, back).orthonormalized(),
		EISpace.pos(b.decode_float(8), b.decode_float(12), b.decode_float(16)))


## The boards' hit rectangles (the original reads menus.reg
## [MainMenu] in this order; the menu init adds them
## as click areas, so index is this order) and the
## animation plays for each index (uspecial 1, 3, 5, 7, 11, 9).
const REG := [["NewGame", "button01_new_game", 1], ["LoadGame", "button02_load_game", 3],
	["ExitGame", "button08_exit", 5], ["Options", "button04_options", 7],
	["Credits", "button06_credits", 11], ["Multiplayer", "button03_multiplayer", 9]]
static var _reg_rects: Array = []


## menus.reg [MainMenu] rectangles (800×600, left / top / right / bottom),
## in REG order; empty when the file is missing.
static func reg_rects() -> Array:
	if _reg_rects.is_empty() and GameData.menus and GameData.menus.has("menus.reg"):
		var mm: Dictionary = EIRegFile.parse(GameData.menus.read("menus.reg")).get("MainMenu", {})
		for e: Array in REG:
			var v: Array = mm.get(e[0], [])
			_reg_rects.append(Rect2(v[0], v[1], v[2] - v[0], v[3] - v[1]) if v.size() == 4 else Rect2())
	return _reg_rects


## A window point in the original's 800×600 menu space. The original drew the menu
## 4:3 with the rectangles stretched per axis; the remake's view keeps the
## height (CameraRig.ORIGINAL_FOV vertical), so x is taken from the centre at
## the height's scale — the same as stretching at 4:3; at 16:9 / 16:10 the
## view widens (remake rule) and the rects stay on the boards.
func to_800(p: Vector2) -> Vector2:
	var vs := get_viewport().get_visible_rect().size
	var k := 600.0 / maxf(vs.y, 1.0)
	return Vector2(400.0 + (p.x - vs.x * 0.5) * k, p.y * k)


## Board under a screen point, "" if none: the first menus.reg rectangle
## (PtInRect) holding it.
func board_at(p: Vector2) -> String:
	var q := to_800(p)
	var rr := reg_rects()
	for i in rr.size():
		var r: Rect2 = rr[i]
		if q.x >= r.position.x and q.y >= r.position.y and q.x < r.end.x and q.y < r.end.y:
			return REG[i][1]
	return ""


## A board's hit rectangle in window pixels (tools / tests).
func board_rect(part: String) -> Rect2:
	var rr := reg_rects()
	for i in rr.size():
		if REG[i][1] == part:
			var vs := get_viewport().get_visible_rect().size
			var k := vs.y / 600.0
			var r: Rect2 = rr[i]
			return Rect2(Vector2(vs.x * 0.5 + (r.position.x - 400.0) * k, r.position.y * k), r.size * k)
	return Rect2()


func _screen_rect(n: Node3D) -> Rect2:
	var r := Rect2()
	var first := true
	for mi: MeshInstance3D in n.find_children("*", "MeshInstance3D", false, false):
		var b: AABB = mi.global_transform * mi.get_aabb()
		for i in 8:
			var c := b.get_endpoint(i)
			if camera.is_position_behind(c):
				continue
			var sp := camera.unproject_position(c)
			r = Rect2(sp, Vector2.ZERO) if first else r.expand(sp)
			first = false
	return r


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion:
		_set_hover(board_at(e.position))
	elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		var b := board_at(e.position)
		if b:
			if BOARDS[b] != "exit":   # ok.wav (Exit plays its movie)
				_ui_sound("buttons\\menu\\ok.wav")
			pressed.emit(BOARDS[b])


## a 2D UI sound on the SFX bus.
func _ui_sound(path: String) -> void:
	var p := AudioStreamPlayer.new()
	p.bus = "SFX"
	p.stream = EIAudio.sfx(path)
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)


func _set_hover(part: String) -> void:
	if part == _hover:
		return
	_hover = part
	_ui_sound("buttons\\menu\\stone.wav")   # the hovered board changed
	if part:
		var n := 1
		for e: Array in REG:
			if e[1] == part:
				n = e[2]
		var anim := "ei/uspecial%02d" % n
		if _player.has_animation(anim):
			_player.play(anim)
			_player.queue("ei/cidle")
