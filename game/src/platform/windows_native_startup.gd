extends Control
## Startup recovery for the required Windows native helper. Opening Windows
## Security is a user action; this screen never changes a security setting.

const TITLE := "Native acceleration could not start"
const DETAILS := "Windows could not load libterrain_search.dll. This Windows build needs it for native acceleration."
const POLICY := "If the Windows error says 0xC0E90002, Application Control blocked the file. If Smart App Control is On, you can turn it Off in Windows Security > App & browser control > Smart App Control, then close and reopen the game."
const SCOPE := "Turning Smart App Control off changes protection for all apps. Older Windows versions may require a Windows reset to turn it back on."
const OTHER := "If Smart App Control is already Off, extract the complete release folder again. On a managed PC, ask your administrator about its Application Control policy."
const OPEN := "Open Windows Security"
const QUIT := "Close game"


static func required() -> bool:
	return OS.has_feature("windows") and not OS.has_feature("editor") \
		and not ClassDB.class_exists("TerrainSearchKernel")


static func instructions() -> String:
	return "\n\n".join(PackedStringArray([DETAILS, POLICY, SCOPE, OTHER]))


func _ready() -> void:
	name = "WindowsNativeStartup"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background := ColorRect.new()
	background.color = Color(0.07, 0.075, 0.08)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	add_child(margin)
	var center := CenterContainer.new()
	margin.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = minf(700, maxf(get_viewport_rect().size.x - 48, 240))
	center.add_child(panel)
	var inner := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		inner.add_theme_constant_override("margin_" + side, 20)
	panel.add_child(inner)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	inner.add_child(column)
	var heading := Label.new()
	heading.text = RemakeText.t(TITLE)
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	heading.add_theme_font_size_override("font_size", 24)
	column.add_child(heading)
	for paragraph: String in [DETAILS, POLICY, SCOPE, OTHER]:
		var label := Label.new()
		label.text = RemakeText.t(paragraph)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_font_size_override("font_size", 16)
		column.add_child(label)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	column.add_child(buttons)
	var security := Button.new()
	security.name = "OpenSecurity"
	security.text = RemakeText.t(OPEN)
	security.pressed.connect(func():
		var result := OS.shell_open("ms-settings:windowsdefender")
		if result != OK:
			security.text = RemakeText.t("Open Windows Security from the Start menu"))
	buttons.add_child(security)
	var close := Button.new()
	close.name = "CloseGame"
	close.text = RemakeText.t(QUIT)
	close.pressed.connect(func(): get_tree().quit())
	buttons.add_child(close)
	security.grab_focus()
