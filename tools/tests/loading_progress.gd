extends Node
var checks:=0
var failures:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func _ready()->void:
	for i in 3:await get_tree().process_frame
	var stage:Array=[]
	LoadingScreen.on_frame=func(n:int):stage.append(n)
	LoadingScreen.prepare(get_tree(),{"id":"gz1g","allod":"gipat"},LoadingScreen.NEW_ZONE)
	var screen:=LoadingScreen._current
	check(screen!=null and screen._bink!=null,"original loading movie opens")
	if screen:
		var first:=screen._tex[0].get_image().get_data()
		var deadline := Time.get_ticks_msec()+2500
		while screen._decoded<2 and Time.get_ticks_msec()<deadline:await get_tree().process_frame
		check(screen._decoded>=2 and screen._decoded<8,"original letters progress while the worker builds")
		check(screen._tex[0].get_image().get_data()!=first,"progress changes the actual movie pixels")
		check(LoadingScreen._current==screen,"progress cannot uncover an unfinished load")
		LoadingScreen.step(10);LoadingScreen.end()
		for i in 12:await get_tree().process_frame
		check(LoadingScreen._current==null,"completed load releases its cover")
	LoadingScreen.on_frame=Callable()
	print("LOADING_PROGRESS ",checks," checks ",failures," failures ",stage)
	get_tree().quit(1 if failures else 0)
