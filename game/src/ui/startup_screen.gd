class_name StartupScreen
extends CanvasLayer
## The launch progress picture. Both campaigns contain twelve authored
## lighting stages. Present them in order before handing input to the menu.

const MOVIE := "progres"
var _y: ImageTexture
var _u: ImageTexture
var _v: ImageTexture
var _bink: EIBink
var _decoded := 0
var _finishing := false


## Shows the screen under `parent`; null when Movies\progres.bik is missing or
## cannot be decoded (the original then only logs "Can't open video file").
static func open(parent: Node) -> StartupScreen:
	if DisplayServer.get_name() == "headless":
		return null
	var b := _open_movie()
	if b == null:
		return null
	var s := StartupScreen.new()
	s.layer = 105   # over the menu, under MovieSequence (110)
	s._bink = b
	s._build(planes(b))
	parent.add_child(s)
	return s


## Frame 0 of Movies\progres.bik as [Y, U, V] L8 images, [] if unavailable.
static func frame0() -> Array:
	var b := _open_movie()
	return planes(b) if b else []

static func _open_movie() -> EIBink:
	if GameData.root.is_empty():
		return null
	var src := GameData.root.path_join("movies/%s.bik" % MOVIE)
	if not GameFiles.exists(src):
		return null
	var b := EIBink.new()
	if not b.open(src) or not b.decode_frame(b.frame_data(0)):
		return null
	return b


## The frame `b` decoded last as [Y, U, V] L8 images (also LoadingScreen).
static func planes(b: EIBink) -> Array[Image]:
	var yuv := b.yuv_image()
	var w := b.width
	var h := b.height
	var cw := (w + 1) >> 1
	var ch := (h + 1) >> 1
	return [yuv.get_region(Rect2i(0, 0, w, h)), yuv.get_region(Rect2i(0, h, cw, ch)),
		yuv.get_region(Rect2i(cw, h, cw, ch))]


func _build(planes: Array) -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP   # the menu below waits
	add_child(bg)
	var view := TextureRect.new()
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	view.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = Shader.new()
	mat.shader.code = MoviePlayer.SHADER
	_y = ImageTexture.create_from_image(planes[0])
	_u = ImageTexture.create_from_image(planes[1])
	_v = ImageTexture.create_from_image(planes[2])
	mat.set_shader_parameter("u_tex", _u)
	mat.set_shader_parameter("v_tex", _v)
	view.texture = _y
	view.material = mat
	bg.add_child(view)


## Waits until the screen has been presented (call before a long build).
func presented() -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw


## Await each stage's presentation: a quick menu build must not collapse
## the entire lighting sequence into a single final frame.
func finish() -> void:
	if _finishing: return
	_finishing = true
	if _bink:
		for frame in range(1, _bink.frame_count):
			if not _bink.decode_frame(_bink.frame_data(frame)): break
			var images := planes(_bink)
			_y.update(images[0]); _u.update(images[1]); _v.update(images[2])
			_decoded = frame
			await RenderingServer.frame_post_draw
			await get_tree().create_timer(1.0 / 25.0, true).timeout
	await RenderingServer.frame_post_draw
	queue_free()


func _input(e: InputEvent) -> void:
	# The original loads without reading input; keys must not reach the menu.
	if e is InputEventKey or e is InputEventMouseButton or e is InputEventScreenTouch:
		get_viewport().set_input_as_handled()
