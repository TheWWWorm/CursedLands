class_name UiInput
## Keyboard "cancel" and "confirm" as InputMap actions.
##
## Panels used to test `keycode == KEY_ESCAPE` and `KEY_ENTER`/`KEY_KP_ENTER`
## one by one; they now ask these two questions, so the bindings live in the
## project's InputMap (`remake_cancel`, `remake_confirm`), can be rebound or
## extended in one place, and a key PadUI synthesizes for a gamepad button
## is recognized through the same path. The checks keep the panels' old
## semantics: a pressed key event (echoes included unless the caller filters
## them) whose keycode is bound to the action.

const CANCEL := "remake_cancel"
const CONFIRM := "remake_confirm"


static func is_cancel(event: InputEvent) -> bool:
	return event is InputEventKey and event.pressed and event.is_action(CANCEL)


static func is_confirm(event: InputEvent) -> bool:
	return event is InputEventKey and event.pressed and event.is_action(CONFIRM)
