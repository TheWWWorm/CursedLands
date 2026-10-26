extends Node
## Actual menu, EN/RU/DE, native high-resolution text, keyboard/pad targets.
var checks := 0
var failures := 0
var opened: Array[String] = []

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL ", message)

func presented() -> void:
	for i in 3: await get_tree().process_frame
	await RenderingServer.frame_post_draw

func _ready() -> void:
	GameData._window_gen += 1
	get_window().mode = Window.MODE_WINDOWED
	get_window().wrap_controls = false
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	for lang in ["en", "ru", "de"]:
		RemakeText.lang = lang
		var menu := preload("res://src/ui/main_menu.gd").new()
		menu.detect_graphics = false
		add_child(menu)
		check(menu._scene != null, "real main menu is present")
		if menu._scene: menu._scene.set_process(false)
		var notice: UpdateNotice = menu._version._updates
		for button: Button in [notice._check, notice._release]:
			check(not button.flat and button.has_theme_stylebox_override("normal") and button.has_theme_stylebox_override("hover"), "updates use visible menu buttons with hover feedback")
		var c := notice.checker
		notice._open_url = func(url: String): opened.append(url); return OK
		for dimensions: Vector2i in [Vector2i(800,600), Vector2i(1920,1080), Vector2i(2560,1440), Vector2i(3840,2160), Vector2i(720,1280)]:
			get_window().content_scale_size = dimensions
			get_window().size = dimensions
			await presented()
			check(get_viewport().get_visible_rect().size == Vector2(dimensions), "native content viewport is " + str(dimensions))
			for state in [ReleaseCheck.State.IDLE, ReleaseCheck.State.CHECKING, ReleaseCheck.State.CURRENT, ReleaseCheck.State.AVAILABLE, ReleaseCheck.State.FAILED]:
				c.latest_tag = "v9.0.0"
				c.state = state
				c.changed.emit()
				await presented()
				var safe := Portability.safe_rect(menu.size)
				for button: Button in [notice._check, notice._release]:
					if not button.visible: continue
					var rect := button.get_global_rect()
					check(safe.encloses(rect), "%s %s: button fits safe area" % [lang, dimensions])
					check(not rect.intersects(menu._version._label.get_global_rect()), "update controls clear the packaged version")
					check(not rect.intersects(menu._utility_bar.get_global_rect()) and not rect.intersects(menu._wiki_hint.get_global_rect()), "%s %s state %s: update controls clear utilities %s and wiki %s (button %s, footer %s)" % [lang, dimensions, state, menu._utility_bar.get_global_rect(), menu._wiki_hint.get_global_rect(), rect, menu._version.footer_height()])
					var width := button.get_theme_font("font").get_string_size(button.text, HORIZONTAL_ALIGNMENT_LEFT, -1, button.get_theme_font_size("font_size")).x
					check(width <= button.size.x, "localized button text fits without clipping")
					check(button.custom_minimum_size.y >= 36 and button.get_theme_font_size("font_size") >= 16, "readable native text and touch target")
				check(notice._check.disabled == (state == ReleaseCheck.State.CHECKING), "busy state disables duplicate checks")
				var ids := menu.campaign_pad_targets().map(func(target): return target.id)
				check(("open_release" in ids) == notice._release.visible, "controller can reach the visible release action")
				check(("check_updates" in ids) == (notice._check.visible and not notice._check.disabled), "controller can reach an available manual check")
				if state == ReleaseCheck.State.AVAILABLE:
					var expected := {"en": "Download update 9.0.0", "ru": "Скачать обновление 9.0.0", "de": "Update 9.0.0 herunterladen"}
					check(notice._release.text == expected[lang], "download button uses localized update wording")
					if dimensions.x in [800, 3840]:
						get_viewport().get_texture().get_image().save_png("user://release-%s-%d.png" % [lang, dimensions.x])
		c.state = ReleaseCheck.State.AVAILABLE
		c.changed.emit()
		menu._on_board("open_release")
		check(opened.back() == ReleaseCheck.RELEASES + "/tag/v9.0.0", "controller opens only the intended release page")
		check(menu.visible and not get_tree().paused, "opening a release leaves the game available")
		notice._release.grab_focus()
		var count := opened.size()
		for pressed in [true, false]:
			var event := InputEventAction.new()
			event.action = "ui_accept"
			event.pressed = pressed
			Input.parse_input_event(event)
			await presented()
		check(opened.size() == count + 1, "focused button activates once through keyboard UI input")
		notice._open_url = func(_url): return ERR_CANT_OPEN
		notice._release.pressed.emit()
		check(notice._release.text == RemakeText.t("Could not open browser. Try again"), "browser launch errors have localized recovery")
		notice._refresh()
		check(notice._release.text == RemakeText.t("Could not open browser. Try again"), "retry feedback survives the periodic state refresh")
		notice._open_url = func(_url): return OK
		notice._release.pressed.emit()
		check(notice._release.text == RemakeText.t("Download update %s") % "9.0.0", "successful retry restores the download button")
		menu._on_board("options")
		await presented()
		check(not menu._version.is_visible_in_tree(), "updates hide behind options")
		menu._options._close()
		await presented()
		check(menu._version.is_visible_in_tree(), "updates return after options")
		menu.free()
	print("RELEASE_CHECK_UI ", checks, " checks ", failures, " failures")
	TexUpscale.shutdown()
	get_tree().quit(1 if failures else 0)
