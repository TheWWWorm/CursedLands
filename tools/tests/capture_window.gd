extends RefCounted
## Test-only capture setup. Wait for the native window, viewport and mode to
## agree after leaving maximized/fullscreen; rendered fixtures keep their own
## exact-size assertions and fail if this setup cannot obtain the extent.

static func resize(owner: Node, extent: Vector2i) -> bool:
	var w:=owner.get_window()
	GameData._window_gen+=1
	w.wrap_controls=false;w.min_size=Vector2i.ONE
	# Leave a maximized/fullscreen window while framed and smaller than the
	# monitor. Windows acknowledges each style transition asynchronously.
	w.borderless=false;w.mode=Window.MODE_WINDOWED
	w.size=Vector2i(960,540);w.position=Vector2i(32,32)
	await owner.get_tree().create_timer(0.2,true,false,true).timeout
	w.borderless=true
	await owner.get_tree().create_timer(0.2,true,false,true).timeout
	var until:=Time.get_ticks_msec()+5000
	var stable:=0;var retry:=0
	while Time.get_ticks_msec()<until:
		if Time.get_ticks_msec()>=retry and (w.mode!=Window.MODE_WINDOWED or w.size!=extent):
			w.borderless=false;w.mode=Window.MODE_WINDOWED;w.borderless=true;w.position=Vector2i(32,32);w.size=extent
			retry=Time.get_ticks_msec()+200
		await RenderingServer.frame_post_draw
		var ready:=w.mode==Window.MODE_WINDOWED and w.size==extent and DisplayServer.window_get_size()==extent and Vector2i(owner.get_viewport().get_visible_rect().size)==extent
		stable=stable+1 if ready else 0
		if stable>=3:return true
	return false
