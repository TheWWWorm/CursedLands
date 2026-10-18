extends Node
## Unheard NPC reactions do not load voices; party changes stay live.
class CaptureSession extends Session:
	var messages := []
	func broadcast(event: Dictionary) -> void: messages.append(event)
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL ",label)
func _ready() -> void:
	var session := CaptureSession.new()
	var world := GameWorld.new(); world.session = session; session.world = world
	world.authority = false # Supply the existing received perception records.
	var speaker := GameUnit.new(); speaker.uid = 10; speaker.world = world
	speaker.info = {"voice":"Test voice"}; speaker.proto = {"name":"Test voice"}
	world.add_child(speaker); world.set_unit(speaker.uid,speaker)
	EIAcks._loaded = false; EIAcks._sets.clear()
	world.ai._react(speaker,EIAcks.NPC_AGGRESSION)
	check(not EIAcks._loaded and session.messages.is_empty(),"no controlled listener leaves the voice database unloaded")
	var hero := GameUnit.new(); hero.uid = 20; hero.world = world; hero.controller = 0
	hero.set_meta("net_noticed",[speaker.uid]); world.add_child(hero); world.set_unit(hero.uid,hero)
	EIAcks._loaded = true; EIAcks._sets = {2:{"test voice":{10:[{"wav":"fixture.wav","chance":100,"text":"fixture"}]}}}
	world.ai._react(speaker,EIAcks.NPC_AGGRESSION)
	check(session.messages == [{"t":"ack","uid":10,"code":EIAcks.NPC_AGGRESSION,"to":0}],"new listener receives the original acknowledgement")
	var companion := GameUnit.new(); companion.uid = 21; companion.world = world; companion.controller = 0
	companion.set_meta("net_noticed",[speaker.uid]); world.add_child(companion); world.set_unit(companion.uid,companion)
	session.messages.clear(); world.ai._react(speaker,EIAcks.NPC_AGGRESSION)
	check(session.messages.size()==1,"multiple party members do not duplicate a player's voice")
	companion.controller = 1
	session.messages.clear(); world.ai._react(speaker,EIAcks.NPC_AGGRESSION)
	check(session.messages.map(func(e):return e.to)==[0,1],"new owner receives its own acknowledgement")
	hero.set_meta("net_noticed",[])
	session.messages.clear(); world.ai._react(speaker,EIAcks.NPC_AGGRESSION)
	check(session.messages.size()==1 and session.messages[0].to==1,"unaware player does not receive a voice")
	speaker.hidden = true
	session.messages.clear(); world.ai._react(speaker,EIAcks.NPC_AGGRESSION)
	check(session.messages.is_empty(),"hidden speaker remains silent")
	speaker.hidden = false
	hero.controller = -1; companion.controller = -1
	EIAcks._loaded = false
	world.ai._react(speaker,EIAcks.NPC_AGGRESSION)
	check(not EIAcks._loaded,"removing all ownership invalidates the cached listener set")
	world.free(); session.world = null; session.free()
	print("AI_REACTION_RECIPIENTS ",checks," checks; failures=",failures)
	get_tree().quit(1 if failures else 0)
