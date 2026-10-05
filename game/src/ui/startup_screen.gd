class_name StartupScreen
extends CanvasLayer
## The screen between the startup movies and the main menu. the original
## right after ("Start") played config/movie.ini
## [Start], sets the loading movie name to "Progres.bik" and calls
## (frame 0): it opens Movies\Progres.bik, decodes frame 0, blits it
## to the whole window and flips once; closes the movie at once.
## Nothing redraws the window while the databases (database.res), the
## interface and the main menu load, so that still image stays up until the
## menu's first frame replaces it. No progress bar, no text, no fade, no
## minimum time.
## Remake: the frame is decoded with EIBink (no cached conversion needed) and
## drawn letterboxed (aspect kept) on black like the other movies; it is shown
## for two frames before the menu is built, and removed once the menu has drawn.

const MOVIE := "progres"
var _y: ImageTexture


## Shows the screen under `parent`; null when Movies\progres.bik is missing or
## cannot be decoded (the original then only logs "Can't open video file").
static func open(parent: Node) -> StartupScreen:
	if DisplayServer.get_name() == "headless":
		return null
	var img := frame0()
	if img.is_empty():
		return null
	var s := StartupScreen.new()
	s.layer = 105   # over the menu, under MovieSequence (110)
	s._build(img)
	parent.add_child(s)
	return s


## Frame 0 of Movies\progres.bik as [Y, U, V] L8 images, [] if unavailable.
static func frame0() -> Array:
	if GameData.root.is_empty():
		return []
	var src := GameData.root.path_join("movies/%s.bik" % MOVIE)
	if not GameFiles.exists(src):
		return []
	var b := EIBink.new()
	if not b.open(src) or not b.decode_frame(b.frame_data(0)):
		return []
	return planes(b)


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
	mat.set_shader_parameter("u_tex", ImageTexture.create_from_image(planes[1]))
	mat.set_shader_parameter("v_tex", ImageTexture.create_from_image(planes[2]))
	view.texture = _y
	view.material = mat
	bg.add_child(view)


## Waits until the screen has been presented (call before a long build).
func presented() -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw


## Removes the screen once what was built under it has drawn a frame
## (a connection, so freeing it earlier is safe).
func finish() -> void:
	RenderingServer.frame_post_draw.connect(_after_draw, CONNECT_ONE_SHOT)


func _after_draw() -> void:
	queue_free()


func _input(e: InputEvent) -> void:
	# The original loads without reading input; keys must not reach the menu.
	if e is InputEventKey or e is InputEventMouseButton or e is InputEventScreenTouch:
		get_viewport().set_input_as_handled()
