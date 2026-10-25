extends Node
class ProbeGame extends Game:
	var picks := 0
	var target: GameUnit
	func pick_hover(_point: Vector2) -> GameUnit:
		picks+=1;return target
	func revive_target(unit: GameUnit) -> GameUnit:return unit
class ProbeHUD extends GameHUD:
	var blocked := false
	func blocks_input() -> bool:return blocked
var checks := 0
var failures := 0
func check(ok: bool,label: String) -> void:
	checks+=1;print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func _ready() -> void:run.call_deferred()
func run() -> void:
	GameData.options.revive=1;GameData.options.pad_enabled=0
	var game:=ProbeGame.new();game.session=Session.new();game.world=GameWorld.new()
	game.hud=ProbeHUD.new();game.direct=DirectControl.new();game.direct.game=game
	var helper:=GameUnit.new();helper.process_mode=Node.PROCESS_MODE_DISABLED;add_child(helper)
	helper.display_name="Companion";helper.action="revive:kneel:10";game.target=helper;game.world.units={1:helper}
	var camera:=Camera3D.new();add_child(camera);camera.position=Vector3(0,3,5);camera.look_at(Vector3(0,1.8,0));camera.current=true
	var overlay:=ReviveOverlay.new();overlay.game=game;add_child(overlay);overlay.set_process(false)
	GameData.options.control_mode=3;overlay._process(0)
	check(game.picks==0 and overlay._label.is_empty(),"hidden first-person pointer does not raycast the city for a mouse label")
	check(overlay._bars.size()==1 and is_equal_approx(overlay._bars[0][1],0.5),"revive progress remains visible during first-person movement")
	game.direct.pointer=true;overlay._process(0)
	check(game.picks==1 and overlay._label.contains(helper.display_name),"revealing the pointer restores its revive hover label")
	game.direct.pointer=false;var before:=game.picks;overlay._process(0)
	check(game.picks==before and overlay._label.is_empty(),"hiding the pointer clears the prior hover without another hit-test")
	GameData.options.control_mode=2;overlay._process(0)
	check(game.picks==before and overlay._bars.size()==1,"third-person direct movement also skips inactive mouse picking")
	for mode in [0,1]:
		GameData.options.control_mode=mode;before=game.picks;overlay._process(0)
		check(game.picks==before+1 and not overlay._label.is_empty(),"tactical mouse hover remains active in camera mode "+str(mode))
	game.hud.blocked=true;before=game.picks;overlay._process(0)
	check(game.picks==before and overlay._label.is_empty(),"blocking UI suppresses the hover query")
	GameData.options.revive=0;overlay._process(0)
	check(game.picks==before and overlay._bars.is_empty(),"disabled revival removes overlay work")
	overlay.free();camera.free();helper.free();game.direct.free();game.hud.free();game.world.free();game.session.free();game.free()
	print("REVIVE_OVERLAY_PICKING ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
