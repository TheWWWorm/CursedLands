extends Node
func _ready() -> void:
	var sampler := PerformanceLog.new()
	add_child(sampler)
	sampler.set_process(false)
	var batches := []
	for batch in 9:
		var started := Time.get_ticks_usec()
		for i in 20000: sampler._process(0.0)
		batches.append((Time.get_ticks_usec()-started)/20000.0)
	batches.sort()
	var row := {"observations":180000,"median_us_per_callback":batches[4],"batches_us_per_callback":batches,"scope":"Local CPU microbenchmark, not an end-to-end FPS or target-laptop performance measurement"}
	FileAccess.open("user://performance-log-cost.json",FileAccess.WRITE).store_string(JSON.stringify(row,"\t"))
	print("PACING_COST ",JSON.stringify(row))
	sampler.free();get_tree().quit()
