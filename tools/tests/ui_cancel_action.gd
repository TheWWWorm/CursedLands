extends Node
## Panels take "cancel" and "confirm" from the InputMap actions
## `remake_cancel` / `remake_confirm` (UiInput), not from a keycode test of
## their own. Rebinding the action must move every panel at once; the key a
## gamepad button is translated to by PadUI must still count.
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL ", label)

func key(code: Key, pressed := true, echo := false) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code; e.pressed = pressed; e.echo = echo
	return e

func bind_cancel(code: Key) -> void:
	InputMap.action_erase_events(UiInput.CANCEL)
	InputMap.action_add_event(UiInput.CANCEL, key(code))

func box_dismissed(esc_closes: bool, event: InputEventKey) -> Dictionary:
	var box := MessageBox.ask(self, "yes_no", "sure", [], false)
	box.esc_closes = esc_closes
	var seen := {"dismissed": false, "answer": null}
	box.dismissed.connect(func(): seen.dismissed = true)
	box.answered.connect(func(yes: bool): seen.answer = yes)
	box._unhandled_key_input(event)
	if is_instance_valid(box): box.queue_free()
	return seen

func _ready() -> void:
	check(InputMap.has_action(UiInput.CANCEL) and InputMap.has_action(UiInput.CONFIRM), "project declares the cancel and confirm actions")
	var codes := []
	for e: InputEvent in InputMap.action_get_events(UiInput.CANCEL): codes.append((e as InputEventKey).keycode)
	check(codes == [KEY_ESCAPE], "cancel is Escape by default")
	codes = []
	for e: InputEvent in InputMap.action_get_events(UiInput.CONFIRM): codes.append((e as InputEventKey).keycode)
	check(codes == [KEY_ENTER, KEY_KP_ENTER], "confirm is Enter and keypad Enter by default")

	check(UiInput.is_cancel(key(KEY_ESCAPE)), "Escape press cancels")
	check(UiInput.is_cancel(key(KEY_ESCAPE, true, true)), "a repeated Escape still counts, as the keycode test did")
	check(not UiInput.is_cancel(key(KEY_ESCAPE, false)), "Escape release does not cancel")
	check(not UiInput.is_cancel(key(KEY_ENTER)), "Enter does not cancel")
	check(UiInput.is_confirm(key(KEY_ENTER)) and UiInput.is_confirm(key(KEY_KP_ENTER)), "Enter and keypad Enter confirm")
	check(not UiInput.is_confirm(key(KEY_SPACE)), "Space does not confirm")
	var synthesized := InputEventKey.new(); synthesized.keycode = KEY_ESCAPE; synthesized.pressed = true   # PadUI.key()
	check(UiInput.is_cancel(synthesized), "a key PadUI synthesizes for the pad's cancel button is recognized")
	var mouse := InputEventMouseButton.new(); mouse.pressed = true
	check(not UiInput.is_cancel(mouse) and not UiInput.is_confirm(mouse), "mouse buttons are neither")

	# Real panels through their own handlers.
	var seen := box_dismissed(true, key(KEY_ESCAPE))
	check(seen.dismissed and seen.answer == null, "message box: Escape dismisses")
	seen = box_dismissed(false, key(KEY_ESCAPE))
	check(seen.answer == false, "message box: Escape answers no when it cannot dismiss")
	seen = box_dismissed(false, key(KEY_KP_ENTER))
	check(seen.answer == true, "message box: keypad Enter answers yes")
	var internet: Control = preload("res://src/ui/internet_panel.gd").new(); add_child(internet)
	internet.open(false, false)
	var closed := {"n": 0}
	internet.closed.connect(func(): closed.n += 1)
	internet._unhandled_key_input(key(KEY_ESCAPE))
	check(closed.n == 1 and not internet.visible, "internet panel: Escape closes")
	var chat := ChatLine.new(); add_child(chat); chat.visible = true; chat.text = "draft"
	chat._gui_input(key(KEY_ESCAPE))
	check(not chat.visible and chat.text == "", "chat line: Escape drops the draft")

	# Rebinding the action rebinds every panel; the old key stops working.
	bind_cancel(KEY_BACKSPACE)
	check(not UiInput.is_cancel(key(KEY_ESCAPE)) and UiInput.is_cancel(key(KEY_BACKSPACE)), "rebound cancel follows the InputMap")
	seen = box_dismissed(true, key(KEY_ESCAPE))
	check(not seen.dismissed, "message box: Escape no longer dismisses after rebinding")
	seen = box_dismissed(true, key(KEY_BACKSPACE))
	check(seen.dismissed, "message box: the rebound key dismisses")
	internet.open(false, false); closed.n = 0
	internet._unhandled_key_input(key(KEY_ESCAPE))
	check(closed.n == 0 and internet.visible, "internet panel: Escape no longer closes after rebinding")
	internet._unhandled_key_input(key(KEY_BACKSPACE))
	check(closed.n == 1 and not internet.visible, "internet panel: the rebound key closes")
	chat.visible = true; chat.text = "draft"
	chat._gui_input(key(KEY_ESCAPE))
	check(chat.visible and chat.text == "draft", "chat line: Escape no longer drops the draft after rebinding")
	chat._gui_input(key(KEY_BACKSPACE))
	check(not chat.visible, "chat line: the rebound key closes")
	bind_cancel(KEY_ESCAPE)
	check(UiInput.is_cancel(key(KEY_ESCAPE)), "default binding restored")
	for i in 4: await get_tree().process_frame
	print("UI_CANCEL_ACTION ", checks, " checks ", failures, " failures")
	get_tree().quit(1 if failures else 0)
