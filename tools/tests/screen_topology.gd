extends Node
## A native display can temporarily have no monitors during teardown or a
## topology change. Do not issue a per-screen query until enumeration is valid.
class Display extends RefCounted:
	var screens: Array[Vector2i]=[]
	var current:=0
	var queries:=0
	var invalid:=0
	func get_name() -> String:return "Windows"
	func get_screen_count() -> int:return screens.size()
	func window_get_current_screen() -> int:return current
	func screen_get_size(index: int) -> Vector2i:
		queries+=1
		if index<0 or index>=screens.size():invalid+=1;return Vector2i.ZERO
		return screens[index]

var checks:=0
var failures:=0
func check(ok: bool,label: String) -> void:
	checks+=1;print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1

func _ready() -> void:
	var display:=Display.new()
	check(GameData._screen_size_from(display)==Vector2i(1920,1080),"no monitors retains the display-less resolution fallback")
	check(display.queries==0 and display.invalid==0,"no per-screen query is sent when screen_count is zero")
	display.screens.assign([Vector2i(1920,1080),Vector2i(3840,2160)]);display.current=1
	check(GameData._screen_size_from(display)==Vector2i(3840,2160),"the active 4K monitor supplies the native resolution")
	display.screens.resize(1)
	check(GameData._screen_size_from(display)==Vector2i(1920,1080),"removing the selected monitor uses a remaining valid monitor")
	display.current=-1
	check(GameData._screen_size_from(display)==Vector2i(1920,1080),"a missing current-screen assignment uses a valid monitor")
	check(display.invalid==0,"topology changes never query an invalid screen index")
	display.screens.clear()
	var before:=display.queries
	check(GameData._screen_size_from(display)==Vector2i(1920,1080) and display.queries==before,"display teardown returns the fallback without another query")
	print("SCREEN_TOPOLOGY ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
