extends Node
## Exercise actual MoviePlayer lifecycle with a tiny valid cached movie.
var checks := 0
var failures := []
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:failures.append(label);printerr("FAIL ",label)
func frames(n:=3) -> void:
	for i in n:await get_tree().process_frame
func muted(bus: String) -> bool:
	return AudioServer.is_bus_mute(AudioServer.get_bus_index(bus))
func game_muted() -> bool:
	return muted("SFX") and muted("Music") and muted("Voice")
func cache() -> void:
	var image := Image.create(16,24,false,Image.FORMAT_L8);image.fill(Color(.5,.5,.5))
	var jpg := image.save_jpg_to_buffer()
	var c := EIBinkCache.new();c.width=16;c.height=16;c.frame_count=100;c.fps_num=25;c.fps_den=1;c.audio_rate=22050;c.audio_channels=1
	DirAccess.make_dir_recursive_absolute("user://movies")
	var f := FileAccess.open("user://movies/audio-fixture.eiv",FileAccess.WRITE)
	c._write_header(f,false,0,0,0)
	var offsets := PackedInt64Array()
	for i in 100:offsets.append(f.get_position());f.store_buffer(jpg)
	offsets.append(f.get_position())
	var pcm := PackedByteArray();pcm.resize(22050*2*4)
	var audio := f.get_position();f.store_buffer(pcm);var index := f.get_position()
	for off in offsets:f.store_64(off)
	c._write_header(f,true,audio,pcm.size(),index);f.close()
func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	MoviePlayer.enabled=true;cache()
	GameData.options.merge({"volume_sfx":37,"volume_stream":61,"volume_voice":49},true);GameData._apply_audio()
	var p := MoviePlayer.new();add_child(p);p.pause_game=true
	p.play("audio-fixture")
	check(p._state==MoviePlayer.PLAYING and p._audio.playing and p._audio.bus=="Movie","cached movie plays on isolated audio bus")
	check(game_muted() and not muted("Movie") and not muted("Master"),"movie mutes game channels while retaining its own sound")
	check(is_equal_approx(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Movie")),linear_to_db(.61)),"movie respects music-volume slider")
	check(get_tree().paused,"modal movie pauses game")
	GameData.options.volume_sfx=0;GameData.options.volume_stream=25;GameData._apply_audio()
	check(game_muted() and not muted("Movie"),"changing volume during movie keeps game channels muted")
	p.stop()
	check(not get_tree().paused and muted("SFX") and not muted("Music") and not muted("Voice"),"stop restores current channel settings and game pause")
	check(is_equal_approx(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music")),linear_to_db(.25)),"stop retains volume changed during movie")
	var q := MoviePlayer.new();add_child(q)
	p.pause_game=false;p.play("audio-fixture");q.play("audio-fixture");p.stop()
	check(game_muted(),"stopping one overlapping movie preserves other movie's mute")
	q.queue_free();await frames()
	check(not muted("Music") and not muted("Voice"),"freeing active movie restores game audio")
	p.loop=true;p.silent=true;p.play("audio-fixture")
	check(not game_muted() and not p._audio.playing,"silent credits background preserves credits music")
	p.stop();p.loop=false;p.silent=false
	p.play("missing-audio-fixture");await frames()
	check(not game_muted() and GameData._movie_audio_owners.is_empty(),"missing movie does not leak game mute")
	p.play("audio-fixture");p._advance(5)
	check(p._state==MoviePlayer.IDLE and not game_muted(),"natural completion restores game audio")
	p.play("audio-fixture");var esc := InputEventKey.new();esc.keycode=KEY_ESCAPE;esc.pressed=true;p._unhandled_input(esc)
	check(p._state==MoviePlayer.IDLE and not game_muted(),"skip restores game audio")
	# Preparation and conversion failure use the same owner, without PCM yet.
	p._conv=EIBinkCache.new();p._conv.failed=true;p._state=MoviePlayer.PREPARING;p._pause()
	check(game_muted(),"preparation suppresses background sounds")
	p._prepare();check(not game_muted(),"conversion failure restores game audio")
	get_tree().paused=true;p.play("audio-fixture");p.stop()
	check(get_tree().paused,"movie preserves an existing pause")
	get_tree().paused=false;p.queue_free();await frames()
	print("MOVIE_AUDIO ",checks," checks ",failures.size()," failures");TexUpscale.shutdown();get_tree().quit(0 if failures.is_empty() else 1)
