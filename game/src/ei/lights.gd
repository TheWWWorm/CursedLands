class_name EILights
extends RefCounted
## config/Lights[Cave]<Allod>.ini: hourly colours (time00 .. time23 = r, g, b) in
## the sections [sunlight], [ambient] and [sky]. the original builds the
## name from "Lights", "Cave" for cave zones and the allod (Gipat, Ingos,
## Suslanger).

var sections := {}   # name -> Array[Color] (24)


static func load_for(allod: String, cave: bool) -> EILights:
	var path := GameData.root.path_join("config/Lights%s%s.ini" % ["Cave" if cave else "", allod])
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		# The GOG files are lower case.
		f = FileAccess.open(GameData.root.path_join(("config/lights%s%s.ini" % ["cave" if cave else "", allod]).to_lower()), FileAccess.READ)
	if f == null:
		return null
	var out := EILights.new()
	var cur := ""
	for line in f.get_as_text().split("\n"):
		line = line.strip_edges()
		if line.begins_with("["):
			cur = line.trim_prefix("[").trim_suffix("]").to_lower()
			var arr: Array[Color] = []
			arr.resize(24)
			arr.fill(Color.WHITE)
			out.sections[cur] = arr
		elif "=" in line and cur and line.to_lower().begins_with("time"):
			var h := line.get_slice("=", 0).strip_edges().substr(4).to_int()
			var c := line.get_slice("=", 1).split(",")
			if h >= 0 and h < 24 and c.size() >= 3:
				out.sections[cur][h] = Color8(c[0].to_int(), c[1].to_int(), c[2].to_int())
	return out


## Colour of a section at `hour` (0..24), interpolated between the hourly keys.
func sample(section: String, hour: float) -> Color:
	var arr: Array = sections.get(section, [])
	if arr.size() < 24:
		return Color.WHITE
	hour = fposmod(hour, 24.0)
	var i := int(hour)
	return (arr[i] as Color).lerp(arr[(i + 1) % 24], hour - i)


## Allod of a zone id by its suffix (gz1g Gipat, gz11k Ingos, gz15h Suslanger).
static func allod_of(zone_id: String) -> String:
	var z := zone_id.get_slice("_", 0)
	match z.right(1):
		"k": return "Ingos"
		"h": return "Suslanger"
	return "Gipat"
