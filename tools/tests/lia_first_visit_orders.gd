extends "lia_campaign_support.gd"
## Every Lost in Astral map against every quest, fortune or dialogue flag its
## scripts read that is granted elsewhere (another map's script or a dialogue
## reward): the first visit with the flag already set, compared with the flag
## set after an earlier visit. Both orders visit the map, wait elsewhere and
## return, so only the moment the flag is set differs. The Wormfaces' Riddle
## locked only in the first order; any outcome that depends on the order shows
## as a difference in quest state: the party, levers (state, usable), waiting quest
## watchers (threads whose condition reads a q./b./z. flag or a lever state,
## without random choices; a watcher and its "a" twin count as one), non-party
## units (dead, hidden, faction), placed objects, quest items, every q./b./z.
## flag and the map's own variables. Cases come from the shipped data.
## --shard=K/N runs every N-th case from K (0-based); --only=TEXT runs only
## the cases whose label ("zone flag=value") contains TEXT.

const GET := "(?i)GSGetVar\\(\\s*\\d+\\s*,\\s*\"([^\"]+)\"\\s*\\)"
const SET := "(?i)GSSetVar(?:Max)?\\(\\s*\\d+\\s*,\\s*\"([^\"]+)\"\\s*,\\s*([0-9.]+)\\s*\\)"
## Party per island: the chapter's travelling party (lia_campaign_* fixtures).
const PARTY := {"suslanger":["FSusel","Hero2","Hero2","merc2"],
	"gipat2":["Gipat","Hero3","Hero","merc2g"], "ingos":["Gipat","Hero3","Hero","merc2g"],
	"jigran":["Gipat","Hero3","Hero","merc2g"]}
## Where the party waits between the two visits of the second order.
const AWAY := {"suslanger":["bz2h","bz5h"], "gipat2":["bz11g","bz13g"],
	"ingos":["bz21k","bz22k"], "jigran":["bz31j","bz32j"]}
## Script ticks after each arrival (0.055 s each): long enough for the
## authored Sleep(20)-style delays before a quest's first objective.
const SETTLE := 120
## Reviewed order differences: case label -> [reason, the differing entries
## ("section id")]. Every reason explains why no quest is lost; any other
## difference in the same case still fails.
const KNOWN := {
	"gz1h b.skelet.fq2=2.0": ["Portal is the chapter's starting map: the fortune is bought "
		+"after the first visit (lia_kel_fortune_orders covers that order)",["levers 2261640"]],
	"bz2h q.gz3h.q13h=2.0": ["q13h comes from brief_37, long after the Elder's brief_9 in this first "
		+"village; only with brief_9 unset does VCheck#1#0 hide merc10 again",["units 1000295968"]],
	"bz5h b.merc8.brief_24=1.0": ["merc8 (1000059191) is on the base map and stays in both orders; "
		+"AddMob(bz5hmerc8.mob) spawns a second copy whose runtime id a revisit does not restore",["units 1500000640"]],
	"bz12g q.gz7g.q21g=2.0": ["the Witch is shown in both orders; VCheck#0#0 waits for q21g = 0, "
		+"which GSSetVarMax never sets again",["threads VCheck#0#0"]],
	"bz12g q.gz7g.q21g=3.0": ["q21g = 3 is the escort's death, followed by EndOfGame",
		["threads VCheck#0#0","units 1000066007"]],
	"gz11d2 z.gz9g=2.0": ["bz8g sets z.gz9g to 2 and back to 0 five ticks later in one "
		+"conversation handler; the party cannot arrive while it is 2",["threads Start"]],
}

var shard := 0
var shards := 1
var only := ""
var zone_vars := {}
var watchers := {}   # zone -> {script name: true} compared by snapshot()

func _ready() -> void: run.call_deferred()

func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--shard="):
			var parts := arg.trim_prefix("--shard=").split("/")
			shard = int(parts[0]); shards = int(parts[1])
		elif arg.begins_with("--only="):
			only = arg.trim_prefix("--only=")
	boot()
	var all := cases()
	check(all.size() > 150,"shipped LiA data yields the expected order cases (%d)" % all.size())
	var mine := 0
	for i in all.size():
		if i % shards != shard: continue
		if not only.is_empty() and not ("%s %s=%s" % [all[i][0],all[i][2],all[i][3]]).contains(only): continue
		mine += 1
		await run_case(all[i])
	print("FIRST_VISIT_CASES ",mine," of ",all.size())
	check(mine > 0,"the shard and --only filter select at least one case")
	await finish("LIA_FIRST_VISIT_ORDERS","Shard %d/%d: %d of %d map/flag/value cases, each map entered through its authored WorldScript twice (flag set before the first visit, or during a stay elsewhere after it; both orders return to the map), comparing levers, waiting quest watchers, non-party units, objects, quest items, quest/dialogue/zone flags and the map's own variables. Direct map entry, frozen units; quest objectives themselves are covered by the lia_kel_/lia_campaign_ programs." % [shard,shards,mine,all.size()])

## [zone, island, flag, value] for every flag a map reads that something
## outside it grants, with each granted value. Sorted for stable shards.
func cases() -> Array:
	var get_re := RegEx.create_from_string(GET)
	var set_re := RegEx.create_from_string(SET)
	var texts := {}
	for id: String in s.campaign.zones:
		var z: Dictionary = s.campaign.zones[id]
		if not String(z.get("type","")) in ["game","brief"] or not PARTY.has(String(z.get("allod",""))): continue
		var mob := String(z.get("mob",""))
		if mob.is_empty() or GameData.read_file("maps/%s.mob" % mob).is_empty(): continue
		texts[id] = EIMob.load_bytes(GameData.read_file("maps/%s.mob" % mob)).script_text
	var sets := {}   # flag -> zone -> {value}
	for id: String in texts:
		var own := {}
		for m: RegExMatch in set_re.search_all(texts[id]):
			sets.get_or_add(m.get_string(1),{}).get_or_add(id,{})[float(m.get_string(2))] = true
			own[m.get_string(1)] = true
		zone_vars[id] = own.keys()
		watchers[id] = quest_watchers(texts[id])
	var grants := {}   # flag -> {value} from dialogue rewards
	for row: Dictionary in GameData.db.table("briefings"):
		for field: String in ["give_quests","give_quests2","open_zones","unknown2"]:
			var v = row.get(field)
			for q in (v if v is Array else [v]):
				if q == null or str(q).is_empty(): continue
				grants.get_or_add(str(q),{})[2.0 if field in ["give_quests2","unknown2"] else 1.0] = true
	var result := []
	var ids := texts.keys(); ids.sort()
	for id: String in ids:
		var reads := {}
		for m: RegExMatch in get_re.search_all(texts[id]): reads[m.get_string(1)] = true
		var keys := reads.keys(); keys.sort()
		for key: String in keys:
			var values: Dictionary = grants.get(key,{}).duplicate()
			for other: String in sets.get(key,{}):
				if other != id: values.merge(sets[key][other])
			values.erase(0.0)
			var sorted := values.keys(); sorted.sort()
			for value: float in sorted:
				result.append([id,String(s.campaign.zones[id].allod),key,value])
	return result

func run_case(c: Array) -> void:
	var label := "%s %s=%s" % [c[0],c[2],c[3]]
	var before := await order(c,true)
	var after := await order(c,false)
	var diff := differences(before,after)
	if not diff.is_empty():
		print("ORDER_DIFF ",JSON.stringify({"case":label,"diff":diff}))
	if KNOWN.has(label):
		var keys := diff.map(func(d): return " ".join(String(d[0]).split(" ").slice(0,2)))
		check(keys == KNOWN[label][1],label+": only the reviewed difference ("+KNOWN[label][0]+")")
		return
	check(diff.is_empty(),label+": same map state whether set before or after the first visit")

## Scripts whose condition reads a quest, dialogue or zone flag or a lever
## state, and that make no random choice (random chests and map variants).
func quest_watchers(text: String) -> Dictionary:
	var result := {}
	var heads := RegEx.create_from_string("\\nScript\\s+(\\S+)\\s*\\n\\(").search_all(text)
	var condition := RegEx.create_from_string("if\\s*\\(([\\s\\S]*?)\\n\\s*\\)\\s*\\n\\s*then")
	for i in heads.size():
		var end := heads[i+1].get_start() if i+1 < heads.size() else text.length()
		var body := text.substr(heads[i].get_start(),end-heads[i].get_start())
		if "Rand" in body: continue
		var watch := condition.search(body)
		if watch == null: continue
		var cond := watch.get_string(1)
		if "\"q." in cond or "\"b." in cond or "\"z." in cond or "GetLeverState" in cond:
			result[heads[i].get_string(1)] = true
	return result

## A watcher and its alternating twin (VCheck#2#1 / VCheck#2#1a) are one.
func family(name: String) -> String:
	return name.left(-1) if name.length() > 1 and name[-1] in "abcd" and name[-2] in "0123456789" else name

## One fresh campaign. Both orders visit the map, stay elsewhere and return;
## the flag is set before the first visit or during the stay.
func order(c: Array, before: bool) -> Dictionary:
	await boot_again()
	var p: Array = PARTY[c[1]]
	chapter(p[0],p[1],p[2],p[3])
	if before: s.state.set_var(0,c[2],c[3])
	if not await arrive(c[0]): return {"error":"first visit"}
	var away: String = AWAY[c[1]][1] if AWAY[c[1]][0] == c[0] else AWAY[c[1]][0]
	if not await arrive(away): return {"error":"stay at "+away}
	if not before: s.state.set_var(0,c[2],c[3])
	if not await arrive(c[0]): return {"error":"return visit"}
	return snapshot()

## Enter through the map's WorldScript; a scripted departure (LeaveToZone)
## is allowed to finish, so both orders end wherever the scripts send them.
func arrive(zone: String) -> bool:
	await s.enter_zone(zone,1,false)
	if s.world == null: return false
	freeze(); ticks(SETTLE)
	await frames(3)
	for i in 1200:
		if not s.loading_game and s.world != null: break
		await frames(1)
	if s.world == null or s.loading_game: return false
	freeze()
	vm().briefings.active = ""; vm().briefings._pending_dialog.clear()
	game.hud._dialog.hide()
	return true

func snapshot() -> Dictionary:
	var w := s.world
	var levers := {}
	for id: int in w.levers:
		levers[str(id)] = [int(w.levers[id].get("state",0)),w.lever_sys.usable(id)]
	var threads := {}
	var mine: Dictionary = watchers.get(s.zone_id,{})
	for i in vm().instances:
		if mine.has(i.sname) and (not i.killed or not i.frames.is_empty()):
			threads[family(i.sname)] = int(threads.get(family(i.sname),0))+1
	var units := {}
	var party := []
	for id: int in w.units:
		var u: GameUnit = w.units[id]
		if u.has_meta("hero"):
			party.append(String(u.info.get("name","")))
			continue
		units["%d %s" % [id,u.info.get("name","")]] = [u.dead,u.hidden,u.faction]
	var objects: Array = w.objects.keys().map(func(id): return str(id)); objects.sort()
	var vars := {}
	for key: String in zone_vars.get(s.zone_id,[]): vars[key] = value(key)
	for key: String in s.state.vars:
		if key.begins_with("0:q.") or key.begins_with("0:b.") or key.begins_with("0:z."): vars[key.substr(2)] = value(key.substr(2))
	var items: Array = s.state.quest_items.keys(); items.sort()
	party.sort()
	return {"zone":s.zone_id,"party":party,"levers":levers,"threads":threads,"units":units,"objects":objects,"vars":vars,"items":items}

## Readable differences, at most a few per section.
func differences(a: Dictionary, b: Dictionary) -> Array:
	var out := []
	for section: String in ["error","zone","party","items","objects"]:
		if a.get(section) != b.get(section):
			out.append([section,str(a.get(section)).left(300),str(b.get(section)).left(300)])
	for section: String in ["levers","threads","units","vars"]:
		var x: Dictionary = a.get(section,{}); var y: Dictionary = b.get(section,{})
		var keys := x.keys()
		for k in y:
			if not x.has(k): keys.append(k)
		keys.sort()
		var n := 0
		for k in keys:
			if x.get(k) != y.get(k):
				n += 1
				if n <= 6: out.append([section+" "+str(k),x.get(k),y.get(k)])
		if n > 6: out.append([section,"%d more" % (n-6)])
	return out
