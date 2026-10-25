extends RefCounted
static var enabled := false
static var rows := {}
static func record(label: String, elapsed: int)->void:
	if not rows.has(label):rows[label]={"calls":0,"inclusive_us":0,"max_us":0}
	var row: Dictionary=rows[label]
	row.calls+=1;row.inclusive_us+=elapsed;row.max_us=maxi(row.max_us,elapsed)
static func begin()->void:
	rows.clear();counts.clear();enabled=true
static func end()->void:
	enabled=false
	FileAccess.open("user://cpu-census.json",FileAccess.WRITE).store_string(JSON.stringify(counts,"\t"))
	FileAccess.open("user://cpu-scopes.json",FileAccess.WRITE).store_string(JSON.stringify(rows,"\t"))

static var counts := {}
static func count(label: String, n: int)->void:
	counts[label]=int(counts.get(label,0))+n
