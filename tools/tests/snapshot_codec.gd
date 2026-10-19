extends Node
var checks := 0
var failures := 0

func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL ",label)

func _ready() -> void:
	var sender := Session.new(); add_child(sender); sender.set_physics_process(false)
	var world := GameWorld.new(); world.process_mode=Node.PROCESS_MODE_DISABLED; add_child(world)
	sender.world=world; sender._pool_epoch=4
	var actors: Array[GameUnit] = []
	for i in 8:
		var actor := GameUnit.new(); actor.uid=1000+i; actor.world=world
		world.add_child(actor); world.set_unit(actor.uid,actor); actors.append(actor)
	var random := RandomNumberGenerator.new(); random.seed=683137
	var raw_bytes := 0; var wire_bytes := 0
	for step in 96:
		var records := []
		for actor in actors:
			actor.pos=Vector2(random.randf_range(0,512),random.randf_range(0,512))
			actor.facing=random.randf_range(-PI,PI); actor.hp=random.randf_range(1,100)
			actor.mana=random.randf_range(0,80); actor.action=["idle","walk","run","attack"][step%4]
			var record := actor.snapshot()
			record[11]=[["eagle_sight",123.125,15.0,3.0],["bless",160.5]]
			record[12]=[PackedInt32Array([1001,1004,2001]),PackedInt32Array([4005])]
			record[14]=step; record[15]=1003
			records.append(record)
		var wire := NetSnapshot.pack(records)
		raw_bytes+=var_to_bytes(records).size(); wire_bytes+=var_to_bytes(wire).size()
		check(NetSnapshot.unpack(wire)==records,"lossless poses, health, buffs, perception and action serials "+str(step))
		check(var_to_bytes(wire).size()<var_to_bytes(records).size(),"compressed records retain the packet's size bound "+str(step))
	var snapshot := actors[0].snapshot(); snapshot[1]=24.0
	# These are data-only actors; rendering one-shots is covered with real
	# figures in unit_presentation_timing.gd.
	snapshot[4]="idle"
	snapshot[12]=[PackedInt32Array(range(1000,1064)),PackedInt32Array()]
	var packed := NetSnapshot.pack([snapshot])
	check(packed[0] is int,"single party actor with retained perception uses compression")
	check(NetSnapshot.unpack(packed)==[snapshot],"single-actor chunks remain readable")
	sender._rpc_snap(packed,2.0,3,1)
	check(actors[0].pos.x!=24.0,"old campaign generation rejects compressed packets")
	sender._rpc_snap(packed,2.0,4,1)
	check(actors[0].pos.x==24.0,"current campaign generation decodes before applying actor state")
	snapshot[1]=32.0
	sender._rpc_snap(NetSnapshot.pack([snapshot]),1.0,4,0)
	check(actors[0].pos.x==24.0,"compression retains per-actor stale-packet rejection")
	sender.lmp={"base":"bz1mpg"}; sender.zone_id="gz1g"; sender.lmp_generation=8
	packed=NetSnapshot.pack([snapshot])
	sender._rpc_lmp_snap("gz2g",8,packed,3.0,2)
	sender._rpc_lmp_snap("gz1g",7,packed,3.0,2)
	check(actors[0].pos.x==24.0,"LMP location and generation still fence compressed data")
	sender._rpc_lmp_snap("gz1g",8,packed,3.0,2)
	check(actors[0].pos.x==32.0,"current LMP scope decodes the same exact actor record")
	check(NetSnapshot.pack([]).is_empty() and NetSnapshot.unpack([]).is_empty(),"empty chunks remain empty")
	check(NetSnapshot.unpack([snapshot])==[snapshot],"uncompressed snapshots remain readable")
	for invalid in [[-1,PackedByteArray([1])],[NetSnapshot.MAX_BYTES+1,PackedByteArray([1])],
		[1,"wrong"],[1,PackedByteArray()],[1.0,PackedByteArray([1])],[1]]:
		check(NetSnapshot.unpack(invalid).is_empty(),"malformed compression wrapper is refused")
	var nested := var_to_bytes([32,PackedByteArray([1,2,3])])
	check(NetSnapshot.unpack([nested.size(),nested.compress(FileAccess.COMPRESSION_ZSTD)]).is_empty(),"nested wrappers cannot become actor rows")
	check(wire_bytes<raw_bytes/2,"complete snapshot codec cuts representative bytes by more than half")
	print("SNAPSHOT_CODEC_COST ",JSON.stringify({"raw_bytes":raw_bytes,"wire_bytes":wire_bytes}))
	sender.world=null; world.free(); sender.queue_free()
	for i in 4: await get_tree().process_frame
	print("SNAPSHOT_CODEC %d checks %d failures"%[checks,failures])
	get_tree().quit(1 if failures else 0)
