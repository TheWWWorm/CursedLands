extends Node
var frames:=0
func _process(_delta:float)->void:
	frames+=1
	if frames%5!=0:return
	var file:=FileAccess.open("user://service-counter.tmp",FileAccess.WRITE)
	file.store_string(JSON.stringify({"pid":OS.get_process_id(),"frames":frames}));file.close()
	DirAccess.rename_absolute("user://service-counter.tmp","user://service-counter.json")
