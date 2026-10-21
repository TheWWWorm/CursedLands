extends "movie_audio.gd"
## Full ending sequence with deterministic short movie caches; source audio is
## also decoded separately from the installed original Bink files below.
func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	MoviePlayer.enabled=true;cache()
	var names:=Array(MoviePlayer.ini_movies("Crdtfin"))+["crdt"]+Array(MoviePlayer.ini_movies("Crdtfout"))
	var source_audio:=[]
	for name:String in names:
		var bk:=EIBink.new()
		check(bk.open(GameData.root.path_join("movies/"+name+".bik")),"original movie opens: "+name)
		var row:={"movie":name,"tracks":bk.audio_tracks.size(),"frames":bk.frame_count}
		if not bk.audio_tracks.is_empty():
			var audio:=EIBinkAudio.new(bk.audio_tracks[0],bk.revision)
			var bytes:=0;var nonzero:=false
			for i in mini(200,bk.frame_count):
				var pcm:=audio.decode_packet(bk.audio_packet(bk.frame_data(i)))
				bytes+=pcm.size()
				for value:int in pcm:
					if value!=0:nonzero=true;break
			row.bytes=bytes;row.nonzero=nonzero
			check(bytes>0 and nonzero,"original soundtrack decodes: "+name)
		source_audio.append(row)
		DirAccess.copy_absolute("user://movies/audio-fixture.eiv","user://movies/"+name+".eiv")
	var metadata:=EIBinkCache.open_cache("user://movies/crdt.eiv",true)
	check(not metadata.is_empty() and not metadata.has("pcm") and not metadata.has("offsets"),"prewarm verifies cache without loading soundtrack or frame index")
	GameData.options.merge({"volume_sfx":37,"volume_stream":61,"volume_voice":49},true);GameData._apply_audio()
	var c:=CreditsPanel.new();c.screen_name="Crdt";add_child(c)
	await frames()
	check(game_muted(),"credits mutes gameplay before first ending movie")
	var played:=[]
	for name:String in MoviePlayer.ini_movies("Crdtfin"):
		var sequence:MovieSequence
		for child:Node in c.get_children():
			if child is MovieSequence:sequence=child
		check(sequence!=null and sequence._player._name==name,"opening sequence plays "+name)
		if sequence:
			played.append(sequence._player._name)
			check(sequence._player._audio.playing,"opening movie audio is playing")
			sequence._player._advance(5)
			check(game_muted(),"gameplay stays muted during deferred movie handoff")
		await frames()
	check(c._music.playing and c._music.bus=="Movie" and not muted("Movie"),"credits music plays over silent looping background")
	check(c._bg!=null and c._bg.loop and c._bg.silent,"credits background is intentionally silent")
	c._close();await frames()
	for name:String in MoviePlayer.ini_movies("Crdtfout"):
		var sequence:MovieSequence
		for child:Node in c.get_children():
			if child is MovieSequence:sequence=child
		check(sequence!=null and sequence._player._name==name,"closing sequence plays "+name)
		if sequence:
			played.append(sequence._player._name)
			check(sequence._player._audio.playing,"closing movie audio is playing")
			sequence._player._advance(5)
			check(game_muted(),"gameplay stays muted until credits finishes")
		await frames()
	check(not is_instance_valid(c) and GameData._movie_audio_owners.is_empty(),"full sequence releases all audio ownership")
	check(not muted("SFX") and not muted("Music") and not muted("Voice"),"leaving credits restores player audio settings")
	FileAccess.open("user://credits_audio.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"source_audio":source_audio,"played":played},"\t"))
	print("CREDITS_AUDIO ",checks," checks ",failures.size()," failures")
	TexUpscale.shutdown();get_tree().quit(0 if failures.is_empty() else 1)
