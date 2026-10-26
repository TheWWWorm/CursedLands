class_name UpdateNotice
extends HFlowContainer
## Non-modal main-menu entry. No file downloads, replacement or restart.
var checker: ReleaseCheck
var _check: Button
var _release: Button
var _open_url: Callable = OS.shell_open
var _browser_failed := false


func _ready() -> void:
	add_theme_constant_override("h_separation", 16)
	add_theme_constant_override("v_separation", 4)
	_check = Button.new()
	_release = Button.new()
	for button in [_check, _release]:
		CampaignChoices.style_button(button)
		add_child(button)
	_check.pressed.connect(func(): checker.check_now())
	_release.pressed.connect(_open_release)
	checker = ReleaseCheck.new()
	add_child(checker)
	checker.changed.connect(_refresh)
	checker.automatic()
	_refresh()
	var timer := Timer.new()
	timer.wait_time = 1.0
	timer.timeout.connect(_refresh)
	add_child(timer)
	timer.start()


func typography(pixels: int) -> void:
	for button in [_check, _release]:
		button.add_theme_font_size_override("font_size", pixels)
		button.custom_minimum_size.y = maxf(36, pixels * 1.8)


func _refresh() -> void:
	var now := int(Time.get_unix_time_from_system())
	_check.disabled = not checker.due(true, now)
	_check.visible = checker.state != ReleaseCheck.State.AVAILABLE
	_release.visible = checker.state in [ReleaseCheck.State.AVAILABLE, ReleaseCheck.State.FAILED]
	_check.text = RemakeText.t("Check for updates")
	match checker.state:
		ReleaseCheck.State.CHECKING: _check.text = RemakeText.t("Checking for updates…")
		ReleaseCheck.State.CURRENT: _check.text = RemakeText.t("Up to date")
		ReleaseCheck.State.FAILED: _check.text = RemakeText.t("Check failed. Try again")
	if checker.state == ReleaseCheck.State.FAILED and _check.disabled:
		_check.text = RemakeText.t("Try again in %d s") % maxi(1, maxi(checker._retry_at, checker._last_attempt + 60) - now)
	_release.text = RemakeText.t("Download update %s") % checker.latest_tag.trim_prefix("v") if checker.state == ReleaseCheck.State.AVAILABLE else RemakeText.t("Go to downloads")
	if _browser_failed: _release.text = RemakeText.t("Could not open browser. Try again")
	_check.tooltip_text = RemakeText.t("Checks GitHub for a newer stable release. You can keep playing while it checks.")
	_release.tooltip_text = RemakeText.t("Opens GitHub in your browser. Download the package for your platform and follow its installation instructions.")


func _open_release() -> void:
	_browser_failed = _open_url.call(checker.release_url()) != OK
	_refresh()


func pad_targets() -> Array:
	var targets := []
	if _check.is_visible_in_tree() and not _check.disabled: targets.append({"rect": _check.get_global_rect(), "id": "check_updates"})
	if _release.is_visible_in_tree(): targets.append({"rect": _release.get_global_rect(), "id": "open_release"})
	return targets


func activate(action: String) -> void:
	if action == "check_updates" and _check.visible and not _check.disabled: checker.check_now()
	if action == "open_release" and _release.visible: _open_release()
