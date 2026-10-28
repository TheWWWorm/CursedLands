extends Node
## Loading movie per zone. Lost in Astral's own game.exe (1.02, 4ea40b..)
## shows progres2 for gipat and gipat2 and progres5 for jigran; the base
## game.exe (595080) knows gipat, ingos and suslanger only. Every chosen movie
## must exist in the campaign's data.
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

const BY_ALLOD := {"gipat": "progres2", "gipat2": "progres2", "ingos": "progres3", "suslanger": "progres4", "jigran": "progres5"}

func _ready() -> void:
	var campaign := CampaignMap.load_from(GameData.texts)
	var astral := GameData.campaign_id != CampaignProfile.ORIGINAL
	var seen := {}
	for id: String in campaign.zones:
		var zone: Dictionary = campaign.zones[id]
		var allod := String(zone.get("allod", "")).to_lower()
		seen[allod] = true
		var expected := "progres1" if id in ["gz1g", "bz7g"] else String(BY_ALLOD.get(allod, "progres"))
		var movie := LoadingScreen.movie_for(zone)
		check(movie == expected, "%s (%s) loads with %s, got %s" % [id, allod, expected, movie])
		check(GameFiles.exists(GameData.root.path_join("movies/%s.bik" % movie)), "%s movie %s exists" % [id, movie])
	if astral:
		check(seen.has("gipat2") and seen.has("jigran"), "Lost in Astral has gipat2 and jigran zones")
	else:
		check(not seen.has("gipat2") and not seen.has("jigran"), "the base campaign has neither allod")
	print("LOADING_MOVIES ", checks, " checks ", failures, " failures")
	get_tree().quit(0 if failures == 0 else 1)
