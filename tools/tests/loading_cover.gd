extends Node
## Missing artwork and overlapping completion must retain an opaque cover.
var failures:=0
var checks:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok: failures+=1;printerr("FAIL ",label)
func frames(n:=3)->void:
	for i in n:await get_tree().process_frame
	await RenderingServer.frame_post_draw
func _ready()->void:
	await frames(3)
	var red:=ColorRect.new();red.color=Color.RED;red.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(red)
	var root:=GameData.root
	GameData.root="user://missing-progress-art"
	LoadingScreen.prepare(get_tree(),{"id":"missing-art"})
	await frames()
	check(LoadingScreen._current!=null and LoadingScreen._current._bink==null,"missing progress art retains fallback loader")
	var pixels:=get_viewport().get_texture().get_image()
	check(pixels.get_pixel(20,20).r<0.02 and pixels.get_pixel(pixels.get_width()-20,pixels.get_height()-20).r<0.02,"fallback is opaque across the frame")
	LoadingScreen.end()
	check(LoadingScreen._current!=null,"completion does not remove cover synchronously")
	LoadingScreen.prepare(get_tree(),{"id":"replacement"})
	var replacement:=LoadingScreen._current
	await frames()
	check(LoadingScreen._current==replacement and is_instance_valid(replacement),"older completion cannot remove a newer load's cover")
	LoadingScreen.end();await frames(4)
	check(LoadingScreen._current==null,"finished replacement clears after presentation")
	# Removal runs after a draw; queued render-thread frees affect the next
	# submitted frame, not the image that triggered the removal callback.
	await frames(2)
	pixels=get_viewport().get_texture().get_image()
	check(pixels.get_pixel(20,20).r>0.9,"completed cover releases the underlying view")
	GameData.root=root
	print("LOADING_COVER ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
