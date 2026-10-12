extends Node
## Reusing a sample channel alternates speech/SFX routing while the native
## audio thread mixes it. No silent/disabled mixer shortcut is used.
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ",label)
func _ready() -> void:
	var mixer := SoundMixer.new(); add_child(mixer)
	var stream := AudioStreamWAV.new(); stream.format=AudioStreamWAV.FORMAT_16_BITS; stream.mix_rate=44100
	var data := PackedByteArray(); data.resize(44100*2)
	for i in 44100: data.encode_s16(i*2,int(sin(i*TAU*220.0/44100)*1000))
	stream.data=data; stream.loop_mode=AudioStreamWAV.LOOP_FORWARD; stream.loop_end=44100
	var chan: SoundMixer.Chan=mixer._chans[0]
	var sound := {"stream":stream,"handle":1,"cat":SoundMixer.CAT_SFX,"vol":100,"pan":0,"cam":false,"is3d":false,"loop":true,"prio":1}
	var swaps := 0; var wrong := 0
	for frame in 300:
		for i in 200:
			sound.cat=i%2
			mixer._bind(chan,sound,0.0)
			if AudioServer.get_bus_send(AudioServer.get_bus_index(chan.bus))!=(&"Voice" if i%2 else &"SFX"): wrong+=1
			swaps+=1
		await get_tree().process_frame
	check(swaps==60000 and wrong==0,"60,000 live sample reuses retain their requested speech/SFX destination")
	check(AudioServer.get_bus_send(0)==&"" and AudioServer.get_bus_send(AudioServer.get_bus_index("SFX"))==&"Master", "sample rerouting leaves the master and SFX parent topology intact")
	mixer.stop_all(); mixer.queue_free()
	for i in 8: await get_tree().process_frame
	print("AUDIO_BUS_ROUTES %d checks %d failures"%[checks,failures])
	get_tree().quit(1 if failures else 0)
