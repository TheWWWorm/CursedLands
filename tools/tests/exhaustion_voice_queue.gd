extends Node
## Holding a voice channel open must not build an exhaustion backlog.
class Mixer extends SoundMixer:
	var active := {}
	var spoken: Array = []
	var serial := 0
	func play2d(path: String, _prio: int, _vol: float, _pan: float, _loop := false, _cam := false, _cat := CAT_SFX) -> int:
		serial += 1; active[serial] = path; spoken.append(path); return serial
	func playing(handle: int) -> bool: return active.has(handle)
	func stop(handle: int) -> void: active.erase(handle)

var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL ", label)

func _ready() -> void:
	var sound := GameSound.new()
	var mixer := Mixer.new(); sound.mixer = mixer
	var hero := GameUnit.new(); hero.uid = 1000000001
	var other := GameUnit.new(); other.uid = 1000000002
	for quiet in [false, true]:
		sound._ack_q.clear(); sound._acks.clear(); mixer.active.clear(); mixer.spoken.clear()
		var code := EIAcks.SHOP_NO if quiet else EIAcks.OUT_OF_STAMINA
		sound._ack_queue(hero, EIAcks.SCENARIO, "story.wav")
		for i in 40: sound._ack_queue(hero, code, "tired%d.wav" % (i % 3), EIAcks.OUT_OF_STAMINA)
		check(sound._ack_q[hero.uid].size() == 2, "one exhaustion reminder waits behind story, quiet=" + str(quiet))
		sound._ack_queue(hero, EIAcks.ARM_CRIPPLED, "arm.wav")
		sound._ack_queue(hero, EIAcks.SCENARIO, "next-story.wav")
		check(sound._ack_q[hero.uid].size() == 4, "injury and scripted speech retain their ordering")
		mixer.active.clear()
		for i in 4: sound._ack_tick()
		check(mixer.spoken == ["story.wav", "tired0.wav"], "only one exhaustion line starts after story")
		for i in 40: sound._ack_queue(hero, code, "another%d.wav" % i, EIAcks.OUT_OF_STAMINA)
		check(sound._ack_q[hero.uid].size() == 3, "active exhaustion cannot queue more exhaustion")
		for i in 40:
			mixer.active.clear(); sound._ack_tick()
		check(mixer.spoken == ["story.wav", "tired0.wav", "arm.wav", "next-story.wav"], "queue drains without a stale exhaustion tail")
	# Independent actors retain independent queues.
	sound._ack_queue(other, EIAcks.OUT_OF_STAMINA, "other-tired.wav")
	check(mixer.spoken.back() == "other-tired.wav", "another character can report its own exhaustion")
	sound.free(); mixer.free(); hero.free(); other.free()
	print("EXHAUSTION_VOICE_QUEUE ", checks, " checks ", failures, " failures")
	get_tree().quit(1 if failures else 0)
