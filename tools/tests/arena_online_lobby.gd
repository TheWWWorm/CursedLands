extends Node
var checks:=0
var failures:Array[String]=[]
var sessions:Array[ArenaOnlineSession]=[]
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:failures.append(message);printerr("FAIL ",message)
func frames(count:=6)->void:
	for i in count:await get_tree().process_frame
func wait_for(predicate:Callable)->bool:
	var deadline:=Time.get_ticks_msec()+8000
	while not predicate.call() and Time.get_ticks_msec()<deadline:await get_tree().process_frame
	return predicate.call()
func client(password:String)->ArenaOnlineSession:
	var result:=ArenaOnlineSession.new();result.password=password;result.player_name="Guest %d"%sessions.size()
	add_child(result);sessions.append(result)
	check(result.join("127.0.0.1:29820")==OK,"connection request starts")
	return result
func _ready()->void:
	await frames()
	var host:=ArenaOnlineSession.new();host.password="room-key";host.player_name="Host";add_child(host)
	check(host.host(29820)==OK,"private host starts")
	var wrong:=client("wrong")
	check(await wait_for(func():return not wrong.status.is_empty()),"wrong password gets explicit rejection")
	check(wrong.status==RemakeText.t("Incorrect password.") and host.members.size()==1,"wrong password cannot claim a seat")
	for index in 8:
		var guest:=client("room-key")
		check(await wait_for(func():return guest.my_seat==index+1),"human seat %d admitted"%(index+1))
	check(host.members.size()==9,"full nine-human room")
	var excess:=client("room-key")
	check(await wait_for(func():return not excess.status.is_empty()),"full lobby rejection arrives")
	check(excess.status==RemakeText.t("This online game is full."),"full lobby gives the right reason")
	var seats:=host.members.values().map(func(member):return member.seat)
	seats.sort();check(seats==range(9),"all human seats are distinct")
	var first:=sessions[1]
	first.close();check(await wait_for(func():return host.members.size()==8),"lobby departure releases seat")
	var replacement:=client("room-key")
	check(await wait_for(func():return replacement.my_seat==1),"new joiner gets the free lobby seat")
	for guest in sessions:
		if guest.peer and guest.my_seat>=0:guest.request("ready")
	check(await wait_for(func():return host.members.values().all(func(member):return member.ready)),"every peer can ready")
	check(host.start_game(7191).is_empty(),"nine-human game starts")
	host.game.set_process(false)
	check(await wait_for(func():return replacement.started),"all peers enter the match")
	host.game.run.finish_preparation()
	check(host.game.run.company(8).army.is_empty(),"no bot can spend for the ninth human")
	var late:=client("room-key")
	check(await wait_for(func():return not late.status.is_empty()),"late join rejected")
	check(late.status==RemakeText.t("This online game has already started."),"late join cannot replace an ongoing company")
	var original:=host.game.run.company(1).snapshot()
	replacement._send(1,{"t":"command","seq":100,"round":999,"action":"buy","args":[0]})
	await frames(12)
	check(host.game.run.company(1).snapshot()==original,"stale-round command cannot mutate state")
	replacement._send(1,{"t":"command","seq":101,"round":1,"action":"deploy","args":["uid","invalid"]})
	await frames(12)
	check(host.game.run.company(1).snapshot()==original,"malformed command cannot mutate state")
	host.close()
	check(await wait_for(func():return not replacement.status.is_empty()),"host departure reaches clients")
	check(not replacement.view.connected,"host loss disables client actions")
	for guest in sessions:guest.close();guest.queue_free()
	host.queue_free();await frames()
	for language in ["en","ru","de"]:
		RemakeText.lang=language
		for key in ArenaOnlineSession.ERRORS:
			check(not RemakeText.t(key).is_empty() and (language=="en" or RemakeText.t(key)!=key),"localized network error "+language)
	print("ARENA_ONLINE_LOBBY ",checks," checks; failures=",JSON.stringify(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
